import AppKit
import Observation
import PastoCore
import PastoFoundation
import UniformTypeIdentifiers

/// The state behind the Privacy pane.
@Observable
final class PrivacyModel {
    let isScreenSharingContentVisible: Setting<Bool>
    let isLinkPreviewsEnabled: Setting<Bool>
    /// The ignored applications that are installed, by name. Looked up again only when the
    /// setting changes.
    private(set) var applications: [IgnoredApplication] = []
    var selectedApplications: Set<IgnoredApplication.ID> = []

    private let ignoredPasteboardTypes: Setting<[String]>
    private let ignoredBundleIdentifiers: Setting<[String]>
    @ObservationIgnored private var observation: Task<Void, Never>?

    init(config: ConfigStore) {
        isScreenSharingContentVisible = Setting(.isScreenSharingContentVisible, in: config)
        isLinkPreviewsEnabled = Setting(.isLinkPreviewsEnabled, in: config)
        ignoredPasteboardTypes = Setting(.ignoredPasteboardTypes, in: config)
        ignoredBundleIdentifiers = Setting(.ignoredBundleIdentifiers, in: config)
        listApplications(ignoredBundleIdentifiers.value)
        observation = Task { [weak self] in
            for await identifiers in config.values(for: .ignoredBundleIdentifiers) {
                self?.listApplications(identifiers)
            }
        }
    }

    isolated deinit {
        observation?.cancel()
    }

    // MARK: - Ignored content

    func isIgnored(_ type: IgnoredContentType) -> Bool {
        ignoredPasteboardTypes.value.contains(type.rawValue)
    }

    func setIgnored(_ isIgnored: Bool, _ type: IgnoredContentType) {
        ignoredPasteboardTypes.value = IgnoredIdentifiers.setting(
            type.rawValue, included: isIgnored, in: ignoredPasteboardTypes.value
        )
    }

    // MARK: - Ignored applications

    /// Lets the user pick applications, in a sheet on the key window, and adds them to the list.
    func chooseApplications() {
        guard let window = NSApp.keyWindow else { return }
        let panel = NSOpenPanel()
        panel.prompt = SettingsStrings.choose
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(filePath: "/Applications", directoryHint: .isDirectory)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            let identifiers = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
            ignoredBundleIdentifiers.value = IgnoredIdentifiers.adding(identifiers, to: ignoredBundleIdentifiers.value)
        }
    }

    func removeSelectedApplications() {
        ignoredBundleIdentifiers.value = IgnoredIdentifiers.removing(selectedApplications, from: ignoredBundleIdentifiers.value)
        selectedApplications = []
    }

    /// Lists the applications by name, in the order the Finder sorts them.
    private func listApplications(_ identifiers: [String]) {
        applications = identifiers.compactMap(IgnoredApplication.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // An application taken off the list elsewhere is no longer selected.
        selectedApplications.formIntersection(applications.map(\.id))
    }
}
