//
//  DuplicateReport.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  What a scan found and how much it looked at.
//

import Foundation

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
