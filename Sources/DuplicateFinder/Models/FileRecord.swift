//
//  FileRecord.swift
//  DuplicateFinder
//
//  Created by David Sherlock on 2026.
//
//  One file as the scan saw it — enough to hash it later, order it
//  deterministically, and recognise a hard link when two paths turn out
//  to be one file.
//

import Foundation

/// One candidate file.
public struct FileRecord: Codable, Sendable, Equatable {

    /// The absolute path.
    public let path: String
    /// Size in bytes.
    public let size: Int64
    /// Last modification.
    public let modified: Date
    /// The device the file lives on — with ``inode``, its identity.
    public let device: Int64
    /// The inode — two paths with the same device and inode are ONE file.
    public let inode: UInt64
    /// Other paths that turned out to be hard links to this same file.
    /// They are not duplicates — deleting one frees nothing.
    public internal(set) var hardlinkedPaths: [String] = []

    /// A record from a path and its attributes.
    public init(path: String, size: Int64, modified: Date, device: Int64, inode: UInt64, hardlinkedPaths: [String] = []) {
        self.path = path
        self.size = size
        self.modified = modified
        self.device = device
        self.inode = inode
        self.hardlinkedPaths = hardlinkedPaths
    }
}
