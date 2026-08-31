//
//  DuplicateFinderTests.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  A synthetic tree with every trap in it: true duplicates, a same-size
//  impostor, a same-edges impostor, a hard link, a too-small file, an
//  excluded folder. The scan must call only the true copies duplicates,
//  and say the same thing twice.
//

import Foundation
import XCTest
@testable import DuplicateFinder

final class DuplicateFinderTests: XCTestCase {

    private var root: URL!
    private let options = ScanOptions(minimumBytes: 1 << 20)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("dupe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("node_modules"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// Deterministic 2 MB of pseudo-noise.
    private func noise(seed: UInt8) -> Data {
        var bytes = [UInt8](repeating: 0, count: 2 << 20)
        var state = UInt64(seed) &* 6_364_136_223_846_793_005 &+ 1
        for i in bytes.indices {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes[i] = UInt8(truncatingIfNeeded: state >> 33)
        }
        return Data(bytes)
    }

    private func write(_ data: Data, _ name: String, modified: Date? = nil) throws -> URL {
        let url = root.appendingPathComponent(name)
        try data.write(to: url)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        return url
    }

    func testFindsOnlyTrueDuplicatesAndCollapsesHardLinks() throws {
        let content = noise(seed: 1)
        let born = Date(timeIntervalSince1970: 1_000_000)
        _ = try write(content, "a.bin", modified: born)
        _ = try write(content, "b.bin", modified: born.addingTimeInterval(60))
        _ = try write(content, "sub/c.bin", modified: born.addingTimeInterval(120))
        _ = try write(noise(seed: 2), "same-size-different.bin")                  // size collides, bytes differ
        var edges = noise(seed: 1)                                               // same first/last 64 KB…
        edges.replaceSubrange(1 << 20 ..< (1 << 20) + 8, with: Data([9, 9, 9, 9, 9, 9, 9, 9]))
        _ = try write(edges, "same-edges-different.bin")                         // …different middle
        _ = try write(noise(seed: 3).prefix(1024), "too-small.bin")              // under the floor
        _ = try write(content, "node_modules/ignored.bin")                       // excluded folder
        try FileManager.default.linkItem(atPath: root.appendingPathComponent("a.bin").path,
                                         toPath: root.appendingPathComponent("a-hardlink.bin").path)

        let report = try DuplicateFinder.find(in: [root], options: options)
        XCTAssertEqual(report.groups.count, 1, "\(report.groups.map { $0.files.map(\.path) })")
        let group = report.groups[0]
        XCTAssertEqual(group.files.count, 3, "a, b and sub/c — the hard link is not a fourth copy")
        XCTAssertEqual(group.files.map { ($0.path as NSString).lastPathComponent }, ["a.bin", "b.bin", "c.bin"], "oldest first")
        XCTAssertEqual(group.reclaimableBytes, Int64(content.count) * 2)
        XCTAssertTrue(group.files[0].hardlinkedPaths.contains { $0.hasSuffix("a-hardlink.bin") },
                      "the hard link is reported as a second name, not a copy")
        XCTAssertGreaterThan(report.scannedFiles, 3)
        XCTAssertGreaterThan(report.hashedBytes, 0)
        XCTAssertLessThan(report.hashedBytes, report.scannedBytes, "the impostors must not be fully hashed")
    }

    func testKeepRulesAndPlan() throws {
        let content = noise(seed: 4)
        let born = Date(timeIntervalSince1970: 2_000_000)
        _ = try write(content, "deep-old.bin", modified: born)
        _ = try write(content, "sub/newer.bin", modified: born.addingTimeInterval(600))
        _ = try write(content, "n.bin", modified: born.addingTimeInterval(300))

        let report = try DuplicateFinder.find(in: [root], options: options)
        let group = try XCTUnwrap(report.groups.first)
        XCTAssertTrue(group.survivor(under: .oldest).path.hasSuffix("deep-old.bin"))
        XCTAssertTrue(group.survivor(under: .newest).path.hasSuffix("newer.bin"))
        XCTAssertTrue(group.survivor(under: .shortestPath).path.hasSuffix("n.bin"))
        let plan = DeletionPlan.make(from: report, keep: .oldest)
        XCTAssertEqual(plan.count, 2)
        XCTAssertEqual(plan.bytes, Int64(content.count) * 2)
        XCTAssertFalse(plan.entries[0].remove.contains { $0.path.hasSuffix("deep-old.bin") })
    }

    func testDeterministicAcrossRuns() throws {
        for seed in UInt8(5)...8 {
            _ = try write(noise(seed: seed), "x\(seed).bin")
            _ = try write(noise(seed: seed), "sub/y\(seed).bin")
        }
        let first = try DuplicateFinder.find(in: [root], options: options)
        let second = try DuplicateFinder.find(in: [root], options: options)
        XCTAssertEqual(first.groups.map(\.hash), second.groups.map(\.hash))
        XCTAssertEqual(first.groups.map { $0.files.map(\.path) }, second.groups.map { $0.files.map(\.path) })
    }

    func testMinimumSizeAndHiddenAndSymlinks() throws {
        let content = noise(seed: 9)
        _ = try write(content, "one.bin")
        _ = try write(content, "two.bin")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.bin"),
            withDestinationURL: root.appendingPathComponent("one.bin"))
        let report = try DuplicateFinder.find(in: [root], options: options)
        XCTAssertEqual(report.groups.first?.files.count, 2, "a symlink is a reference, not a copy")
        let raised = ScanOptions(minimumBytes: 4 << 20)
        XCTAssertEqual(try DuplicateFinder.find(in: [root], options: raised).groups.count, 0)
    }

