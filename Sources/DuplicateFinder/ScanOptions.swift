//
//  ScanOptions.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  What a scan looks at. The defaults skip the places where identical
//  files are the point, not a problem — version control objects, package
//  caches, build products — and everything too small to be worth a
//  person's attention.
//

import Foundation

/// How a scan walks and what it keeps.
public struct ScanOptions: Sendable {

    /// Files smaller than this are not candidates. Duplicates below a
    /// megabyte are rarely worth the risk of deleting the wrong one.
    public var minimumBytes: Int64

    /// Whether hidden files and folders are walked.
    public var includeHidden: Bool

    /// Whether a symbolic link to a file is followed and treated as the
    /// file it points at. Off, links are reported by nobody: a link is a
    /// reference, not a copy.
    public var followSymlinks: Bool

    /// Directory names never descended into, wherever they appear.
    public var excludedDirectoryNames: Set<String>

    /// Options with the fleet's defaults.
    public init(minimumBytes: Int64 = 1 << 20,
                includeHidden: Bool = false,
                followSymlinks: Bool = false,
                excludedDirectoryNames: Set<String> = ScanOptions.defaultExcludes) {
        self.minimumBytes = minimumBytes
        self.includeHidden = includeHidden
        self.followSymlinks = followSymlinks
        self.excludedDirectoryNames = excludedDirectoryNames
    }

    /// Where identical files are the point, not a problem.
    public static let defaultExcludes: Set<String> = [
        ".git", ".svn", ".hg", "node_modules", ".build", ".swiftpm", "DerivedData",
        "Caches", ".Trash", ".npm", ".cargo", "Pods", "__pycache__", ".venv", "venv",
    ]
}
