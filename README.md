# Swift Duplicate Finder

Exact duplicate files, found honestly.

```swift
import DuplicateFinder

let report = try DuplicateFinder.find(in: [folder])
for group in report.groups {
    print(group.files.map(\.path), "wastes", group.reclaimableBytes)
}
```

## Features

- 🎯 **Exact means exact** — a file is a duplicate only when its full SHA-256 matches; size and edge samples merely narrow the field
- ⚡ **Reads far less than it looks at** — size groups first (free), then the first and last 64 KB (cheap), and only survivors get the full streaming hash; nothing is ever loaded whole, so a 10 GB file passes in megabyte bites
- 🔗 **Hard links are not duplicates** — two names with one inode collapse into one record carrying its other names; deleting one frees nothing and the report says so
- 🚫 **Skips where copies are the point** — `.git`, `node_modules`, `.build`, caches and friends, by default and configurably
- 📐 **Deterministic** — the same tree reports the same groups in the same order, files oldest-first within each
- 🗑️ **Plans, doesn't delete** — `DeletionPlan` says what a keep rule (`oldest`, `newest`, `shortest-path`) would remove and what it frees; acting on it is the caller's job
- 📦 **Zero dependencies** — Foundation and CryptoKit

## Measured

The fleet's own folder — 1,475 candidate files, 3.86 GB — scans in 0.6 s warm, finding 174 groups and 407 MB reclaimable, with the full hash touching only a fraction of the bytes looked at. The tests walk a tree containing every trap at once: true duplicates, a same-size impostor, a same-edges impostor (identical first and last 64 KB, different middle), a hard link, a too-small file and an excluded folder — and must call only the true copies duplicates, twice, in the same order.

## Requirements

macOS 14+ / iOS 16+, Swift 6.

## License

MIT — see LICENSE.
