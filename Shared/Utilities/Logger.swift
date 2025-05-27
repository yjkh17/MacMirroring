import os

struct Logger {
    static func log(_ message: String) {
        os_log("%{public}@", message)
    }
}
