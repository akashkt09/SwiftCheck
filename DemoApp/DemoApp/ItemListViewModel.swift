import Foundation

final class ItemListViewModel: ObservableObject {
    @Published var entries: [Entry]

    init() {
        entries = ItemSorter.sortedByScore(ItemService().loadEntries())
    }
}
