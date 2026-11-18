import Foundation
import PastoCore

/// The class of an item by fixed rules, without the language model.
///
/// The rules recognise secrets, links, what the system's data detector finds, amounts, tracking
/// numbers, paths and terminal commands. Names, organisations, code, messages, prompts and
/// quotes are the language model's to recognise.
enum ItemClassRules {
    /// The class of an item of `type` whose text is `text`. Only text and links have a text to
    /// look at; anything else is unclassified. A text or link without one is taken as empty: a
    /// link is still a link.
    static func itemClass(of text: String?, type: ItemType) -> ItemClass {
        guard type == .text || type == .link else { return .unclassified }
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !trimmed.isEmpty, SecretDetector.looksSecret(trimmed) { return .secret }
        if type == .link { return .link }
        if trimmed.count > PicksMetrics.ruleTextLimit { return .unclassified }
        if let detected = detectedClass(of: trimmed) { return detected }
        if Pattern.money.matches(trimmed) { return .money }
        if Pattern.trackingNumber.matches(trimmed) { return .trackingNumber }
        if Pattern.filePath.matches(trimmed) { return .filePath }
        if CommandDetector.isCommand(trimmed) { return .command }
        return .unclassified
    }

    /// What the data detector says when it finds exactly one thing and that thing is the
    /// whole text.
    private static func detectedClass(of text: String) -> ItemClass? {
        let whole = NSRange(text.startIndex..., in: text)
        let matches = DataDetection.detector.matches(in: text, range: whole)
        guard matches.count == 1, let match = matches.first, match.range == whole else { return nil }
        switch match.resultType {
        // The scheme is compared as written.
        case .link: return match.url?.scheme == "mailto" ? .email : .link
        case .phoneNumber: return .phone
        case .date: return .date
        case .address: return .address
        default: return nil
        }
    }

    /// Patterns for the rules the data detector does not cover.
    private enum Pattern {
        /// A currency symbol, perhaps a space, and an amount; or an amount, perhaps a space, and
        /// a currency symbol or a three-letter code in capitals. An amount starts with a digit
        /// and goes on with digits, separators and spaces, however they are grouped; no sign.
        static let money = TextPattern(#"\p{Sc}\s?\#(amount)|\#(amount)\s?(?:\p{Sc}|[A-Z]{3})"#, scope: .wholeText)
        /// "1Z" and sixteen capitals or digits, or only digits in one of the lengths parcel
        /// numbers come in.
        static let trackingNumber = TextPattern(#"1Z[0-9A-Z]{16}|\d{10}|\d{12}|\d{15}|\d{20,22}"#, scope: .wholeText)
        /// A path from the root or the home folder with something after the slash, or a drive
        /// path; never with spaces.
        static let filePath = TextPattern(#"~?/\S+|[A-Za-z]:\\\S*"#, scope: .wholeText)

        private static let amount = #"\d[\d.,\s]*"#
    }
}

/// The system's detector for dates, addresses, links and phone numbers. Building one is
/// expensive, and it holds no state between searches.
private enum DataDetection {
    static let detector: NSDataDetector = {
        let types: NSTextCheckingResult.CheckingType = [.date, .address, .link, .phoneNumber]
        // Only an invalid type mask makes this throw.
        return try! NSDataDetector(types: types.rawValue)
    }()
}
