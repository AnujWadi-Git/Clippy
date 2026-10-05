import Foundation

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var passes = 0

func expect(_ cond: @autoclosure () throws -> Bool, _ msg: @autoclosure () -> String = "", line: Int = #line, file: String = #fileID) {
    if (try? cond()) == true { passes += 1 } else { failures += 1; print("  FAIL \(file):\(line) \(msg())") }
}

func suite(_ name: String, _ body: () throws -> Void) {
    print("• \(name)")
    do { try body() } catch { failures += 1; print("  FAIL (threw) \(error)") }
}

/// Runs an async body to completion (the check runner is synchronous).
func blocking(_ body: @escaping @Sendable () async throws -> Void) throws {
    let sem = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var err: Error?
    Task { do { try await body() } catch { err = error }; sem.signal() }
    sem.wait()
    if let err { throw err }
}
