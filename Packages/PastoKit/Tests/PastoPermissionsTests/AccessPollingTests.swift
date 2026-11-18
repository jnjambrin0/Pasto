@testable import PastoPermissions
import Testing

@MainActor
struct AccessPollingTests {
    @Test func emitsTheFirstAnswerAndThenOnlyTheChanges() async {
        var answers = [false, false, true, true, true, false]
        let states = AccessPolling.states(every: .milliseconds(1)) {
            // Once the script runs out, the last answer holds and nothing more is emitted.
            answers.count > 1 ? answers.removeFirst() : answers[0]
        }

        var emitted: [Bool] = []
        for await state in states.prefix(3) {
            emitted.append(state)
        }

        #expect(emitted == [false, true, false])
    }
}
