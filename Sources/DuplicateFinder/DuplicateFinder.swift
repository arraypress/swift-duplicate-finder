//
//  DuplicateFinder.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  Exact duplicates, honestly: size groups, then edge samples, then full
//  SHA-256 — a file is only called a copy of another when every byte
//  agrees. Hard links are collapsed first, because two names for one
//  file is not a duplicate and deleting one frees nothing.
//

import Foundation

/// How to choose the copy that stays.
public enum KeepRule: String, CaseIterable, Codable, Sendable {
    /// The oldest copy is the original.
    case oldest
    /// The newest copy is the one that matters.
    case newest
    /// The copy with the shortest path — usually the one in the tidy place.
    case shortestPath = "shortest-path"
}

/// Several paths, one content.
public struct DuplicateGroup: Codable, Sendable {

    /// Bytes per copy.
    public let size: Int64
    /// The full SHA-256 every member shares.
    public let hash: String
    /// The copies, oldest first (ties: shorter path, then lexical) — at
    /// least two. Hard links to a member ride inside its record.
    public let files: [FileRecord]

    /// What deleting all but one copy frees.
    public var reclaimableBytes: Int64 { size * Int64(files.count - 1) }

    /// The copy a rule keeps.
    public func survivor(under rule: KeepRule) -> FileRecord {
        switch rule {
        case .oldest: return files.first!
        case .newest: return files.max { ($0.modified, $1.path.count) < ($1.modified, $0.path.count) }!
        case .shortestPath: return files.min { ($0.path.count, $0.path) < ($1.path.count, $1.path) }!
        }
    }

    /// Every copy the rule lets go.
    public func removable(under rule: KeepRule) -> [FileRecord] {
        let keep = survivor(under: rule)
        return files.filter { $0.path != keep.path }
    }
}

/// What a scan found and how much it looked at.
public struct DuplicateReport: Codable, Sendable {

    /// Every duplicate group, biggest reclaimable first.
    public let groups: [DuplicateGroup]
    /// Candidate files walked (after size and exclusion filters).
    public let scannedFiles: Int
    /// Their bytes.
    public let scannedBytes: Int64
    /// Bytes actually read for full hashes — usually far less than scanned.
    public let hashedBytes: Int64

    /// What deleting every extra copy would free.
    public var reclaimableBytes: Int64 { groups.reduce(0) { $0 + $1.reclaimableBytes } }
    /// The number of removable copies across all groups.
    public var duplicateFiles: Int { groups.reduce(0) { $0 + $1.files.count - 1 } }
}

/// Where a scan is, for a progress bar.
public struct ScanProgress: Sendable {
    /// `walking`, `sampling` or `hashing`.
    public let phase: String
    /// Items done in this phase.
    public let completed: Int
    /// Items the phase has in all; `0` while unknown.
    public let total: Int
}

/// The scan itself.
public enum DuplicateFinder {

