/// Carries out the commands of the tabs' context menus. The toolbar only builds the menus and
/// reports what was chosen.
public protocol TabMenuActions: AnyObject {
    func perform(_ command: TabMenuCommand)
}
