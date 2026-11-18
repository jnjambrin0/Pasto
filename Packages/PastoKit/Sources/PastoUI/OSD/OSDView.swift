import AppKit
import SwiftUI

/// What an on-screen notice shows: a large symbol, a title and an optional subtitle.
struct OSDView: View {
    let symbol: String
    let title: String?
    /// A `Text` so that callers can interleave symbols with words.
    let subtitle: Text?
    let onClick: (() -> Void)?

    @State private var clickMonitor: Any?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .renderingMode(.template)
                .font(.system(size: 86))
            VStack(spacing: 4) {
                if let title {
                    Text(title).font(.title)
                }
                if let subtitle {
                    subtitle.font(.body)
                }
            }
        }
        .foregroundColor(.secondary)
        .onHover { isInside in
            if isInside { startMonitoringClicks() } else { stopMonitoringClicks() }
        }
        .onDisappear(perform: stopMonitoringClicks)
    }

    /// While the pointer is over the notice, a left click is consumed and runs the action a
    /// moment later. The notice itself stays up for its usual time.
    private func startMonitoringClicks() {
        guard clickMonitor == nil else { return }
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                onClick?()
            }
            return nil
        }
    }

    private func stopMonitoringClicks() {
        if let clickMonitor {
            NSEvent.removeMonitor(clickMonitor)
        }
        clickMonitor = nil
    }
}