    /// Every candidate file under `roots`, per the options. Hard links are
    /// NOT collapsed here — ``find(in:options:progress:)`` does that.
    public static func gather(_ roots: [URL], options: ScanOptions = ScanOptions()) throws -> [FileRecord] {
        let manager = FileManager.default
        var records: [FileRecord] = []
        for root in roots {
            var walkOptions: FileManager.DirectoryEnumerationOptions = []
            if !options.includeHidden { walkOptions.insert(.skipsHiddenFiles) }
            guard let walker = manager.enumerator(at: root,
                                                  includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey],
                                                  options: walkOptions) else { continue }
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
                if values?.isDirectory == true {
                    if options.excludedDirectoryNames.contains(url.lastPathComponent) { walker.skipDescendants() }
                    continue
                }
                var path = url.path
                if values?.isSymbolicLink == true {
                    guard options.followSymlinks else { continue }
                    path = url.resolvingSymlinksInPath().path
                    var isDirectory: ObjCBool = false
                    guard manager.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
                } else if values?.isRegularFile != true {
                    continue
                }
                guard let attributes = try? manager.attributesOfItem(atPath: path),
                      let size = attributes[.size] as? Int64, size >= options.minimumBytes else { continue }
                records.append(FileRecord(
                    path: url.path,
                    size: size,
                    modified: attributes[.modificationDate] as? Date ?? .distantPast,
                    device: (attributes[.systemNumber] as? Int64) ?? Int64((attributes[.systemNumber] as? Int) ?? 0),
                    inode: (attributes[.systemFileNumber] as? UInt64) ?? UInt64((attributes[.systemFileNumber] as? Int) ?? 0)
                ))
            }
        }
        return records.sorted { $0.path < $1.path }
    }

    /// Finds exact duplicates under `roots`.
    ///
    /// - Parameters:
    ///   - roots: Folders to walk.
    ///   - options: What to look at.
    ///   - progress: Told as phases advance, for a bar.
    /// - Returns: The groups, biggest reclaimable first, deterministically
    ///   ordered — the same tree reports the same thing in the same order.
    public static func find(in roots: [URL], options: ScanOptions = ScanOptions(),
                            progress: ((ScanProgress) -> Void)? = nil) throws -> DuplicateReport {
        progress?(ScanProgress(phase: "walking", completed: 0, total: 0))
        let all = try gather(roots, options: options)
        let scannedBytes = all.reduce(0) { $0 + $1.size }

        // Size is the free filter: different sizes cannot be copies.
        var bySize: [Int64: [FileRecord]] = [:]
        for record in all { bySize[record.size, default: []].append(record) }
        var candidates = bySize.values.filter { $0.count > 1 }

        // Two names, one inode: a hard link, not a duplicate. Collapse each
        // linked set into one record carrying the other names.
        candidates = candidates.map { group in
            var byIdentity: [String: FileRecord] = [:]
            // The representative name is the tidy one: shortest path first,
            // so `a.bin` speaks for `a-hardlink.bin` and not the other way.
            for record in group.sorted(by: { ($0.path.count, $0.path) < ($1.path.count, $1.path) }) {
                let identity = "\(record.device):\(record.inode)"
                if var existing = byIdentity[identity] {
                    existing.hardlinkedPaths.append(record.path)
                    byIdentity[identity] = existing
                } else {
                    byIdentity[identity] = record
                }
            }
            return Array(byIdentity.values)
        }
        .filter { $0.count > 1 }

        // Edge sample: split same-size files without reading their middles.
        let sampleTotal = candidates.reduce(0) { $0 + $1.count }
        var sampled = 0
        var edgeGroups: [[FileRecord]] = []
        for group in candidates {
            var byEdge: [String: [FileRecord]] = [:]
            for record in group {
                if let edge = try? Hashing.edgeHash(of: record.path, size: record.size) {
                    byEdge[edge, default: []].append(record)
                }
                sampled += 1
                progress?(ScanProgress(phase: "sampling", completed: sampled, total: sampleTotal))
            }
            edgeGroups.append(contentsOf: byEdge.values.filter { $0.count > 1 })
        }

        // Full hash: the only thing that may call two files identical.
        let hashTotal = edgeGroups.reduce(0) { $0 + $1.count }
        var hashed = 0
        var hashedBytes: Int64 = 0
        var groups: [DuplicateGroup] = []
        for group in edgeGroups {
            var byHash: [String: [FileRecord]] = [:]
            for record in group {
                if let hash = try? Hashing.fullHash(of: record.path) {
                    byHash[hash, default: []].append(record)
                    hashedBytes += record.size
                }
                hashed += 1
                progress?(ScanProgress(phase: "hashing", completed: hashed, total: hashTotal))
            }
            for (hash, members) in byHash where members.count > 1 {
                let ordered = members.sorted {
                    ($0.modified, $0.path.count, $0.path) < ($1.modified, $1.path.count, $1.path)
                }
                groups.append(DuplicateGroup(size: ordered[0].size, hash: hash, files: ordered))
            }
        }
        groups.sort { ($0.reclaimableBytes, $1.hash) > ($1.reclaimableBytes, $0.hash) }
        return DuplicateReport(groups: groups, scannedFiles: all.count, scannedBytes: scannedBytes, hashedBytes: hashedBytes)
    }
}

/// What a deletion would do, before it does it.
public struct DeletionPlan: Codable, Sendable {

    /// One group's fate.
    public struct Entry: Codable, Sendable {
        /// The copy that stays.
        public let keep: FileRecord
        /// The copies that go.
        public let remove: [FileRecord]
    }

    /// Every group with something to remove.
    public let entries: [Entry]

    /// Bytes freed if the plan is carried out.
    public var bytes: Int64 { entries.reduce(0) { $0 + $1.remove.reduce(0) { $0 + $1.size } } }
    /// Files removed if the plan is carried out.
    public var count: Int { entries.reduce(0) { $0 + $1.remove.count } }

    /// The plan a report and a rule imply.
    public static func make(from report: DuplicateReport, keep rule: KeepRule) -> DeletionPlan {
        DeletionPlan(entries: report.groups.map {
            Entry(keep: $0.survivor(under: rule), remove: $0.removable(under: rule))
        })
    }
}
