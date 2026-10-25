import Foundation

/// Running a command and reading what it said. Only for the small, quick ones
/// — listing a key's fingerprint, say. Anything that might ask a question goes
/// into a terminal session instead, where there is a pty to answer it on.
enum Shell {
    struct Result: Sendable {
        var status: Int32
        var out: String
        var err: String
        var ok: Bool { status == 0 }
    }

    static func run(_ executable: String, _ arguments: [String]) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Result(
                        status: -1, out: "", err: error.localizedDescription))
                    return
                }
                let outData = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: Result(
                    status: process.terminationStatus,
                    out: String(decoding: outData, as: UTF8.self),
                    err: String(decoding: errData, as: UTF8.self)))
            }
        }
    }
}
