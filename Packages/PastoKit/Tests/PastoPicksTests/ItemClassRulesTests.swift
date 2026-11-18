import PastoCore
@testable import PastoPicks
import Testing

struct ItemClassRulesTests {
    @Test(arguments: [ItemType.image, .color, .files, .unknown])
    func onlyTextAndLinksAreClassified(type: ItemType) {
        #expect(ItemClassRules.itemClass(of: "git status", type: type) == .unclassified)
    }

    @Test func noTextIsUnclassifiedButALinkStaysALink() {
        #expect(ItemClassRules.itemClass(of: nil, type: .text) == .unclassified)
        #expect(ItemClassRules.itemClass(of: "   \n", type: .text) == .unclassified)
        #expect(ItemClassRules.itemClass(of: nil, type: .link) == .link)
    }

    @Test func aLinkIsALink() {
        #expect(ItemClassRules.itemClass(of: "https://example.com/page", type: .link) == .link)
    }

    @Test func aSecretComesBeforeEverythingElse() {
        #expect(ItemClassRules.itemClass(of: "https://example.com/?token=abc123", type: .link) == .secret)
        #expect(ItemClassRules.itemClass(of: "  password: hunter2  ", type: .text) == .secret)
    }

    @Test func longTextsAreLeftToTheModel() {
        let text = String(repeating: "/usr/local ", count: 400)
        #expect(ItemClassRules.itemClass(of: text, type: .text) == .unclassified)
    }

    @Test func whatTheDataDetectorFindsInTheWholeText() {
        #expect(ItemClassRules.itemClass(of: "https://example.com", type: .text) == .link)
        #expect(ItemClassRules.itemClass(of: "someone@example.com", type: .text) == .email)
        #expect(ItemClassRules.itemClass(of: "+1 (408) 555-0123", type: .text) == .phone)
    }

    @Test func aDetectionThatCoversOnlyPartOfTheTextDoesNotCount() {
        #expect(ItemClassRules.itemClass(of: "Write to someone@example.com", type: .text) == .unclassified)
    }

    @Test(arguments: ["$12.50", "€ 3", "12,50 €", "1,234.56 USD", "99 GBP", "1 000 000 €", "£1.2.3"])
    func amounts(text: String) {
        #expect(ItemClassRules.itemClass(of: text, type: .text) == .money)
    }

    @Test(arguments: ["12.50", "USD", "$", "twelve dollars", "-$5", "USD 99", "99 usd"])
    func notAmounts(text: String) {
        #expect(ItemClassRules.itemClass(of: text, type: .text) != .money)
    }

    @Test func trackingNumbers() {
        #expect(ItemClassRules.itemClass(of: "1Z999AA10123456784", type: .text) == .trackingNumber)
        #expect(ItemClassRules.itemClass(of: String(repeating: "7", count: 21), type: .text) == .trackingNumber)
        #expect(ItemClassRules.itemClass(of: String(repeating: "7", count: 13), type: .text) != .trackingNumber)
    }

    @Test(arguments: ["/usr/local/bin", "~/Documents/notes.txt", #"C:\Users\Pasto"#, #"C:\"#])
    func paths(text: String) {
        #expect(ItemClassRules.itemClass(of: text, type: .text) == .filePath)
    }

    @Test(arguments: ["/usr/local and more", #"C:\Program Files\Pasto"#, "/", "~/"])
    func notPaths(text: String) {
        #expect(ItemClassRules.itemClass(of: text, type: .text) != .filePath)
    }

    @Test(arguments: ["git status", "ls -la", "./build.sh --release", "cat notes | wc -l", "make && make install"])
    func commands(text: String) {
        #expect(ItemClassRules.itemClass(of: text, type: .text) == .command)
    }

    @Test(arguments: [
        "git is great!", "Did you run ls?", "cd there. Then wait", "cd there.\tThen wait", "git status\ngit push",
        "makeup tips", "lsd", "ls", "ls | grep x?",
    ])
    func notCommands(text: String) {
        #expect(!CommandDetector.isCommand(text))
    }

    @Test func plainProseIsUnclassified() {
        #expect(ItemClassRules.itemClass(of: "See you tomorrow at the usual place", type: .text) == .unclassified)
    }

    @Test func theModelIsAskedOnlyAboutMidLengthTextsTheRulesLeft() {
        #expect(LanguageModelItemClassifier.isWorthAsking("Lunch with the design team"))
        #expect(!LanguageModelItemClassifier.isWorthAsking("Lunch"))
        #expect(!LanguageModelItemClassifier.isWorthAsking(String(repeating: "word ", count: 401)))
        #expect(!LanguageModelItemClassifier.isWorthAsking("git status --short"))
    }
}
