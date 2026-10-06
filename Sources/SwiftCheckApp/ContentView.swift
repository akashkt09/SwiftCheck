import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            // Why: NavigationSplitView only gets real drag-to-resize behavior once each column has explicit
            // min/ideal/max width hints — without them the dividers don't feel draggable.
            NavigationSplitView {
                FileTreeView()
                    .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
            } content: {
                InspectorView()
                    .navigationSplitViewColumnWidth(min: 300, ideal: 420, max: 800)
            } detail: {
                FindingsPanelView()
                    .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 600)
            }
            .navigationSplitViewStyle(.balanced)

            Divider()
            ConsoleView()
                .frame(height: 160)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    model.openFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder.badge.plus")
                }
            }
            // Why: lives in the toolbar, not the inspector's project-summary view, so it's reachable
            // regardless of whether a file is selected — the inspector swaps to the file preview as soon
            // as you pick something in the tree, which used to make the scheme unreachable after that.
            ToolbarItem {
                if !model.schemes.isEmpty {
                    Picker("Scheme", selection: Binding(
                        get: { model.selectedScheme ?? model.schemes[0] },
                        set: { model.selectedScheme = $0 }
                    )) {
                        ForEach(model.schemes, id: \.self) { scheme in
                            Text(scheme).tag(scheme)
                        }
                    }
                    .frame(maxWidth: 220)
                    .disabled(model.isBusy)
                }
            }
            ToolbarItem {
                Button {
                    Task { await model.runTests() }
                } label: {
                    Label("Run Tests", systemImage: "play.fill")
                }
                .disabled(model.isBusy || model.project == nil || model.selectedScheme == nil || model.simulator == nil)
            }
            ToolbarItem {
                Button(role: .destructive) {
                    model.cancelCurrentRun()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!model.isBusy)
            }
            ToolbarItem {
                Button {
                    Task { await model.startVisualUIWatch() }
                } label: {
                    Label("Watch UI", systemImage: "eye")
                }
                .disabled(model.isBusy || model.project == nil || model.selectedScheme == nil || model.simulator == nil || !model.hasClaudeClient)
            }
            ToolbarItem(placement: .principal) {
                if model.isBusy {
                    ProgressView()
                        .scaleEffect(0.6)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Text(String(format: "in: %d · out: %d · $%.4f", model.totalInputTokens, model.totalOutputTokens, model.totalCost))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $model.showingUICheck) {
            UICheckResultView()
        }
    }
}
