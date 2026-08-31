//
//  DuplicateGroup.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  Several paths, one content — and which copy a rule keeps.
//

import Foundation

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
        KeepPolicy.survivor(of: files, under: rule)
    }

    /// Every copy the rule lets go.
    public func removable(under rule: KeepRule) -> [FileRecord] {
        KeepPolicy.removable(of: files, under: rule)
    }
}
