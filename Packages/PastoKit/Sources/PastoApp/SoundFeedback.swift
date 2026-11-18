import AudioToolbox
import Foundation
import PastoCore
import PastoFoundation

/// The copy and paste sounds.
///
/// They are system sounds, so they follow the user's alert volume and "play user interface
/// sound effects" preference. The setting is read on every play, so it applies at once.
final class SoundFeedback {
    private let config: ConfigStore
    private var copySoundID: SystemSoundID = 0
    private var pasteSoundID: SystemSoundID = 0

    init(config: ConfigStore, bundle: Bundle = .main) {
        self.config = config
        if let url = bundle.url(forResource: "PastoCopy", withExtension: "aiff") {
            AudioServicesCreateSystemSoundID(url as CFURL, &copySoundID)
        }
        if let url = bundle.url(forResource: "PastoPaste", withExtension: "aiff") {
            AudioServicesCreateSystemSoundID(url as CFURL, &pasteSoundID)
        }
    }

    /// Something was captured. Re-copying what is already in the history stays silent while the
    /// Paste Stack is on screen, where every paste already triggers a capture.
    func playCopy(wasInHistory: Bool, isPasteStackVisible: Bool) {
        guard config.value(for: .isSoundEffectsEnabled), !(isPasteStackVisible && wasInHistory) else { return }
        AudioServicesPlaySystemSound(copySoundID)
    }

    /// Items were put back on the pasteboard: a paste, a copy from the panel or a stack paste.
    /// To be called from `ItemRestorer.onRestore`, so that it sounds in the turn of the
    /// pasteboard write, before the paste's keystroke.
    func playPaste() {
        guard config.value(for: .isSoundEffectsEnabled) else { return }
        AudioServicesPlaySystemSound(pasteSoundID)
    }
}
