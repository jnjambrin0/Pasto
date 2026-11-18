import Foundation

/// Opens an application again once a process has exited, from a shell that outlives it.
///
/// The shell puts its work in the background and returns at once, so the work is left to
/// launchd when the app exits. It waits for the process to go, then gives System Settings
/// `systemRelaunchGrace` to reopen the app itself — it took 3.2 s on macOS 27.2 — and opens it
/// only if no copy of the executable is running by then; a second `open` would only send the
/// running copy a "reopen". Everything variable travels as an argument, never inside
/// the script, so no path can break the quoting. The first wait gives up after `maximumWait`: a
/// process identifier that never goes away has been reused.
enum RelaunchHelper {
    static let pollInterval = 0.2
    static let maximumWait = 30.0
    static let systemRelaunchGrace = 4.0

    /// `$1` process, `$2` application bundle, `$3` its executable, `$4` and `$5` how many polls
    /// each wait makes.
    static let script = """
        (i=0; while /bin/kill -0 "$1" 2>/dev/null && [ "$i" -lt "$4" ]; do /bin/sleep \(pollInterval); i=$((i+1)); done; \
        j=0; while [ "$j" -lt "$5" ]; do /bin/ps -ax -o comm= | /usr/bin/grep -F -x -q -- "$3" && exit 0; \
        /bin/sleep \(pollInterval); j=$((j+1)); done; \
        /usr/bin/open "$2") >/dev/null 2>&1 &
        """

    /// The arguments of `/bin/sh` that wait for `processIdentifier` to exit and then make sure
    /// `application` runs again.
    static func arguments(processIdentifier: pid_t, application: URL, executable: URL) -> [String] {
        [
            "-c", script, "pasto-relaunch",
            String(processIdentifier),
            application.path(percentEncoded: false),
            executable.path(percentEncoded: false),
            String(polls(maximumWait)),
            String(polls(systemRelaunchGrace)),
        ]
    }

    static func openAfterExit(of processIdentifier: pid_t, application: URL, executable: URL) throws {
        let shell = Process()
        shell.executableURL = URL(filePath: "/bin/sh")
        shell.arguments = arguments(processIdentifier: processIdentifier, application: application, executable: executable)
        try shell.run()
    }

    private static func polls(_ seconds: Double) -> Int {
        Int((seconds / pollInterval).rounded())
    }
}
