/// What Pasto tells the language model. The texts are not translated, since they are read by the
/// model, not by the user.
enum LanguageModelInstructions {
    /// Sorting a copied text: one category, secret for credentials, other when in doubt.
    static let classification = """
        You sort text that a person copied to their clipboard into one category. \
        Reply with the single category that fits best. \
        Choose secret for passwords, API keys, access tokens, private keys and any other credential. \
        When no category clearly fits, choose other.
        """

    /// Telling the destination field from a screenshot: what the window shows, why there is no
    /// cursor, how to judge, and when to say unknown.
    static let fieldKind = """
        The image is a screenshot of the window a person is about to paste into. \
        The window was not in front when it was captured, so it shows no text cursor \
        and may show no focus ring. \
        Judging by what the application is for and how the window is laid out, \
        say which kind of input field the paste will most likely go into. \
        If the window has no input field, or you cannot tell, answer unknown.
        """

    static let fieldKindQuestion = "Which kind of field is this paste most likely going into?"

    /// How the screenshot is labelled in the prompt.
    static let screenshotLabel = "screen"
}
