import SwiftUI

struct ConsoleView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(model.consoleLines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(XcodeTheme.plain)
                            .textSelection(.enabled)
                            .id(index)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }
            .onChange(of: model.consoleLines.count) { _, newCount in
                guard newCount > 0 else { return }
                proxy.scrollTo(newCount - 1, anchor: .bottom)
            }
        }
        .background(XcodeTheme.background)
    }
}
