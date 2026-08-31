//
//  Hashing.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  Two hashes, because most same-size files differ in their first
//  kilobytes: a cheap edge sample (first and last 64 KB) splits those
//  without reading the middle, and only what survives gets the full
//  streaming SHA-256. Nothing is ever loaded whole — a 10 GB video
//  passes through in megabyte bites.
//

import CryptoKit
import Foundation

enum Hashing {

    static let edgeBytes = 64 << 10
    static let chunkBytes = 1 << 20

    /// SHA-256 of the first and last 64 KB (which is the whole file when
    /// it is small), prefixed with the size so equal edges of unequal
    /// files can never meet.
    static func edgeHash(of path: String, size: Int64) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }
        let head = try handle.read(upToCount: edgeBytes) ?? Data()
        hasher.update(data: head)
        if size > Int64(edgeBytes) {
            try handle.seek(toOffset: UInt64(max(0, size - Int64(edgeBytes))))
            let tail = try handle.read(upToCount: edgeBytes) ?? Data()
            hasher.update(data: tail)
        }
        return hex(hasher.finalize())
    }

    /// Streaming SHA-256 of the whole file.
    static func fullHash(of path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkBytes), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
