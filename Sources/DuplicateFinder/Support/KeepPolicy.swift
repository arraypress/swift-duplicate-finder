//
//  KeepPolicy.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  Which copy a rule keeps. The tie-breaks are the whole policy — two
//  copies modified in the same second are separated by path — so the
//  selection lives here as pure functions over a plain array, where a
//  test can hand it hand-built records and pin every branch.
//

import Foundation

/// Selecting the copy a keep rule preserves.
enum KeepPolicy {

    /// The copy the rule keeps. `files` is ordered as ``DuplicateGroup``
    /// stores it — oldest first, ties broken by shorter path then
    /// lexical — which is what lets `oldest` take the head directly.
    static func survivor(of files: [FileRecord], under rule: KeepRule) -> FileRecord {
        switch rule {
        case .oldest: return files.first!
        case .newest: return files.max { ($0.modified, $1.path.count) < ($1.modified, $0.path.count) }!
        case .shortestPath: return files.min { ($0.path.count, $0.path) < ($1.path.count, $1.path) }!
        }
    }

    /// Every copy the rule lets go.
    static func removable(of files: [FileRecord], under rule: KeepRule) -> [FileRecord] {
        let keep = survivor(of: files, under: rule)
        return files.filter { $0.path != keep.path }
    }
}
