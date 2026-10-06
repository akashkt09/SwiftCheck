import SwiftUI

struct FileTreeView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.fileTree.isEmpty {
            ContentUnavailableView("No Folder Open", systemImage: "folder", description: Text("Open a project folder to get started."))
        } else {
            List(model.fileTree, children: \.children, selection: Binding(
                get: { model.selectedFilePath },
                set: { newValue in
                    if let newValue, let node = findNode(newValue, in: model.fileTree) {
                        model.selectFile(node)
                    }
                }
            )) { node in
                Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                    .tag(node.path)
            }
            .listStyle(.sidebar)
        }
    }

    private func findNode(_ path: String, in nodes: [FileNode]) -> FileNode? {
        for node in nodes {
            if node.path == path { return node }
            if let children = node.children, let match = findNode(path, in: children) {
                return match
            }
        }
        return nil
    }
}
