@testable import PastoPicks
import Testing

struct SecretDetectorTests {
    @Test func aPEMBlock() {
        #expect(SecretDetector.looksSecret("-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXk=\n-----END OPENSSH PRIVATE KEY-----"))
    }

    @Test(arguments: [
        "Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123",
        "Authorization: Basic dXNlcjpwYXNz",
        "Bearer abcdefghij.klmnopqrst=",
    ])
    func authorizationHeaders(text: String) {
        #expect(SecretDetector.looksSecret(text))
    }

    @Test(arguments: [
        "Bearer of bad news",
        // The scheme is written with its capital, followed by a single space.
        "authorization: basic dXNlcjpwYXNz",
        "Bearer  abcdefghijklmnopqrstuvwxyz0123",
    ])
    func notAuthorizationHeaders(text: String) {
        #expect(!SecretDetector.looksSecret(text))
    }

    @Test(arguments: [
        "DB_PASSWORD=hunter2",
        "password: correct horse",
        "pass: x",
        "clientSecret = abc",
        "api-key: 1234",
        "GITHUB_TOKEN=abc",
        "access_token: x",
        "1pwd=x",
    ])
    func credentialAssignments(text: String) {
        #expect(SecretDetector.looksSecret(text))
    }

    @Test(arguments: [
        "passport: X1234567", "tokenizer = fast", "password", "The secret is out",
        // The word has to end the name, right before the sign.
        "mypassword=x", "password_hash=x", "passphrase=x",
        #"{"client_secret": "s3cr3t"}"#,
    ])
    func notCredentialAssignments(text: String) {
        #expect(!SecretDetector.looksSecret(text))
    }

    @Test(arguments: [
        "ghp_" + String(repeating: "a1B2", count: 9),
        "gho_" + String(repeating: "a1B2", count: 5),
        "AKIA" + "ABCDEFGHIJKLMNOP",
        "xoxb-1234567890-abcdefghij",
        "sk-abcdefghijklmnopqrstuv",
        "sk-proj-abcdefghijklmnop",
        "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0In0.c2lnbmF0dXJl",
    ])
    func wellKnownShapes(text: String) {
        #expect(SecretDetector.looksSecret(text))
    }

    @Test(arguments: [
        // Too short after the prefix.
        "sk-abcdefghijklmno",
        // Only personal and OAuth GitHub tokens.
        "ghs_" + String(repeating: "a1B2", count: 5),
        // A temporary AWS key ID is not one of the shapes.
        "ASIA" + "ABCDEFGHIJKLMNOP",
        // A token's segments are long.
        "eyJhbGciOi.eyJzdWIi.c2ln",
    ])
    func notWellKnownShapes(text: String) {
        #expect(!SecretDetector.isSecretWord(Substring(text)))
    }

    @Test func aRandomDenseWord() {
        #expect(SecretDetector.looksSecret("key Zx8Qm2Lp9Rt4Vb7Nc1Hd6Jf3Kw5Ys0Ug8Ta2Pe"))
    }

    @Test(arguments: [
        // A UUID.
        "6F9619FF-8B86-D011-B42D-00C04FC964FF-trailing",
        // A hexadecimal hash.
        "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        // A path.
        "/Users/someone/Library/Application/Support/abcdefghijklmnop",
        // Low entropy.
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaAAAAAAAA1111",
        // Prose.
        "Meet me at the station at noon, the usual platform",
    ])
    func benignWords(text: String) {
        #expect(!SecretDetector.looksSecret(text))
    }

    @Test func uuidsAndHexadecimalAreBenign() {
        #expect(SecretDetector.isBenign("6F9619FF-8B86-D011-B42D-00C04FC964FF"))
        #expect(SecretDetector.isBenign("deadBEEF0123"))
        #expect(SecretDetector.isBenign("~/notes"))
        #expect(!SecretDetector.isBenign("Zx8Qm2Lp9Rt4"))
    }

    @Test func entropy() {
        #expect(SecretDetector.entropy(of: "abcd") == 2)
        #expect(SecretDetector.entropy(of: "aaaa") == 0)
    }

    @Test func characterClasses() {
        let classes = SecretDetector.CharacterClasses("aB3-_")
        #expect(classes.count == 4)
        #expect(classes.otherCount == 2)
    }
}
