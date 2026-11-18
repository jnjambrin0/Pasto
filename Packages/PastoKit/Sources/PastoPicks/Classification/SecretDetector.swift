import Foundation

/// Whether a text looks like a password, key or token, which suggestions never offer.
///
/// The first test that holds decides: a PEM block; an authorization header or a credential
/// assignment near the start; a word shaped like a well-known kind of API key or like a JSON Web
/// Token; or a long, dense, high-entropy word that is not something benign such as a path, an
/// address, a UUID or a hexadecimal hash.
enum SecretDetector {
    static func looksSecret(_ text: String) -> Bool {
        if text.contains(pemHeader) { return true }
        let start = String(text.prefix(PicksMetrics.secretScanLimit))
        if Pattern.authorizationHeader.matches(start) || Pattern.credentialAssignment.matches(start) {
            return true
        }
        return words(of: start).contains(where: isSecretWord)
    }

    // MARK: - Words

    private static let pemHeader = "-----BEGIN "
    /// A word with fewer characters is never taken for a known kind of key or a token.
    static let shapedWordMinimumLength = 15
    /// A word with fewer characters is never taken for a random secret.
    static let denseWordMinimumLength = 32
    /// Bits of Shannon entropy per character from which a dense word reads as random.
    static let minimumEntropy = 4.0

    private static let wordDelimiters = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "=\"':,;()[]{}<>"))

    static func words(of text: String) -> [Substring] {
        text.split { $0.unicodeScalars.allSatisfy(wordDelimiters.contains) }
    }

    static func isSecretWord(_ word: Substring) -> Bool {
        guard word.count >= shapedWordMinimumLength else { return false }
        let word = String(word)
        if Pattern.knownKey.matches(word) || Pattern.webToken.matches(word) { return true }
        guard word.count >= denseWordMinimumLength, Pattern.base64.matches(word), !isBenign(word) else {
            return false
        }
        let classes = CharacterClasses(word)
        return classes.count > 2 && classes.otherCount < 3 && entropy(of: word) >= minimumEntropy
    }

    /// Long words that are not secrets however random they look.
    static func isBenign(_ word: String) -> Bool {
        word.contains("://") || word.contains("@") || word.hasPrefix("/") || word.hasPrefix("~/")
            || UUID(uuidString: word) != nil || Pattern.hexadecimal.matches(word)
    }

    /// Shannon entropy in bits per character.
    static func entropy(of word: String) -> Double {
        let frequencies = Dictionary(word.map { ($0, 1) }, uniquingKeysWith: +)
        let length = Double(word.count)
        return frequencies.values.reduce(0) { total, count in
            let probability = Double(count) / length
            return total - probability * log2(probability)
        }
    }

    /// Which of lowercase letters, uppercase letters, digits and other characters a word mixes.
    struct CharacterClasses {
        private(set) var count = 0
        /// How many characters are neither letters nor digits.
        private(set) var otherCount = 0

        init(_ word: String) {
            var lowercase = false, uppercase = false, digit = false
            for character in word {
                if character.isLowercase {
                    lowercase = true
                } else if character.isUppercase {
                    uppercase = true
                } else if character.isNumber {
                    digit = true
                } else {
                    otherCount += 1
                }
            }
            count = [lowercase, uppercase, digit, otherCount > 0].count(where: \.self)
        }
    }

    // MARK: - Patterns

    private enum Pattern {
        /// `Bearer`, one space and a credential of 20 characters or more, or `Basic`, one space
        /// and one of 8 or more, as written: the scheme's capitals count.
        static let authorizationHeader = TextPattern(
            #"\b(?:Bearer [A-Za-z0-9._~+/=-]{20,}|Basic [A-Za-z0-9+/=]{8,})"#,
            scope: .anywhere
        )
        /// `name = value` or `name: value` whose name ends in a word for a password, a secret, a
        /// token or a key, right before the sign (`pass`, `password`, `DB_PASSWORD`, `pwd`,
        /// `access_token`, `api-key`, `private_key`, `clientSecret`…), in any case. The word
        /// starts the text or follows something other than a letter, so `mypassword=` is not one
        /// and neither is a quoted JSON key.
        static let credentialAssignment = TextPattern(
            #"(?:^|[^a-z])(?:pass(?:word|wd|code)?|pwd|secret|token|api[_-]?key|private[_-]?key|client[_-]?secret)\s*[:=]\s*\S"#,
            scope: .anywhere,
            options: .caseInsensitive
        )
        /// The published shapes of four widespread kinds of key, as a whole word: OpenAI-style
        /// `sk-` keys, GitHub personal and OAuth tokens, Slack tokens and AWS access key IDs.
        static let knownKey = TextPattern(
            #"sk-[A-Za-z0-9_-]{16,}|gh[po]_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}"#,
            scope: .wholeText
        )
        /// A JSON Web Token: three base64url segments separated by dots, the first one a JSON
        /// object, none of them short.
        static let webToken = TextPattern(
            #"eyJ[A-Za-z0-9_-]{7,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#,
            scope: .wholeText
        )
        /// Letters, digits and the symbols of base64 and base64url. `=` never reaches here: it
        /// splits words.
        static let base64 = TextPattern(#"[A-Za-z0-9+/_-]+"#, scope: .wholeText)
        static let hexadecimal = TextPattern(#"[0-9A-Fa-f]+"#, scope: .wholeText)
    }
}
