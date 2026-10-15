//
//  DuplicateFinder.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  The scan itself: size groups, edge samples, then full SHA-256 —
//  a file is only called a copy when every byte agrees.
//

import Foundation

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
                // An iCloud placeholder holds no bytes here: hashing it would
                // download it, and listing a placeholder folder downloads that.
                if Placeholder.isDataless(url.path) {
                    if values?.isDirectory == true { walker.skipDescendants() }
                    continue
                }
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
