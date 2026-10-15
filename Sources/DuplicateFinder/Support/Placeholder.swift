//
//  Placeholder.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  iCloud Drive's "optimise storage" leaves dataless placeholders: a file
//  whose bytes live in the cloud. Reading one downloads it, so a duplicate
//  scan must never open one — it is not on this disk to be a duplicate of
//  anything.
//

import Darwin
import Foundation

enum Placeholder {

    /// Whether the item at `path` is a dataless placeholder (`SF_DATALESS`),
    /// checked with lstat, which never triggers a download.
    static func isDataless(_ path: String) -> Bool {
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return info.st_flags & UInt32(SF_DATALESS) != 0
    }
}
