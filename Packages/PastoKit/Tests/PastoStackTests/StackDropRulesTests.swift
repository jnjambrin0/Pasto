import AppKit
import Testing
@testable import PastoStack

@Suite struct StackDropRulesTests {
    @Test func aRowDragEndsByWhatTookIt() {
        #expect(StackDragOutcome(operation: [], didDropInPanel: false) == .cancelled)
        #expect(StackDragOutcome(operation: [], didDropInPanel: true) == .cancelled)
        #expect(StackDragOutcome(operation: .move, didDropInPanel: true) == .droppedInPanel)
        #expect(StackDragOutcome(operation: .copy, didDropInPanel: false) == .droppedOutside)
        #expect(StackDragOutcome(operation: .move, didDropInPanel: false) == .droppedOutside)
    }

    @Test func thePanelTakesCopiesFromAnyoneAndMovesOnlyOfPastoItems() {
        #expect(StackDropContent.operation(forSourceMask: [.copy, .move], carriesItems: false) == .copy)
        #expect(StackDropContent.operation(forSourceMask: .copy, carriesItems: true) == .copy)
        #expect(StackDropContent.operation(forSourceMask: .move, carriesItems: true) == .move)
        #expect(StackDropContent.operation(forSourceMask: .move, carriesItems: false) == [])
        #expect(StackDropContent.operation(forSourceMask: .link, carriesItems: true) == [])
    }
}
