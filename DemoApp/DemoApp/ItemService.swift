import Foundation

// Bug (by omission): this service has no test coverage — a target for generated tests.
final class ItemService {
    private let legacyHelper = LegacyHelper()

    func fetchLatestResult(completion: @escaping (String) -> Void) {
        legacyHelper.fetchData { result in
            // Missing nullability annotations on LegacyHelper's completion block force this unwrap.
            completion(result ?? "")
        }
    }

    func loadEntries() -> [Entry] {
        [
            Entry(label: "Entry A", score: 589),
            Entry(label: "Entry B", score: 526),
            Entry(label: "Entry C", score: 505)
        ]
    }
}
