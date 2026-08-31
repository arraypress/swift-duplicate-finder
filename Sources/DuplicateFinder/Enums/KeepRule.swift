//
//  KeepRule.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  How to choose the copy that stays when duplicates go.
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
