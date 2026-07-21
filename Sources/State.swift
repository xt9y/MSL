import Foundation

struct DaemonState {
    let pidPath: String
    let deadMarkerPath: String
    var lockFD: Int32
    let dataDir: String

    init(dataDir: String) {
        self.pidPath = "\(dataDir)/daemon.pid"
        self.deadMarkerPath = "\(dataDir)/vm.dead"
        self.lockFD = -1
        self.dataDir = dataDir
    }

    func isRunning() -> Bool {
        guard let pid = readPID() else { return false }
        guard processIsMsl(pid) else {
            try? FileManager.default.removeItem(atPath: pidPath)
            return false
        }
        return !FileManager.default.fileExists(atPath: deadMarkerPath)
    }

    func readPID() -> pid_t? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: pidPath)),
              let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let pid = pid_t(str) else { return nil }
        return pid
    }

    /// Acquire an exclusive flock on the PID file and hold it for our
    /// entire lifetime.  This prevents a second daemon from starting
    /// while we are alive, even if our PID file is briefly absent.
    ///
    /// Writes the PID directly to the already-open fd (via write + ftruncate),
    /// never through an atomic write that would replace the inode and defeat
    /// the flock.
    mutating func writePID() throws {
        let fd = open(pidPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            throw MslError("cannot create PID file: \(String(cString: strerror(errno)))")
        }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            throw MslError("another msl start is already running (lock held)")
        }
        let pid = getpid()
        let pidStr = "\(pid)\n"
        _ = ftruncate(fd, 0)
        lseek(fd, 0, SEEK_SET)
        let pidData = pidStr.data(using: .utf8)!
        var written = 0
        while written < pidData.count {
            let n = pidData.withUnsafeBytes { ptr in
                write(fd, ptr.baseAddress! + written, pidData.count - written)
            }
            if n <= 0 { close(fd); throw MslError("failed to write PID: \(String(cString: strerror(errno)))") }
            written += n
        }
        lockFD = fd
    }

    mutating func removePID() {
        if lockFD >= 0 {
            close(lockFD)
            lockFD = -1
        }
        try? FileManager.default.removeItem(atPath: pidPath)
    }

    private func processIsMsl(_ pid: pid_t) -> Bool {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let len = proc_pidpath(pid, &buf, UInt32(buf.count))
        guard len > 0 else {
            try? FileManager.default.removeItem(atPath: pidPath)
            return false
        }
        let path = String(cString: buf)
        guard path.hasSuffix("/msl") else { return false }
        return true
    }
}
