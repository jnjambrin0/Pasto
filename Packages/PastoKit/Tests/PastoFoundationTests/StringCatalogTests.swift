import Foundation
import Testing

/// Every string catalog of the app, the modules' `Localizable.xcstrings` and the app target's
/// `InfoPlist.xcstrings`, must carry each of its keys in English and in Spanish, finished, with
/// the same format arguments in both. A key left without Spanish would show English in the
/// middle of a Spanish interface, and nothing else would notice.
struct StringCatalogTests {
    private static let languages = ["en", "es"]

    private static var packageDirectory: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent() // PastoFoundationTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // PastoKit
    }

    static var catalogs: [URL] {
        let sources = packageDirectory.appending(path: "Sources")
        let modules = (try? FileManager.default.contentsOfDirectory(
            at: sources, includingPropertiesForKeys: nil
        )) ?? []
        let moduleCatalogs = modules.flatMap { module in
            let resources = module.appending(path: "Resources")
            let files = (try? FileManager.default.contentsOfDirectory(
                at: resources, includingPropertiesForKeys: nil
            )) ?? []
            return files.filter { $0.pathExtension == "xcstrings" }
        }
        let infoPlist = packageDirectory
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // repository
            .appending(path: "Pasto/InfoPlist.xcstrings")
        return (moduleCatalogs + [infoPlist]).sorted { $0.path < $1.path }
    }

    @Test func catalogsAreFound() {
        let names = Self.catalogs.map { $0.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent }
        #expect(names.contains("PastoApp"))
        #expect(names.contains("PastoOnboarding"))
        #expect(Self.catalogs.contains { $0.lastPathComponent == "InfoPlist.xcstrings" })
        #expect(Self.catalogs.count >= 9)
    }

    @Test(arguments: StringCatalogTests.catalogs)
    func everyKeyIsTranslated(_ catalog: URL) throws {
        let data = try Data(contentsOf: catalog)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["sourceLanguage"] as? String == "en", "\(catalog.path): source language")
        let strings = try #require(root["strings"] as? [String: Any], "\(catalog.path): no strings")
        #expect(!strings.isEmpty, "\(catalog.path) is empty")

        for (key, value) in strings {
            let entry = try #require(value as? [String: Any])
            let location = "\(catalog.lastPathComponent) of \(catalog.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent): “\(key)”"
            #expect(entry["extractionState"] as? String != "stale", "\(location) is stale: no code uses it")
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            var arguments: [String: [String: [String]]] = [:]
            for language in Self.languages {
                guard let localization = localizations[language] as? [String: Any] else {
                    Issue.record("\(location) has no \(language) text")
                    continue
                }
                let units = Self.units(of: localization)
                #expect(!units.isEmpty, "\(location): the \(language) text has no value")
                for (variant, unit) in units {
                    #expect(unit.state == "translated", "\(location): the \(language) text (\(variant)) is “\(unit.state)”")
                    #expect(!unit.value.trimmingCharacters(in: .whitespaces).isEmpty,
                            "\(location): the \(language) text (\(variant)) is empty")
                    arguments[language, default: [:]][variant] = Self.formatArguments(in: unit.value)
                }
            }
            if let english = arguments["en"], let spanish = arguments["es"] {
                for (variant, englishArguments) in english {
                    guard let spanishArguments = spanish[variant] else { continue }
                    // A plural's "one" may spell the number out; every other text keeps them all.
                    if variant.hasSuffix("one") {
                        #expect(Set(spanishArguments).isSubset(of: Set(englishArguments)),
                                "\(location) (\(variant)): format arguments differ")
                    } else {
                        #expect(spanishArguments.sorted() == englishArguments.sorted(),
                                "\(location) (\(variant)): format arguments differ")
                    }
                }
            }
        }
    }

    // MARK: Pure helpers

    @Test func formatArgumentsAreFound() {
        #expect(Self.formatArguments(in: "%1$@ (%2$@, %3$@ to navigate)") == ["%1$@", "%2$@", "%3$@"])
        #expect(Self.formatArguments(in: "Delete %lld items?") == ["%lld"])
        #expect(Self.formatArguments(in: "100%% sure") == [])
    }

    private struct Unit {
        let state: String
        let value: String
    }

    /// The string units of one language, keyed by variant ("" when there are no variations;
    /// "plural.one", "plural.other"… otherwise).
    private static func units(of localization: [String: Any], prefix: String = "") -> [String: Unit] {
        var units: [String: Unit] = [:]
        if let unit = localization["stringUnit"] as? [String: Any] {
            units[prefix] = Unit(state: unit["state"] as? String ?? "", value: unit["value"] as? String ?? "")
        }
        if let variations = localization["variations"] as? [String: Any] {
            for (kind, cases) in variations {
                guard let cases = cases as? [String: Any] else { continue }
                for (name, variant) in cases {
                    guard let variant = variant as? [String: Any] else { continue }
                    let path = prefix.isEmpty ? "\(kind).\(name)" : "\(prefix).\(kind).\(name)"
                    units.merge(Self.units(of: variant, prefix: path)) { first, _ in first }
                }
            }
        }
        return units
    }

    /// The printf-style arguments of a text, `%%` aside.
    private static func formatArguments(in text: String) -> [String] {
        let pattern = /%(?:\d+\$)?(?:@|lld|ld|d|u|llu|f|\.\d+f|s)/
        let withoutEscapes = text.replacingOccurrences(of: "%%", with: "")
        return withoutEscapes.matches(of: pattern).map { String($0.output) }
    }
}
