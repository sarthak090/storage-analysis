import Foundation

public struct CommandOutput: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
}

/// Runs a command without a shell, off the cooperative thread pool.
/// Only ever used for read-only tools (`du`, `df`).
public enum CommandRunner {
    public static func run(_ executable: String, _ arguments: [String]) async throws -> CommandOutput {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                // Drain stderr concurrently so a chatty stderr can't fill its pipe
                // buffer and deadlock us while we read stdout.
                let errBox = DataBox()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                group.wait()
                process.waitUntilExit()

                continuation.resume(returning: CommandOutput(
                    status: process.terminationStatus,
                    stdout: String(decoding: outData, as: UTF8.self),
                    stderr: String(decoding: errBox.data, as: UTF8.self)
                ))
            }
        }
    }
}

/// Written by one queue, read after `DispatchGroup.wait()` on another.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Runs blocking work (file enumeration) off the cooperative thread pool.
func offCooperativePool<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(returning: work())
        }
    }
}
