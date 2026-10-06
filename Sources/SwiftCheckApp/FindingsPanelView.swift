import SwiftUI
import QACore

private enum FindingsTab: String, CaseIterable {
    case failures = "Failures"
    case improvements = "Improvements"
}

struct FindingsPanelView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab: FindingsTab = .failures

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(FindingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            Divider()

            switch tab {
            case .failures: failuresTab
            case .improvements: improvementsTab
            }

            Spacer()
        }
    }

    // MARK: - Failures

    @ViewBuilder
    private var failuresTab: some View {
        if model.failures.isEmpty {
            ContentUnavailableView("No Failures", systemImage: "checkmark.circle", description: Text("Run tests to see findings here."))
        } else {
            List(Array(model.failures.enumerated()), id: \.offset, selection: Binding(
                get: { model.selectedFailure.flatMap { f in model.failures.firstIndex(where: { $0.file == f.file && $0.line == f.line && $0.message == f.message }) } },
                set: { index in
                    if let index { model.selectedFailure = model.failures[index] }
                }
            )) { _, failure in
                VStack(alignment: .leading, spacing: 2) {
                    Text(failure.file.map { "\($0):\(failure.line.map(String.init) ?? "?")" } ?? "Unknown location")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(failure.message)
                        .font(.callout)
                        .lineLimit(2)
                }
                .tag(model.failures.firstIndex(where: { $0.file == failure.file && $0.line == failure.line && $0.message == failure.message }) ?? 0)
            }
            .frame(minHeight: 120, maxHeight: 200)

            Divider()

            if let failure = model.selectedFailure {
                failureDetail(for: failure)
            }
        }
    }

    @ViewBuilder
    private func failureDetail(for failure: Failure) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(failure.file.map { "\($0):\(failure.line.map(String.init) ?? "?")" } ?? "Unknown location")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(failure.message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Text("Diagnostic only — no fix is proposed here. Select the failing file in the tree, switch to the Improvements tab, or use \"Ask Claude to Write Tests\" to add coverage.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(8)
    }

    // MARK: - Improvements

    @ViewBuilder
    private var improvementsTab: some View {
        if let path = model.selectedFilePath {
            VStack(alignment: .leading, spacing: 8) {
                Text((path as NSString).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding([.horizontal, .top], 8)

                if let diff = model.proposedImprovementDiff {
                    ScrollView {
                        Text(highlightSwiftCode(diff))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                    .frame(maxHeight: 300)
                    .background(XcodeTheme.background)

                    HStack {
                        Button("Reject") { model.rejectImprovement() }
                        Button("Approve") { Task { await model.approveImprovement() } }
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(.horizontal, 8)
                } else {
                    Button {
                        Task { await model.proposeImprovement(for: path) }
                    } label: {
                        Label("Suggest Improvements", systemImage: "wand.and.stars")
                    }
                    .disabled(model.isBusy || !model.hasClaudeClient)
                    .padding(.horizontal, 8)

                    if !model.hasClaudeClient {
                        Text("ANTHROPIC_API_KEY is not set.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                    }

                    if let status = model.improvementStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                    }
                }
            }
        } else {
            ContentUnavailableView("No File Selected", systemImage: "wand.and.stars", description: Text("Select a file in the tree to review it for improvements."))
        }
    }
}
