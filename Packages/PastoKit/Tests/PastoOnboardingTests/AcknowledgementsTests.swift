@testable import PastoOnboarding
import Testing

struct AcknowledgementsTests {
    @Test func entriesAreReadInOrder() {
        let text = """
            # Acknowledgements

            A note for whoever edits the file.

            ## First

            Version 1 · MIT License

            ```
            Copyright (c) 2026 Someone.

            THE SOFTWARE IS PROVIDED "AS IS".
            ```

            ## Second
            Details
            ```
            ## Not a heading inside the license
            ```
            """

        let acknowledgements = Acknowledgements.parse(text)

        #expect(acknowledgements.entries == [
            .init(
                name: "First",
                details: "Version 1 · MIT License",
                license: "Copyright (c) 2026 Someone.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\"."
            ),
            .init(name: "Second", details: "Details", license: "## Not a heading inside the license"),
        ])
    }

    @Test func textBeforeTheFirstHeadingIsIgnored() {
        #expect(Acknowledgements.parse("# Title\n\nJust a note.").entries.isEmpty)
    }

    @Test func theBundledNoticesIncludeSparkle() throws {
        let sparkle = try #require(Acknowledgements.bundled().entries.first { $0.name == "Sparkle" })
        #expect(sparkle.details.contains("MIT License"))
        #expect(sparkle.license.hasPrefix("Copyright (c) 2006-2013 Andy Matuschak."))
        #expect(sparkle.license.contains("Permission is hereby granted, free of charge"))
        #expect(sparkle.license.contains("EXTERNAL LICENSES"))
    }
}
