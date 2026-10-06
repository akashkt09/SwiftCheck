import SwiftUI

struct UICheckResultView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if model.uiWatchActive {
                    Text("Navigate the app in the simulator — click Stop in the toolbar when you're done.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Close") {
                    // Why: the watch loop runs in the background independent of this window — closing it
                    // without stopping first would leave that loop polling invisibly, with no way left to
                    // reach it, and risks a second overlapping session if "Watch UI" gets clicked again.
                    if model.uiWatchActive {
                        model.cancelCurrentRun()
                    }
                    dismiss()
                }
            }
            .padding()
            Divider()

            // Why: hidden while expanded — the whole point of expanding is a larger, distraction-free look
            // at one screenshot, and the thumbnail strip/review controls would just eat into that space.
            if !isExpanded {
                if !model.uiScreenshotPaths.isEmpty {
                    thumbnailStrip
                    Divider()
                }

                if model.isReviewingUIScreenshots {
                    reviewControls
                    Divider()
                }
            }

            HSplitView {
                screenshotPane
                if !isExpanded {
                    analysisPane
                }
            }
        }
        .frame(minWidth: 800, minHeight: 550)
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    private var title: String {
        if model.uiWatchActive {
            return "Watching — \(model.uiScreenshotPaths.count) screen(s) captured so far"
        }
        if model.isReviewingUIScreenshots {
            return "Select screens to review"
        }
        return "Visual UI Check"
    }

    // Why: the sequence is the whole point — a splash screen that never advances shows up here as several
    // identical thumbnails, which is itself a visible symptom even before reading Claude's analysis.
    //
    // Why `.onTapGesture` instead of a `Button` for selection: a `Button` nested in the same `ZStack` as the
    // approve-checkmark `Button` is a known SwiftUI pitfall — overlapping buttons can fight over hit-testing,
    // making taps on the larger one unreliable right where it matters most. `.contentShape(Rectangle())` +
    // `.onTapGesture` sidesteps that entirely by not using a button at all for the "select to preview" action,
    // leaving exactly one real `Button` (the checkmark) with no overlap to contend with.
    @ViewBuilder
    private var thumbnailStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(Array(model.uiScreenshotPaths.enumerated()), id: \.offset) { index, path in
                    let isSelected = index == model.selectedUIScreenshotIndex
                    VStack(spacing: 2) {
                        ZStack(alignment: .topTrailing) {
                            Group {
                                if let image = NSImage(contentsOfFile: path) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 60, height: 100)
                                }
                            }
                            .contentShape(Rectangle())
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                            )
                            .scaleEffect(isSelected ? 1.08 : 1.0)
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    model.selectedUIScreenshotIndex = index
                                }
                            }

                            if model.isReviewingUIScreenshots {
                                Button {
                                    model.toggleUIScreenshotApproval(path)
                                } label: {
                                    Image(systemName: model.approvedUIScreenshots.contains(path) ? "checkmark.circle.fill" : "circle")
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, model.approvedUIScreenshots.contains(path) ? Color.green : Color.secondary)
                                        .background(Circle().fill(.black.opacity(0.4)))
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                            }
                        }
                        Text("\(index + 1)")
                            .font(.caption2)
                            .foregroundStyle(isSelected ? .primary : .secondary)
                    }
                }
            }
            .padding(8)
        }
        .frame(height: 130)
    }

    // Why: tinted and labeled plainly, not just a plain HStack — this is the only place the developer
    // can trigger sending anything to Claude, so it needs to be impossible to overlook once watching stops.
    @ViewBuilder
    private var reviewControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Approve screens above (check mark on each thumbnail), then send them for review.")
                .font(.callout.bold())
            HStack {
                Button("Select All") { model.selectAllUIScreenshots() }
                Button("Select None") { model.deselectAllUIScreenshots() }
                Spacer()
                Text("\(model.approvedUIScreenshots.count) of \(model.uiScreenshotPaths.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Send for Review") {
                    Task { await model.sendApprovedScreenshotsForReview() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.approvedUIScreenshots.isEmpty || model.isBusy)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.12))
    }

    // Why: the expand button and double-click both toggle the same state — common image-viewer convention
    // (double-click to zoom) alongside an explicit, discoverable button for anyone who doesn't know that.
    //
    // Why `GeometryReader` instead of the previous `ScrollView`: a `ScrollView` doesn't give its content a
    // bounded size to fit against in the scrollable direction, so `.resizable() + .aspectRatio(.fit)` had no
    // concrete frame to scale within — the image could render at an arbitrary size instead of showing the
    // simulator's actual screen proportions cleanly. `GeometryReader` hands the image an exact width/height
    // to fit inside, so it's always shown at the real device aspect ratio, fully visible, letterboxed rather
    // than cropped or requiring a scroll.
    @ViewBuilder
    private var screenshotPane: some View {
        GeometryReader { geometry in
            Group {
                if model.uiScreenshotPaths.indices.contains(model.selectedUIScreenshotIndex),
                   let image = NSImage(contentsOfFile: model.uiScreenshotPaths[model.selectedUIScreenshotIndex]) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onTapGesture(count: 2) {
                            withAnimation { isExpanded.toggle() }
                        }
                } else {
                    Text("No screenshot available.")
                        .foregroundStyle(.secondary)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .frame(minWidth: 300)
        .overlay(alignment: .topTrailing) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(10)
            .help(isExpanded ? "Collapse (or double-click the image)" : "Expand (or double-click the image)")
        }
    }

    @ViewBuilder
    private var analysisPane: some View {
        ScrollView {
            Group {
                if let result = model.uiCheckResult {
                    Text(result)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                } else if model.uiWatchActive {
                    Text("Capturing — click Stop in the toolbar when you're done navigating.")
                        .foregroundStyle(.secondary)
                } else if model.isReviewingUIScreenshots {
                    Text("Nothing is sent to Claude until you approve screens above and click \"Send for Review.\"")
                        .foregroundStyle(.secondary)
                } else if model.isBusy {
                    Text("Analyzing the approved screens...")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No analysis available.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .frame(minWidth: 300)
    }
}
