import Foundation
import Testing
@testable import Shellhand

@Suite("Whose turn it is")
nonisolated struct TransferQueueTests {
    private func transfer(_ id: String, _ state: String) -> Transfer {
        Transfer(id: id, name: id, state: state)
    }

    private var six: [Transfer] {
        (1...6).map { transfer("\($0)", TransferQueue.queued) }
    }

    @Test("an empty queue starts nothing, and does not fall over asking")
    func nothing() {
        #expect(TransferQueue.toStart([], width: 2).isEmpty)
    }

    @Test("six asked for at once start two, not six")
    func fillsTheWidth() {
        #expect(TransferQueue.toStart(six, width: 2) == ["1", "2"])
    }

    @Test("the longest-waiting go first — the order asked for is the fairness")
    func inOrder() {
        #expect(TransferQueue.toStart(six, width: 3) == ["1", "2", "3"])
    }

    @Test("a queue already full starts nothing more")
    func full() {
        var jobs = six
        jobs[0].state = TransferQueue.running
        jobs[1].state = TransferQueue.running
        #expect(TransferQueue.toStart(jobs, width: 2).isEmpty)
    }

    @Test("one finishing makes room for exactly one more")
    func roomForOne() {
        var jobs = six
        jobs[0].state = TransferQueue.done
        jobs[1].state = TransferQueue.running
        #expect(TransferQueue.toStart(jobs, width: 2) == ["3"])
    }

    @Test("finished ones hold no place, however many of them there are")
    func finishedHoldNothing() {
        var jobs = six
        jobs[0].state = TransferQueue.done
        jobs[1].state = TransferQueue.failed
        jobs[2].state = TransferQueue.cancelled
        #expect(TransferQueue.toStart(jobs, width: 2) == ["4", "5"])
    }

    @Test("fewer waiting than there is room for starts all of them")
    func fewerThanWidth() {
        let two = [transfer("1", TransferQueue.queued), transfer("2", TransferQueue.queued)]
        #expect(TransferQueue.toStart(two, width: 8) == ["1", "2"])
    }

    @Test("a width of nought would stop everything for ever, so it is not one")
    func noZeroWidth() {
        #expect(TransferQueue.clamped(0) == 1)
        #expect(TransferQueue.clamped(-3) == 1)
        #expect(!TransferQueue.toStart(six, width: 0).isEmpty)
    }

    @Test("an absurd width is brought back to something sensible")
    func clamped() {
        #expect(TransferQueue.clamped(500) == TransferQueue.widths.upperBound)
        #expect(TransferQueue.clamped(2) == 2)
    }

    @Test("more running than the width allows — after it was lowered — starts none")
    func widthLowered() {
        var jobs = six
        for index in 0..<4 { jobs[index].state = TransferQueue.running }
        // The four already moving are left to finish; nothing new joins them.
        #expect(TransferQueue.toStart(jobs, width: 2).isEmpty)
    }
}

@Suite("What the strip says")
nonisolated struct TransferSummaryTests {
    private func transfer(_ state: String) -> Transfer {
        Transfer(id: UUID().uuidString, name: "f", state: state)
    }

    @Test("nothing asked for yet says nothing at all")
    func silent() {
        #expect(TransferQueue.summary([]) == "")
    }

    @Test("it counts what is moving and what is waiting")
    func movingAndWaiting() {
        let jobs = [
            transfer(TransferQueue.running), transfer(TransferQueue.running),
            transfer(TransferQueue.queued), transfer(TransferQueue.queued),
            transfer(TransferQueue.queued),
        ]
        #expect(TransferQueue.summary(jobs) == "2 moving, 3 waiting")
    }

    @Test("something broken is said even while the rest carry on")
    func failedIsSaid() {
        let jobs = [
            transfer(TransferQueue.running), transfer(TransferQueue.failed),
        ]
        #expect(TransferQueue.summary(jobs) == "1 moving, 1 failed")
    }

    @Test("when it is all over it says how much arrived")
    func allDone() {
        #expect(TransferQueue.summary([transfer(TransferQueue.done)]) == "1 done")
        #expect(TransferQueue.summary(
            [transfer(TransferQueue.done), transfer(TransferQueue.done)]) == "2 done")
    }

    @Test("everything called off is not a list of successes")
    func allCancelled() {
        #expect(TransferQueue.summary([transfer(TransferQueue.cancelled)]) == "Nothing to carry")
    }

    @Test("busy means something is still to happen")
    func busy() {
        #expect(TransferQueue.busy([transfer(TransferQueue.queued)]))
        #expect(TransferQueue.busy([transfer(TransferQueue.running)]))
        #expect(!TransferQueue.busy([transfer(TransferQueue.done)]))
        #expect(!TransferQueue.busy([transfer(TransferQueue.failed)]))
        #expect(!TransferQueue.busy([]))
    }

    /// What closing the SFTP window, or quitting, would stop: a transfer on
    /// the wire or waiting its turn, and nothing that has already ended.
    @Test("still to go counts what is moving or waiting, and nothing finished")
    func stillToGo() {
        #expect(TransferQueue.stillToGo([
            transfer(TransferQueue.running), transfer(TransferQueue.queued),
            transfer(TransferQueue.queued), transfer(TransferQueue.done),
            transfer(TransferQueue.failed), transfer(TransferQueue.cancelled),
        ]) == 3)
        #expect(TransferQueue.stillToGo([]) == 0)
    }
}

@Suite("A transfer's own idea of where it is")
nonisolated struct TransferStateTests {
    @Test("waiting its turn is not finished")
    func queuedIsNotFinished() {
        // Reading "not running" as finished is what made a queue impossible
        // to add: a transfer that had not started looked like one that had
        // already ended.
        let job = Transfer(id: "1", state: TransferQueue.queued)
        #expect(!job.finished)
        #expect(job.waiting)
        #expect(!job.moving)
    }

    @Test("every way of ending counts as finished")
    func endings() {
        for state in [TransferQueue.done, TransferQueue.failed, TransferQueue.cancelled] {
            #expect(Transfer(id: "1", state: state).finished, "\(state)")
        }
    }

    @Test("a new transfer starts out waiting, not running")
    func startsQueued() {
        #expect(Transfer().state == TransferQueue.queued)
        #expect(!Transfer().finished)
    }

    @Test("progress is a fraction of what there is, and never over one")
    func fraction() {
        #expect(Transfer(id: "1", done: 50, total: 100).fraction == 0.5)
        #expect(Transfer(id: "1", done: 0, total: 0).fraction == 0)
        // A total that arrives late, after some of it has already moved.
        #expect(Transfer(id: "1", done: 120, total: 100).fraction == 1)
    }
}
