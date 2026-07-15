import Foundation

struct DaemonState {
    let pidPath: String
    private let lockFD: Int32

    init(dataDir: String) {
        self.pidPath = "\(dataDir)/daemon.pid"
        self.lockFD = -1
    }

    /// Check if the daemon is running by verifying the PID is alive AND
    /// is actually an msl process (not a recycled PID belonging to something else).
    func isRunning() -> Bool {
        guard let pid = readPID() else { return false }
        guard kill(pid, 0) == 0 else {
            // Stale PID file — process is dead, clean it up
            try? FileManager.default.removeItem(atPath: pidPath)
            return false
        }
        // Verify the process is actually msl (not a recycled PID)
        return processIsMsl(pid)
    }

    func readPID() -> pid_t? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: pidPath)),
              let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = pid_t(str) else { return nil }
        return pid
    }

    /// Atomically write the PID file using flock to prevent concurrent
    /// --start invocations from racing past the isRunning() check.
    func writePID() throws {
        let lockPath = pidPath + ".lock"
        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            throw MslError("cannot create PID lock file: \(String(cString: strerror(errno)))")
        }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            throw MslError("another msl --start is already running (lock held)")
        }
        let pid = getpid()
        try "\(pid)".write(toFile: pidPath, atomically: true, encoding: .utf8)
        flock(fd, LOCK_UN)
        close(fd)
        try? FileManager.default.removeItem(atPath: lockPath)
    }

    func removePID() {
        try? FileManager.default.removeItem(atPath: pidPath)
    }

    /// Check if the process at `pid` is actually msl by reading its comm.
    private func processIsMsl(_ pid: pid_t) -> Bool {
        let commPath = "/proc/\(pid)/comm"
        // macOS doesn't have /proc — use a different approach
        if FileManager.default.fileExists(atPath: commPath) {
            if let data = try? String(contentsOfFile: commPath, encoding: .utf8) {
                return data.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("msl")
            }
        }
        // macOS: check the process name via ps
        let result = shellOutput("ps -p \(pid) -o comm= 2>/dev/null")
        return result.contains("msl") && !result.contains("grep")
    }
}