import Foundation
import LoupeCLICore
import LoupeCore

extension LoupeCLI {
    static func runtimeFetch(
        _ arguments: [String],
        path: String,
        usage: String,
        allowsAlias: Bool = false
    ) async throws {
        let options = try RuntimeFetchOptions(arguments, usage: usage, allowsAlias: allowsAlias)
        let data = try await runtimeData(path: path, options: options)
        try write(data: data, outputURL: options.outputURL)
    }

    static func use(_ arguments: [String]) async throws {
        let options = try RuntimeUseOptions(arguments)
        let record: LoupeRuntimeHostRecord
        if let host = options.host {
            let state = try await fetchRuntimeState(host: host, timeout: options.timeout)
            let udid = state.identity.simulatorUDID ?? options.udid ?? "unknown"
            let bundleID = state.identity.bundleIdentifier ?? options.bundleID ?? "unknown"
            record = LoupeRuntimeHostRecord(udid: udid, bundleID: bundleID, host: host.absoluteString, updatedAt: Date())
        } else if let bundleID = options.bundleID {
            record = try await runtimeHostRecord(bundleID: bundleID, udid: options.udid, timeout: options.timeout)
        } else {
            throw CLIError("Usage: loupe use <bundle-id> | --bundle-id <id> | --host <url> [--udid <sim>]")
        }
        try storeCurrentRuntimeHost(record)
        print("current \(record.bundleID) \(record.host) udid=\(record.udid)")
    }

    static func current(_ arguments: [String]) async throws {
        let options = try RuntimeCurrentOptions(arguments)
        guard let record = try loadCurrentRuntimeHost() else {
            throw CLIError("No current Loupe runtime. Run `loupe use <bundle-id>` or `loupe use --host <url>`.")
        }
        var live = false
        if let host = URL(string: record.host),
           let state = try? await fetchRuntimeState(host: host, timeout: options.timeout) {
            live = runtimeState(state, matches: record)
        }
        if options.json {
            let row = RuntimeListRow(
                udid: record.udid,
                simulator: "",
                bundleID: record.bundleID,
                host: record.host,
                pid: "",
                live: live,
                startedAt: "",
                updatedAt: isoString(record.updatedAt)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            FileHandle.standardOutput.write(try encoder.encode(row))
            FileHandle.standardOutput.write(Data("\n".utf8))
            return
        }
        print("bundle\t host\tudid\tlive\tupdatedAt")
        print("\(record.bundleID)\t\(record.host)\t\(record.udid)\t\(live ? "yes" : "no")\t\(isoString(record.updatedAt))")
    }

    static func runtimeData(path: String, options: RuntimeFetchOptions) async throws -> Data {
        let host = try await resolvedRuntimeHost(
            requestedHost: options.host,
            hostWasExplicit: options.hostWasExplicit,
            udid: options.udid,
            bundleID: options.bundleID
        )
        if let udid = options.udid {
            try await validateRuntimeIdentity(host: host, expectedUDID: udid, timeout: options.timeout)
        }
        var url = host.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        if let alias = options.alias {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "alias", value: alias)]
            url = components?.url ?? url
        }
        let (data, response) = try await httpData(from: url, timeout: options.timeout, label: "runtime fetch")
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CLIError("runtime fetch expected an HTTP response")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CLIError("runtime fetch failed with HTTP \(httpResponse.statusCode)")
        }
        return data
    }

    static func runtimeState(_ state: LoupeRuntimeState, matches record: LoupeRuntimeHostRecord) -> Bool {
        guard state.identity.simulatorUDID == record.udid else {
            return false
        }
        guard let bundleIdentifier = state.identity.bundleIdentifier else {
            return true
        }
        return bundleIdentifier == record.bundleID
    }

    static func resolvedRuntimeHost(
        requestedHost: URL,
        hostWasExplicit: Bool,
        udid: String?,
        bundleID: String? = nil
    ) async throws -> URL {
        guard !hostWasExplicit else {
            return requestedHost
        }

        if let bundleID {
            let record = try await runtimeHostRecord(bundleID: bundleID, udid: udid, timeout: 1)
            guard let url = URL(string: record.host), !record.host.isEmpty else {
                throw CLIError("Stored Loupe runtime for \(bundleID) has an invalid host.")
            }
            return url
        }

        if let udid {
            let resolvedUDID = try resolvedBackendUDID(udid)
            if let record = try loadRuntimeHost(udid: resolvedUDID),
               let url = URL(string: record.host),
               !record.host.isEmpty {
                return url
            }
        }

        if requestedHost.absoluteString == "http://127.0.0.1:8765",
           let current = try loadCurrentRuntimeHost(),
           let url = URL(string: current.host),
           !current.host.isEmpty {
            return url
        }

        return requestedHost
    }

    static func runtimeHostRecord(bundleID: String, udid: String?, timeout: TimeInterval) async throws -> LoupeRuntimeHostRecord {
        let resolvedUDID = try udid.map(resolvedBackendUDID)
        let records = try loadRuntimeHostRecords()
            .filter { record in
                record.bundleID == bundleID && (resolvedUDID == nil || record.udid == resolvedUDID)
            }
        guard !records.isEmpty else {
            throw CLIError("No stored Loupe runtime for bundle \(bundleID). Run `loupe runtimes` or launch with `loupe start --bundle-id \(bundleID)`.")
        }
        for record in records {
            guard let host = URL(string: record.host) else {
                continue
            }
            if let state = try? await fetchRuntimeState(host: host, timeout: timeout),
               runtimeState(state, matches: record) {
                return record
            }
        }
        return records[0]
    }

    static func runtimeHostDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".loupe", isDirectory: true)
            .appendingPathComponent("runtimes", isDirectory: true)
    }

    static func runtimeHostRecordURL(udid: String) -> URL {
        runtimeHostDirectory().appendingPathComponent("\(udid).json")
    }

    static func currentRuntimeHostURL() -> URL {
        runtimeHostDirectory().appendingPathComponent("current.json")
    }

    static func storeRuntimeHost(udid: String, bundleID: String, host: URL) throws {
        let directory = runtimeHostDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = LoupeRuntimeHostRecord(udid: udid, bundleID: bundleID, host: host.absoluteString, updatedAt: Date())
        try writeJSON(record, to: runtimeHostRecordURL(udid: udid))
    }

    static func loadRuntimeHost(udid: String) throws -> LoupeRuntimeHostRecord? {
        let url = runtimeHostRecordURL(udid: udid)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoupeRuntimeHostRecord.self, from: data)
    }

    static func storeCurrentRuntimeHost(_ record: LoupeRuntimeHostRecord) throws {
        let directory = runtimeHostDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var updatedRecord = record
        updatedRecord.updatedAt = Date()
        try writeJSON(updatedRecord, to: currentRuntimeHostURL())
    }

    static func loadCurrentRuntimeHost() throws -> LoupeRuntimeHostRecord? {
        let url = currentRuntimeHostURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LoupeRuntimeHostRecord.self, from: data)
    }

    static func loadRuntimeHostRecords() throws -> [LoupeRuntimeHostRecord] {
        let directory = runtimeHostDirectory()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return urls
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != "current.json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(LoupeRuntimeHostRecord.self, from: data)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
}

