import SwiftUI

// Bug: unstable identity — a fresh UUID is generated every time this wrapper is created (i.e. on every
// render), so SwiftUI can't tell rows apart across diffs.
struct EntryRow: Identifiable {
    let id = UUID()
    let entry: Entry
}

struct ContentView: View {
    // Bug: @ObservedObject on a view-owned object — this view model is recreated on every re-render of
    // ContentView, losing its state. Should be @StateObject.
    @ObservedObject var viewModel = ItemListViewModel()

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.entries.map(EntryRow.init)) { row in
                    HStack {
                        Text(row.entry.label)
                        Spacer()
                        Text("\(row.entry.score)")
                    }
                }
            }
            .navigationTitle("Items")
        }
    }
}

#Preview {
    ContentView()
}
