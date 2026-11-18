import CoreGraphics
import FoundationModels
import os
import PastoFoundation
import Synchronization

/// The system's on-device language model, through FoundationModels.
///
/// Each request gets a session of its own with greedy sampling, a short answer and a deadline
/// that includes the wait for its turn. Nothing leaves the Mac.
public final class SystemLanguageModelClient: LanguageModelClient {
    private let turn = GenerationTurn()
    /// Kept only so that the model stays loaded; requests use sessions of their own.
    private let prewarmedSession = Mutex<LanguageModelSession?>(nil)
    private let log = Log.logger(.picks)

    public init() {}

    public var availability: LanguageModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable(.appleIntelligenceNotEnabled): .appleIntelligenceNotEnabled
        // Not ready yet, and any reason a later system may add.
        case .unavailable: .modelNotReady
        }
    }

    public var acceptsImages: Bool {
        SystemLanguageModel.default.capabilities.contains(.vision)
    }

    public func prewarm() {
        guard availability == .available else { return }
        prewarmedSession.withLock { prewarmedSession in
            guard prewarmedSession == nil else { return }
            let session = LanguageModelSession(model: .default)
            session.prewarm()
            prewarmedSession = session
        }
    }

    public func classify(_ text: String) async throws -> ItemClass {
        let prompt = String(text.prefix(PicksMetrics.modelPromptLimit))
        let answer = try await generate(
            ItemCategoryAnswer.self,
            instructions: LanguageModelInstructions.classification,
            timeout: PicksMetrics.classificationTimeout
        ) { session, options in
            try await session.respond(
                to: prompt, generating: ItemCategoryAnswer.self, includeSchemaInPrompt: true, options: options
            ).content
        }
        return answer.category.itemClass
    }

    public func fieldKind(in screenshot: CGImage) async throws -> FieldKind? {
        guard acceptsImages else { throw LanguageModelClientError.unavailable }
        let answer = try await generate(
            FieldKindAnswer.self,
            instructions: LanguageModelInstructions.fieldKind,
            timeout: PicksMetrics.fieldKindTimeout
        ) { session, options in
            try await session.respond(generating: FieldKindAnswer.self, includeSchemaInPrompt: true, options: options) {
                LanguageModelInstructions.fieldKindQuestion
                Attachment(screenshot).label(LanguageModelInstructions.screenshotLabel)
            }.content
        }
        return answer.kind.fieldKind
    }

    /// Runs `request` on a fresh session once it is its turn, within `timeout`.
    private func generate<Answer: Sendable>(
        _ answer: Answer.Type,
        instructions: String,
        timeout: Duration,
        request: @escaping @Sendable (LanguageModelSession, GenerationOptions) async throws -> Answer
    ) async throws -> Answer {
        guard availability == .available else { throw LanguageModelClientError.unavailable }
        let start = ContinuousClock.now
        do {
            let result = try await withDeadline(timeout, expiry: LanguageModelClientError.timedOut) { [turn] in
                try await turn.take()
                do {
                    try Task.checkCancellation()
                    let session = LanguageModelSession(model: .default, instructions: instructions)
                    let options = GenerationOptions(
                        samplingMode: .greedy,
                        maximumResponseTokens: PicksMetrics.maximumResponseTokens
                    )
                    let result = try await request(session, options)
                    await turn.release()
                    return result
                } catch {
                    await turn.release()
                    throw error
                }
            }
            log.debug("Language model answered \(String(describing: Answer.self), privacy: .public) in \(start.duration(to: .now), privacy: .public)")
            return result
        } catch {
            log.debug("Language model gave no \(String(describing: Answer.self), privacy: .public) after \(start.duration(to: .now), privacy: .public): \(error)")
            throw error
        }
    }
}

// MARK: - Answers

/// The categories only the language model can tell, and `other`.
@Generable
struct ItemCategoryAnswer {
    @Guide(description: "The single category that best describes the copied text.")
    var category: Category

    @Generable
    enum Category {
        case personName
        case organizationName
        case code
        case command
        case filePath
        case message
        case prompt
        case quote
        case secret
        case other
    }
}

extension ItemCategoryAnswer.Category {
    var itemClass: ItemClass {
        switch self {
        case .personName: .personName
        case .organizationName: .organizationName
        case .code: .code
        case .command: .command
        case .filePath: .filePath
        case .message: .message
        case .prompt: .prompt
        case .quote: .quote
        case .secret: .secret
        case .other: .unclassified
        }
    }
}

/// A field kind, or `unknown`.
@Generable
struct FieldKindAnswer {
    @Guide(description: "The kind of input field the paste will most likely go into.")
    var kind: Kind

    @Generable
    enum Kind {
        case url
        case search
        case password
        case chat
        case code
        case terminal
        case cell
        case canvas
        case text
        case unknown
    }
}

extension FieldKindAnswer.Kind {
    var fieldKind: FieldKind? {
        switch self {
        case .url: .url
        case .search: .search
        case .password: .password
        case .chat: .chat
        case .code: .code
        case .terminal: .terminal
        case .cell: .cell
        case .canvas: .canvas
        case .text: .text
        case .unknown: nil
        }
    }
}
