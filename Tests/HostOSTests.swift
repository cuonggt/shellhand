import Foundation
import Testing

@testable import Shellhand

private typealias AppHost = Shellhand.Host

/// When a host is asked what it is.
///
/// A schedule is the kind of thing that reads as obviously right and is
/// wrong in one case — so each case is here rather than the two that are
/// obvious. Pure, so none of it opens a connection to anything.
@Suite("asking a host what it is")
nonisolated struct HostOSTests {
    private func host(os: String = "", seen: Double = 0) -> AppHost {
        var h = AppHost(name: "web", addr: "10.0.0.1")
        h.id = "h-1"
        h.os = os
        h.osSeen = seen
        return h
    }

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var aDayAgo: Double { now.timeIntervalSince1970 - 24 * 60 * 60 }

    @Test("a host that has never been asked is asked")
    func neverAsked() {
        #expect(host().shouldAskOS(allowed: true, now: now))
    }

    @Test("a host asked just now is left alone")
    func askedJustNow() {
        #expect(!host(os: "ubuntu", seen: now.timeIntervalSince1970 - 60).shouldAskOS(allowed: true, now: now))
    }

    /// **The case the first version got wrong**, and the reason `osSeen`
    /// records the asking rather than the answering. A host that cannot say
    /// — one taking only a password, a BSD with no `/etc/os-release`, a
    /// container with no sftp subsystem — has an empty `os` for ever. Keyed
    /// on the answer, it would open a connection on **every single connect**,
    /// for ever, for an icon it is never going to get.
    @Test("a host that could not answer is not asked again until tomorrow")
    func answeredNothing() {
        let asked = host(os: "", seen: now.timeIntervalSince1970 - 60)
        #expect(!asked.shouldAskOS(allowed: true, now: now))
    }

    /// What makes a rebuilt machine correct itself, which asking once ever
    /// never did.
    @Test("a host asked a day ago is asked again")
    func aDayLater() {
        #expect(host(os: "ubuntu", seen: aDayAgo).shouldAskOS(allowed: true, now: now))
        #expect(host(os: "ubuntu", seen: aDayAgo + 1).shouldAskOS(allowed: true, now: now) == false)
    }

    /// A host not yet saved has no id to ask about, and `Core.osOf` takes
    /// one. Asking would be a connection opened for a record that may never
    /// be written.
    @Test("a host with no id is not asked")
    func noID() {
        var draft = host()
        draft.id = ""
        #expect(!draft.shouldAskOS(allowed: true, now: now))
    }

    /// A clock that has gone backwards — a laptop waking in another
    /// timezone, a stamp from a store copied off another machine — must not
    /// lock a host out of ever being asked again.
    @Test("a stamp in the future does not lock a host out for ever")
    func futureStamp() {
        let ahead = host(os: "ubuntu", seen: now.timeIntervalSince1970 + 60 * 60)
        #expect(!ahead.shouldAskOS(allowed: true, now: now))
        // ...but a day later it is due regardless of how it got there.
        #expect(ahead.shouldAskOS(allowed: true, now: now.addingTimeInterval(25 * 60 * 60)))
    }

    // MARK: the switch in Settings

    /// **The switch outranks the schedule.** Off, nothing is due — not even a
    /// host never asked, which the schedule alone asks first.
    @Test("with the switch off, no host is asked, not even one never asked")
    func switchedOff() {
        #expect(!host().shouldAskOS(allowed: false, now: now))
        #expect(!host(os: "ubuntu", seen: aDayAgo).shouldAskOS(allowed: false, now: now))
    }

    /// Nothing stored is how every copy behaved before there was a switch,
    /// so it means on, and only a stored false turns it off.
    @Test("the switch is on unless it was turned off")
    func onUnlessTurnedOff() {
        #expect(AppHost.asks(nil))
        #expect(AppHost.asks(true))
        #expect(!AppHost.asks(false))
    }

    // MARK: what the mark is called

    /// **The mark is decoration until something says what it is.** This is
    /// the one string the tooltip, the accessibility label and the inspector
    /// row all read, so they cannot drift apart — and a rule rather than
    /// three copies inside views, none of which could be checked.
    @Test("a host is called what it said, falling back to its id")
    func whatItIsCalled() {
        var h = host()
        #expect(h.osLabel == "", "nothing known says nothing")

        // An id and no words: better than nothing, and what an os-release
        // with an `ID` and no `PRETTY_NAME` gives.
        h.os = "rhel"
        #expect(h.osLabel == "rhel")

        // The machine's own words win, which is the whole reason the name is
        // stored rather than made up from the id.
        h.osName = "Red Hat Enterprise Linux 9.3"
        #expect(h.osLabel == "Red Hat Enterprise Linux 9.3")
    }
}
