import SwiftUI
import QACore

struct InspectorView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if let path = model.selectedFilePath {
            VStack(alignment: .leading, spacing: 0) {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                Divider()
                ScrollView {
                    Group {
                        if let contents = model.selectedFileContents {
                            Text(highlightSwiftCode(contents))
                        } else {
                            Text("Unable to read file.")
                                .foregroundColor(XcodeTheme.plain)
                        }
                    }
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .background(XcodeTheme.background)
                if isGeneratableSource(path) {
                    Divider()
                    testGenerationSection(for: path)
                }
            }
        } else {
            projectSummary
        }
    }

    private func isGeneratableSource(_ path: String) -> Bool {
        path.hasSuffix(".swift") && !path.contains("Tests")
    }

    @ViewBuilder
    private func testGenerationSection(for path: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let code = model.proposedTestCode {
                Text("Proposed tests for \((model.testTargetFile as NSString?)?.lastPathComponent ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    Text(highlightSwiftCode(code))
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                }
                .frame(maxHeight: 200)
                .background(XcodeTheme.background)
                HStack {
                    Button("Reject") { model.rejectGeneratedTests() }
                    Button("Approve") { Task { await model.approveGeneratedTests() } }
                        .keyboardShortcut(.defaultAction)
                }
            } else {
                // Why: a pure code-reading generator would faithfully write tests for a bug as if it were a
                // feature — letting the developer state intended behavior is what lets Claude catch the gap
                // between what the module is supposed to do and what it actually does.
                Text("Explain this module (optional) — Claude will test the behavior you describe, not just the code as written:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: Binding(
                    get: { model.developerNotes },
                    set: { model.developerNotes = $0 }
                ))
                .font(.system(.caption, design: .monospaced))
                .frame(height: 70)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))

                Button {
                    Task { await model.generateTests(for: path) }
                } label: {
                    Label("Ask Claude to Write Tests", systemImage: "sparkles")
                }
                .disabled(model.isBusy || !model.hasClaudeClient)

                if !model.hasClaudeClient {
                    Text("ANTHROPIC_API_KEY is not set.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
    }

    private var projectSummary: some View {
        Form {
            if let project = model.project {
                LabeledContent("Project", value: "\(project.kind.rawValue.capitalized) · \(project.path)")
            } else {
                Text("No project discovered yet.")
                    .foregroundStyle(.secondary)
            }

            if let scheme = model.selectedScheme {
                // Why: the editable picker lives in the toolbar now, where it stays reachable even after
                // a file is selected (this view swaps to the file preview then) — this is just a readout.
                LabeledContent("Scheme", value: scheme)
            }

            if let simulator = model.simulator {
                LabeledContent("Simulator", value: "\(simulator.name)\(simulator.isBooted ? " (booted)" : "")")
            }
        }
        .formStyle(.grouped)
    }
}
