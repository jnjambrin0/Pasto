import AppKit
import ProbeCore

// ProbeTarget: a window full of text inputs that logs how focus, key events and pastes reach it.

let options: TargetOptions
let eventLog: EventLog
do {
    options = try TargetOptions(arguments: Array(CommandLine.arguments.dropFirst()))
    eventLog = try EventLog(url: options.logURL)
} catch let error as ProbeError {
    Console.error("ProbeTarget: \(error.message)")
    exit(error.exitCode)
} catch {
    Console.error("ProbeTarget: \(error.localizedDescription)")
    exit(ProbeError.runtime("").exitCode)
}

let application = NSApplication.shared
let delegate = AppDelegate(options: options, log: eventLog)
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
