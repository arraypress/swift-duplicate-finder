//
//  ScanProgress.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  Where a scan is, for a progress bar.
//

import Foundation

/// Where a scan is, for a progress bar.
public struct ScanProgress: Sendable {
    /// `walking`, `sampling` or `hashing`.
    public let phase: String
    /// Items done in this phase.
    public let completed: Int
    /// Items the phase has in all; `0` while unknown.
    public let total: Int
}