    /// The two hashes carry the honesty: identical files agree on both;
    /// same edges with a different middle pass the cheap gate and fail
    /// the full one — exactly the case the edge sample exists to defer.
    func testEdgeHashDefersAndFullHashDecides() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let edge = 64 << 10
        var a = Data(repeating: 0xAB, count: edge) + Data(repeating: 0x01, count: edge) + Data(repeating: 0xCD, count: edge)
        var b = Data(repeating: 0xAB, count: edge) + Data(repeating: 0x02, count: edge) + Data(repeating: 0xCD, count: edge)
        let pa = dir.appendingPathComponent("a.bin"), pb = dir.appendingPathComponent("b.bin"), pc = dir.appendingPathComponent("c.bin")
        try a.write(to: pa); try b.write(to: pb); try a.write(to: pc)
        let size = Int64(a.count)
        let ea = try Hashing.edgeHash(of: pa.path, size: size)
        let eb = try Hashing.edgeHash(of: pb.path, size: size)
        let ec = try Hashing.edgeHash(of: pc.path, size: size)
        XCTAssertEqual(ea, eb, "same edges must pass the cheap gate together")
        XCTAssertEqual(ea, ec)
        XCTAssertNotEqual(try Hashing.fullHash(of: pa.path), try Hashing.fullHash(of: pb.path), "the middle differs; only the full hash may say so")
        XCTAssertEqual(try Hashing.fullHash(of: pa.path), try Hashing.fullHash(of: pc.path))
        _ = a; _ = b
    }

    func testKeepPolicyTieBreaksAlone() {
        // The policy pinned on hand-built records — no filesystem, no scan.
        func record(_ path: String, at t: TimeInterval) -> FileRecord {
            FileRecord(path: path, size: 1, modified: Date(timeIntervalSince1970: t), device: 1, inode: 1)
        }
        let sameTime = [record("/x/aaaa", at: 100), record("/x/b", at: 100)]
        XCTAssertEqual(KeepPolicy.survivor(of: sameTime, under: .newest).path, "/x/b",
                       "equal dates fall back to the shorter path")
        let staggered = [record("/old/a", at: 100), record("/mid/bbbbbbbbbb", at: 200), record("/new/c", at: 300)]
        XCTAssertEqual(KeepPolicy.survivor(of: staggered, under: .oldest).path, "/old/a")
        XCTAssertEqual(KeepPolicy.survivor(of: staggered, under: .newest).path, "/new/c")
        let lexical = [record("/x/b", at: 100), record("/y/a", at: 100)]
        XCTAssertEqual(KeepPolicy.survivor(of: lexical, under: .shortestPath).path, "/x/b")
        XCTAssertEqual(KeepPolicy.removable(of: staggered, under: .newest).map(\.path).sorted(),
                       ["/mid/bbbbbbbbbb", "/old/a"])
    }
}
