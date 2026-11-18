/// The kind of field the user is about to paste into.
///
/// It comes from looking at the destination window or, failing that, from what the destination
/// application is known to be. The raw values are what the pick log stores.
public enum FieldKind: String, Sendable, Codable, CaseIterable {
    case url
    case search
    case password
    case chat
    case code
    case terminal
    case cell
    case canvas
    case text

    /// The classes of item that suit the field and earn a candidate the field bonus.
    /// A password field gets no suggestions at all, so none suit it.
    var suitedClasses: Set<ItemClass> {
        switch self {
        case .url: [.link]
        case .search: [.link, .trackingNumber, .address, .personName, .organizationName]
        case .chat: [.message, .link, .quote]
        case .code: [.code, .filePath, .command]
        case .terminal: [.command, .filePath, .code]
        case .cell: [.money, .date, .phone, .email, .trackingNumber, .address]
        case .canvas, .text, .password: []
        }
    }
}
