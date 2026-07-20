import Darwin
import Foundation

/// A short-lived advisory lock for coordinating App Group file mutations across
/// the containing app and widget extension. `flock` is released automatically if
/// either process exits, so an interrupted refresh cannot leave a stale lock.
struct SharedFileLock {
    enum LockError: Error {
        case openFailed(Int32)
        case timedOut
    }

    let url: URL

    func withLock<T>(timeout: TimeInterval = 1, _ body: () throws -> T) throws -> T {
        let deadline = Date(timeIntervalSinceNow: timeout)
        let descriptor: Int32
        while true {
            let candidate = Darwin.open(url.path,
                                        O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK,
                                        S_IRUSR | S_IWUSR)
            if candidate >= 0 {
                descriptor = candidate
                break
            }
            guard errno == EWOULDBLOCK else { throw LockError.openFailed(errno) }
            guard Date() < deadline else { throw LockError.timedOut }
            usleep(10_000)
        }
        defer { Darwin.close(descriptor) }

        return try body()
    }
}
