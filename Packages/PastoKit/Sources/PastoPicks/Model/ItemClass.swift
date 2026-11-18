/// What a clipboard item holds, in the terms suggestions match against a field. The raw values
/// are what the class store and the pick log keep.
public enum ItemClass: String, Sendable, Codable, CaseIterable {
    case unclassified
    case link
    case email
    case phone
    case date
    case address
    case money
    case trackingNumber
    case personName
    case organizationName
    case code
    case command
    case filePath
    case message
    case prompt
    case quote
    /// A password, key or token: never suggested.
    case secret
}
