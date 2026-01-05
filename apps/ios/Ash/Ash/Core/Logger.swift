//
//  Logger.swift
//  Ash
//
//  Core Layer - Logging system with levels and build profiles
//

import Foundation
import os.log

// MARK: - Log Level

/// Log severity levels (ordered by verbosity)
enum LogLevel: Int, Comparable, Sendable {
    case verbose = 0  // Most detailed, trace-level
    case debug = 1    // Debug information
    case info = 2     // General information
    case warning = 3  // Potential issues
    case error = 4    // Errors that don't crash
    case fatal = 5    // Critical errors
    case none = 99    // Disable all logging

    var prefix: String {
        switch self {
        case .verbose: return "📝"
        case .debug:   return "🔍"
        case .info:    return "ℹ️"
        case .warning: return "⚠️"
        case .error:   return "❌"
        case .fatal:   return "💀"
        case .none:    return ""
        }
    }

    var osLogType: OSLogType {
        switch self {
        case .verbose, .debug: return .debug
        case .info:            return .info
        case .warning:         return .default
        case .error:           return .error
        case .fatal:           return .fault
        case .none:            return .debug
        }
    }

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Log Category

/// Categorize logs by subsystem for filtering
enum LogCategory: String, Sendable {
    case app = "App"
    case crypto = "Crypto"
    case relay = "Relay"
    case sse = "SSE"
    case poll = "Poll"
    case message = "MSG"
    case ceremony = "Ceremony"
    case storage = "Storage"
    case security = "Security"
    case ui = "UI"
    case perf = "Perf"
    case push = "Push"

    var osLog: OSLog {
        OSLog(subsystem: Log.subsystem, category: rawValue)
    }
}

// MARK: - Build Profile

/// Build configuration profile
enum BuildProfile: Sendable {
    case development
    case production

    /// Current profile based on build configuration
    static var current: BuildProfile {
        #if DEBUG
        return .development
        #else
        return .production
        #endif
    }

    /// Default minimum log level for this profile
    var defaultMinLevel: LogLevel {
        switch self {
        case .development: return .verbose
        case .production:  return .none  // No logging in production
        }
    }

    /// Whether to include file/line info in logs
    var includeSourceLocation: Bool {
        switch self {
        case .development: return true
        case .production:  return false
        }
    }
}

// MARK: - Logger

/// Thread-safe logger with levels and profiles
final class Log: Sendable {
    static let subsystem = Bundle.main.bundleIdentifier ?? "com.monadial.Ash"

    /// Shared instance with default configuration
    nonisolated(unsafe) static var shared = Log()

    /// Minimum log level - messages below this level are ignored
    nonisolated(unsafe) private(set) var minLevel: LogLevel

    /// Current build profile
    let profile: BuildProfile

    /// Whether logging is enabled
    var isEnabled: Bool {
        minLevel != .none
    }

    // MARK: - Initialization

    init(profile: BuildProfile = .current, minLevel: LogLevel? = nil) {
        self.profile = profile
        self.minLevel = minLevel ?? profile.defaultMinLevel
    }

    /// Configure the minimum log level at runtime
    static func setMinLevel(_ level: LogLevel) {
        shared.minLevel = level
    }

    /// Enable all logging (development mode)
    static func enableAll() {
        shared.minLevel = .verbose
    }

    /// Disable all logging (production mode)
    static func disableAll() {
        shared.minLevel = .none
    }

    // MARK: - Logging Methods

    /// Log a message at the specified level
    static func log(
        _ level: LogLevel,
        _ category: LogCategory,
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        guard level >= shared.minLevel else { return }

        let msg = message()
        let output: String

        if shared.profile.includeSourceLocation {
            let filename = (file as NSString).lastPathComponent
            output = "\(level.prefix) [\(category.rawValue)] \(msg) (\(filename):\(line))"
        } else {
            output = "\(level.prefix) [\(category.rawValue)] \(msg)"
        }

        // Use os_log for system integration (visible in Console.app and Xcode)
        os_log("%{public}@", log: category.osLog, type: level.osLogType, output)
    }

    // MARK: - Convenience Methods

    /// Verbose (trace-level) logging
    static func verbose(
        _ category: LogCategory,
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.verbose, category, message(), file: file, function: function, line: line)
    }

    /// Debug logging
    static func debug(
        _ category: LogCategory,
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.debug, category, message(), file: file, function: function, line: line)
    }

    /// Info logging
    static func info(
        _ category: LogCategory,
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.info, category, message(), file: file, function: function, line: line)
    }

    /// Warning logging
    static func warning(
        _ category: LogCategory,
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.warning, category, message(), file: file, function: function, line: line)
    }

    /// Error logging
    static func error(
        _ category: LogCategory,
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.error, category, message(), file: file, function: function, line: line)
    }

    /// Fatal error logging
    static func fatal(
        _ category: LogCategory,
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        log(.fatal, category, message(), file: file, function: function, line: line)
    }

    // MARK: - Performance Logging

    /// Measure execution time of a block
    @discardableResult
    static func measure<T>(
        _ category: LogCategory,
        _ operation: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: () throws -> T
    ) rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let ms = elapsed * 1000

        if ms > 100 {
            warning(category, "\(operation) took \(String(format: "%.1f", ms))ms (SLOW)", file: file, function: function, line: line)
        } else if ms > 16 {
            debug(category, "\(operation) took \(String(format: "%.1f", ms))ms", file: file, function: function, line: line)
        } else {
            verbose(category, "\(operation) took \(String(format: "%.2f", ms))ms", file: file, function: function, line: line)
        }

        return result
    }

    /// Async version of measure (MainActor-isolated for use in view models)
    @MainActor
    @discardableResult
    static func measureAsync<T>(
        _ category: LogCategory,
        _ operation: String,
        file: String = #file,
        function: String = #function,
        line: Int = #line,
        block: () async throws -> T
    ) async rethrows -> T {
        let start = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let ms = elapsed * 1000

        if ms > 100 {
            warning(category, "\(operation) took \(String(format: "%.1f", ms))ms (SLOW)", file: file, function: function, line: line)
        } else if ms > 16 {
            debug(category, "\(operation) took \(String(format: "%.1f", ms))ms", file: file, function: function, line: line)
        } else {
            verbose(category, "\(operation) took \(String(format: "%.2f", ms))ms", file: file, function: function, line: line)
        }

        return result
    }
}

// MARK: - Signpost Integration (for Instruments profiling)

import os.signpost

extension Log {
    private static let signpostLog = OSLog(subsystem: subsystem, category: .pointsOfInterest)

    /// Begin a signpost interval (for Instruments profiling)
    static func signpostBegin(_ name: StaticString, _ message: String = "") {
        #if DEBUG
        os_signpost(.begin, log: signpostLog, name: name, "%{public}s", message)
        #endif
    }

    /// End a signpost interval
    static func signpostEnd(_ name: StaticString, _ message: String = "") {
        #if DEBUG
        os_signpost(.end, log: signpostLog, name: name, "%{public}s", message)
        #endif
    }

    /// Single signpost event
    static func signpostEvent(_ name: StaticString, _ message: String = "") {
        #if DEBUG
        os_signpost(.event, log: signpostLog, name: name, "%{public}s", message)
        #endif
    }
}