struct RuntimeFetchOptions {
    var host: URL
    var hostWasExplicit: Bool
    var udid: String?
    var bundleID: String?
    var alias: String?
    var outputURL: URL?
    var timeout: TimeInterval

    init(_ arguments: [String], usage: String, allowsAlias: Bool = false) throws {
        host = URL(string: "http://127.0.0.1:8765")!
        hostWasExplicit = false
        var udid: String?
        var bundleID: String?
        var alias: String?
        var outputURL: URL?
        var timeout: TimeInterval = 5
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case let value where allowsAlias && !value.hasPrefix("--") && alias == nil:
                alias = value
            case "--host":
                let raw = try Self.value(after: "--host", in: arguments, index: &index)
                guard let url = URL(string: raw) else {
                    throw CLIError("Invalid --host URL: \(raw)")
                }
                host = url
                hostWasExplicit = true
            case "--udid", "--device":
                udid = try Self.value(after: arguments[index], in: arguments, index: &index)
            case "--bundle-id":
                bundleID = try Self.value(after: "--bundle-id", in: arguments, index: &index)
            case "--alias", "--name":
                guard allowsAlias else {
                    throw CLIError("Unknown runtime option: \(arguments[index])")
                }
                alias = try Self.value(after: arguments[index], in: arguments, index: &index)
            case "--output":
                outputURL = URL(fileURLWithPath: try Self.value(after: "--output", in: arguments, index: &index))
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            case "--help", "-h":
                throw CLIError(usage)
            default:
                throw CLIError("Unknown runtime option: \(arguments[index])")
            }
            index += 1
        }
        self.udid = udid
        self.bundleID = bundleID
        self.alias = alias
        self.outputURL = outputURL
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
        self.timeout = timeout
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func double(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Double(raw) else {
            throw CLIError("\(option) expects a number")
        }
        return value
    }
}

struct RuntimeUseOptions {
    var host: URL?
    var bundleID: String?
    var udid: String?
    var timeout: TimeInterval

    init(_ arguments: [String]) throws {
        host = nil
        bundleID = nil
        udid = nil
        timeout = 2
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case let value where !value.hasPrefix("--") && bundleID == nil:
                bundleID = value
            case "--host":
                let raw = try Self.value(after: "--host", in: arguments, index: &index)
                guard let url = URL(string: raw) else {
                    throw CLIError("Invalid --host URL: \(raw)")
                }
                host = url
            case "--bundle-id":
                bundleID = try Self.value(after: "--bundle-id", in: arguments, index: &index)
            case "--udid", "--device":
                udid = try Self.value(after: arguments[index], in: arguments, index: &index)
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            default:
                throw CLIError("Unknown use option: \(arguments[index])")
            }
            index += 1
        }
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func double(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Double(raw) else {
            throw CLIError("\(option) expects a number")
        }
        return value
    }
}

struct RuntimeCurrentOptions {
    var json: Bool
    var timeout: TimeInterval

    init(_ arguments: [String]) throws {
        json = false
        timeout = 1
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "--json":
                json = true
            case "--timeout":
                timeout = try Self.double(after: "--timeout", in: arguments, index: &index)
            default:
                throw CLIError("Unknown current option: \(arguments[index])")
            }
            index += 1
        }
        guard timeout > 0 else {
            throw CLIError("--timeout must be greater than 0")
        }
    }

    private static func value(after option: String, in arguments: [String], index: inout Int) throws -> String {
        let valueIndex = index + 1
        guard valueIndex < arguments.count else {
            throw CLIError("\(option) requires a value")
        }
        index = valueIndex
        return arguments[valueIndex]
    }

    private static func double(after option: String, in arguments: [String], index: inout Int) throws -> Double {
        let raw = try value(after: option, in: arguments, index: &index)
        guard let value = Double(raw) else {
            throw CLIError("\(option) expects a number")
        }
        return value
    }
}
