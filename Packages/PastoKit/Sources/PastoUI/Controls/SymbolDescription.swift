import AppKit

/// An SF Symbol at a given point size and weight. Glyph sizes are tuned per symbol to match
/// measurements, so they live in metrics files as values of this type.
public nonisolated struct SymbolDescription: Sendable, Equatable {
    public let name: String
    public let pointSize: CGFloat
    public let weight: NSFont.Weight

    public init(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .regular) {
        self.name = name
        self.pointSize = pointSize
        self.weight = weight
    }

    /// The symbol as a template image, or nil if the system has no symbol with that name.
    public func makeImage() -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
    }
}
