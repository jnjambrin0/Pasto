/// Which tab takes the selection when the selected one goes away.
nonisolated enum TabSuccession {
    /// The tab that takes the place of `removed`: the first one after it that is still there
    /// or, when none after it is left, the last one before it. Nil when no other tab is left.
    ///
    /// - Parameters:
    ///   - previousOrder: The tabs as they were, `removed` among them.
    ///   - remaining: The tabs there are now.
    static func successor<ID: Hashable>(of removed: ID, in previousOrder: [ID], remaining: Set<ID>) -> ID? {
        guard let index = previousOrder.firstIndex(of: removed) else { return nil }
        return previousOrder[(index + 1)...].first(where: remaining.contains)
            ?? previousOrder[..<index].last(where: remaining.contains)
    }
}
