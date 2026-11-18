import Foundation

/// The third-party notices Pasto ships, read from `Resources/Acknowledgements.md`. The file is
/// a small, fixed Markdown subset: each `## Name` heading opens an entry, the text after it is
/// the entry's details (version, site, license name) and a fenced block holds the license text,
/// kept verbatim. Anything before the first heading is a note for whoever edits the file.
nonisolated struct Acknowledgements: Equatable {
    struct Entry: Equatable, Identifiable {
        let name: String
        let details: String
        let license: String

        var id: String { name }
    }

    let entries: [Entry]

    /// The notices bundled with the module; none if the resource is missing.
    static func bundled() -> Acknowledgements {
        guard let url = Bundle.module.url(forResource: "Acknowledgements", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return Acknowledgements(entries: []) }
        return parse(text)
    }

    static func parse(_ text: String) -> Acknowledgements {
        var entries: [Entry] = []
        var name: String?
        var details: [String] = []
        var license: [String] = []
        var isInFence = false

        func closeEntry() {
            guard let name else { return }
            entries.append(Entry(
                name: name,
                details: details.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                license: license.joined(separator: "\n")
            ))
        }

        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("```") {
                isInFence.toggle()
                continue
            }
            if isInFence {
                if name != nil { license.append(line) }
                continue
            }
            if line.hasPrefix("## ") {
                closeEntry()
                name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                details = []
                license = []
            } else if name != nil {
                details.append(line)
            }
        }
        closeEntry()
        return Acknowledgements(entries: entries)
    }
}
