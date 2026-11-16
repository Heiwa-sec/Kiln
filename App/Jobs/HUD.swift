import AppKit
import SwiftUI
import KilnCore

struct HUDView: View {
    @ObservedObject var jobs: JobCenter
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if jobs.rows.count > 6 { Text("\(jobs.rows.count - 6) earlier items hidden").font(.system(size: 11)).foregroundStyle(Palette.textDim) }
            ForEach(jobs.rows.suffix(6)) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        trailing(row)
                    }
                    switch row.state {
                    case .running: ProgressView(value: row.progress).progressViewStyle(.linear).tint(Palette.accent)
                    case .done(let urls): Text("Saved \(urls.map(\.lastPathComponent).joined(separator: ", "))").font(.system(size: 11)).foregroundStyle(Palette.textDim).lineLimit(1)
                    case .failed(let m): Text(m).font(.system(size: 11)).foregroundStyle(Palette.warn).fixedSize(horizontal: false, vertical: true)
                    case .info: EmptyView()
                    }
                }
            }
        }
        .foregroundStyle(Palette.text)
        .padding(12).frame(width: 340, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func trailing(_ row: JobCenter.Row) -> some View {
        switch row.state {
        case .running: Button("Cancel") { row.handle?.cancel() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent)
        case .done(let urls): Button("Show") { NSWorkspace.shared.activateFileViewerSelecting(urls) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent)
        case .failed: Button("Dismiss") { jobs.dismiss(row.id) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.accent)
        case .info: EmptyView()
        }
    }
}

@MainActor final class HUDController {
    private let jobs: JobCenter
    private let panel: NSPanel
    private let host: NSHostingView<HUDView>
    private var hideWork: DispatchWorkItem?

    init(jobs: JobCenter) {
        self.jobs = jobs
        host = NSHostingView(rootView: HUDView(jobs: jobs))
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 60), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = host
        jobs.onChange = { [weak self] in self?.refresh() }
    }

    private var anchor: NSPoint?
    func place(near p: NSPoint) { anchor = p; refresh() }

    private func refresh() {
        hideWork?.cancel()
        guard !jobs.rows.isEmpty else { panel.orderOut(nil); return }
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        guard let main = NSScreen.main else { return }
        let p = anchor ?? NSPoint(x: main.frame.midX, y: main.frame.midY)
        let o = NSScreen.keepOnScreen(NSPoint(x: p.x - size.width / 2, y: p.y - size.height - 24), size: size, near: p, margin: 8)
        panel.setFrame(NSRect(origin: o, size: size), display: true)
        panel.orderFrontRegardless()
        if !jobs.isBusy && !jobs.hasFailures {
            let w = DispatchWorkItem { [weak self] in self?.jobs.dismissFinished() }
            hideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: w)
        }
    }
}
