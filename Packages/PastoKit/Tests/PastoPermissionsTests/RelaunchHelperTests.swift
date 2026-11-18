import Foundation
@testable import PastoPermissions
import Testing

/// The shell that opens Pasto again.
struct RelaunchHelperTests {
    @Test func everythingVariableTravelsAsAnArgument() {
        let application = URL(filePath: "/Applications/Pas'to \"$(x)\".app")
        let executable = application.appending(path: "Contents/MacOS/Pasto")

        let arguments = RelaunchHelper.arguments(processIdentifier: 4321, application: application, executable: executable)

        #expect(arguments[0] == "-c")
        #expect(arguments[1] == RelaunchHelper.script)
        #expect(Array(arguments[3...]) == [
            "4321",
            "/Applications/Pas'to \"$(x)\".app",
            "/Applications/Pas'to \"$(x)\".app/Contents/MacOS/Pasto",
            "150",
            "20",
        ])
        #expect(!RelaunchHelper.script.contains("Applications"))
    }

    @Test func theScriptRunsInTheBackgroundSoTheShellReturnsAtOnce() {
        #expect(RelaunchHelper.script.hasPrefix("("))
        #expect(RelaunchHelper.script.hasSuffix("&"))
    }
}
