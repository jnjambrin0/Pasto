import CoreGraphics
import Testing
@testable import ProbeCore

@Suite struct ArgumentsTests {
    private let spec = CommandLineArguments.Spec(valueOptions: ["app", "hz", "rect"], flags: ["largest"])

    @Test func separatesOptionsFlagsAndPositionals() throws {
        let arguments = try CommandLineArguments(["a.png", "--app", "pasto", "--largest", "--hz=240", "-5,10"], spec: spec)
        #expect(arguments.positionals == ["a.png", "-5,10"])
        #expect(arguments.string("app") == "pasto")
        #expect(arguments.flag("largest"))
        #expect(try arguments.double("hz") == 240)
        #expect(try arguments.int("hz") == 240)
        #expect(arguments.string("rect") == nil)
    }

    @Test func rejectsUnknownOptionsMissingValuesAndBadNumbers() throws {
        #expect(throws: ProbeError.usage("unknown option --nope")) { try CommandLineArguments(["--nope"], spec: spec) }
        #expect(throws: ProbeError.usage("--app needs a value")) { try CommandLineArguments(["--app"], spec: spec) }
        let arguments = try CommandLineArguments(["--hz", "fast"], spec: spec)
        #expect(throws: ProbeError.self) { try arguments.double("hz") }
        #expect(throws: ProbeError.self) { try arguments.requiredString("app") }
        #expect(throws: ProbeError.self) { try arguments.positional(0, named: "file") }
    }

    @Test func parsesRectanglesAndPoints() throws {
        #expect(try Frame(parsing: "0,785,1728,332") == Frame(x: 0, y: 785, w: 1728, h: 332))
        #expect(try Geometry.point(parsing: "-12.5, 40") == CGPoint(x: -12.5, y: 40))
        for text in ["1,2,3", "1,2,0,4", "a,b,c,d", ""] {
            #expect(throws: ProbeError.self) { try Frame(parsing: text) }
        }
    }

    @Test func errorsMapToTheDocumentedExitCodes() {
        #expect(ProbeError.usage("").exitCode == 1)
        #expect(ProbeError.permission("").exitCode == 2)
        #expect(ProbeError.targetNotFound("").exitCode == 3)
        #expect(ProbeError.runtime("").exitCode == 4)
    }
}

@Suite struct SeedSetTests {
    @Test func itemIdentifiersAreUniqueAndBasicIsASubsetOfFull() {
        let full = SeedSet.full.items.map(\.id)
        #expect(Set(full).count == full.count)
        #expect(full.count == 14)
        #expect(Set(SeedSet.basic.items.map(\.id)).isSubset(of: Set(full)))
        #expect(SeedSet.basic.items.count == 7)
    }

    @Test func longTextIsExactlyThreeThousandCharacters() throws {
        let item = try #require(SeedSet.full.items.first { $0.id == "text-long" })
        guard case .text(let text) = item.payload else {
            Issue.record("text-long should be plain text")
            return
        }
        #expect(text.count == 3000)
    }
}
