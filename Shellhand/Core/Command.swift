import Foundation

/// Running a program and collecting what it said.
///
/// Output is read as it arrives rather than after the program ends: a pipe
/// holds about 64 KiB, and a command that filled it would block forever
/// waiting for someone to read, while the reader waited for it to exit.
nonisolated enum Command {
    nonisolated struct Outcome: Sendable {
        var output = ""
        /// True where the program said more than was kept.
        var truncated = false
        var exitCode: Int32 = 0
        var signal: Int32 = 0
        /// Set where the program could not be run or was stopped from here,
        /// which is not a verdict on what it was asked to do.
        var failure: String?
        var milliseconds = 0

        var wentWell: Bool { failure == nil && exitCode == 0 && signal == 0 }
    }

    /// Runs a program, keeping at most `limit` bytes of what it writes to
    /// either stream. Cancelling the task that called this ends the program.
    static func run(
        _ program: String, _ arguments: [String], environment: [String: String] = [:],
        limit: Int = 256 << 10
    ) async -> Outcome {
        let started = Date()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: program)
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, b in b }
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let collected = Collector(limit: limit)
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { return }
            collected.append(data)
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return Outcome(failure: error.localizedDescription,
                           milliseconds: Int(Date().timeIntervalSince(started) * 1000))
        }

        var stopped = false
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                process.terminationHandler = { _ in continuation.resume() }
            }
        } onCancel: {
            stopped = true
            process.terminate()
        }

        // Whatever was written between the last read and the exit.
        pipe.fileHandleForReading.readabilityHandler = nil
        if let rest = try? pipe.fileHandleForReading.readToEnd(), !rest.isEmpty {
            collected.append(rest)
        }
        try? pipe.fileHandleForReading.close()

        var outcome = Outcome(
            output: collected.text, truncated: collected.over,
            milliseconds: Int(Date().timeIntervalSince(started) * 1000))
        if process.terminationReason == .uncaughtSignal {
            outcome.signal = process.terminationStatus
        } else {
            outcome.exitCode = process.terminationStatus
        }
        if stopped || Task.isCancelled {
            // Stopped from here, so whatever status the child ended with is
            // not a verdict on what it was running.
            outcome.failure = "stopped"
        }
        return outcome
    }

    /// Keeps the first `limit` bytes and remembers that there were more. The
    /// handler runs on a queue of the pipe's choosing, so the lock is not
    /// optional.
    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private var overflowed = false
        private let limit: Int

        init(limit: Int) { self.limit = limit }

        func append(_ more: Data) {
            lock.lock()
            defer { lock.unlock() }
            let room = limit - data.count
            guard room > 0 else {
                overflowed = true
                return
            }
            if more.count > room {
                data.append(more.prefix(room))
                overflowed = true
            } else {
                data.append(more)
            }
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(decoding: data, as: UTF8.self)
        }

        var over: Bool {
            lock.lock()
            defer { lock.unlock() }
            return overflowed
        }
    }

    /// Whether a program is on the PATH.
    static func exists(_ program: String) -> Bool {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            .components(separatedBy: ":")
            + ["/opt/homebrew/bin", "/usr/local/bin"]
        for folder in paths where !folder.isEmpty {
            let path = (folder as NSString).appendingPathComponent(program)
            if FileManager.default.isExecutableFile(atPath: path) { return true }
        }
        return false
    }

    /// Where a program is, so it can be run without a shell.
    static func which(_ program: String) -> String? {
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin")
            .components(separatedBy: ":")
            + ["/opt/homebrew/bin", "/usr/local/bin"]
        for folder in paths where !folder.isEmpty {
            let path = (folder as NSString).appendingPathComponent(program)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}
