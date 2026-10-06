import Foundation

struct ItemSorter {
    // Bug: wrong sorting logic — should rank the highest score first, but this sorts ascending.
    static func sortedByScore(_ entries: [Entry]) -> [Entry] {
        entries.sorted { $0.score < $1.score }
    }
}
