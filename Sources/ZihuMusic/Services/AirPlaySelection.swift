import Foundation

/// User intent and acknowledged routes are independent. A snapshot that started
/// before the latest click must never undo that click.
struct AirPlaySelection {
    private(set) var observed: Set<String> = []
    private(set) var requested: Set<String>?
    private(set) var revision: UInt64 = 0
    private var deadline: Date?

    var selected: Set<String> { requested ?? observed }
    var pending: Set<String> { selected.symmetricDifference(observed) }

    mutating func request(_ ids: Set<String>, now: Date = Date()) {
        revision &+= 1
        requested = ids
        deadline = now.addingTimeInterval(12)
    }

    /// Returns false for an obsolete read. The caller should fetch a new one.
    @discardableResult
    mutating func receive(_ ids: Set<String>, revision: UInt64) -> Bool {
        guard revision == self.revision else { return false }
        observed = ids
        if requested == ids {
            requested = nil
            deadline = nil
        }
        return true
    }

    /// Runs on the UI timer, including when a route IPC has stopped responding.
    mutating func expire(now: Date = Date()) -> Bool {
        guard let deadline, now >= deadline else { return false }
        revision &+= 1
        requested = nil
        self.deadline = nil
        return true
    }
}
