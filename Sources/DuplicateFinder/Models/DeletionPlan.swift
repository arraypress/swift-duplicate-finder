//
//  DeletionPlan.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  What a deletion would do, before it does it.
//

import Foundation

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
