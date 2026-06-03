import Foundation
import LoupeCLIModel
import LoupeCore

extension LoupeCLI {
    static func runtimeFetch(
        _ arguments: [String],
        path: String,
        usage: String
    ) async throws {
        let options = try RuntimeFetchOptions(arguments, usage: usage)
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
            throw CLIError("Usage: loupe app use <bundle-id> | --bundle-id <id> | --host <url> [--udid <sim>]")
        }
        try storeCurrentRuntimeHost(record)
        print("current \(record.bundleID) \(record.host) udid=\(record.udid)")
    }

    static func current(_ arguments: [String]) async throws {
        let options = try RuntimeCurrentOptions(arguments)
        guard let record = try loadCurrentRuntimeHost() else {
            throw CLIError("No current Loupe app runtime. Run `loupe app use <bundle-id>` or `loupe app use --host <url>`.")
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
        let normalizedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let url: URL
        if normalizedPath.contains("?"),
           let queryURL = URL(string: normalizedPath, relativeTo: host)?.absoluteURL {
            url = queryURL
        } else {
            url = host.appendingPathComponent(normalizedPath)
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
            throw CLIError("No stored Loupe app runtime for bundle \(bundleID). Run `loupe app list` or launch with `loupe app launch --bundle-id \(bundleID)`.")
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

    static func runtimeHostRecordURL(udid: String, bundleID: String) -> URL {
        let filename = "\(runtimeRecordPathComponent(udid))--\(runtimeRecordPathComponent(bundleID)).json"
        return runtimeHostDirectory().appendingPathComponent(filename)
    }

    static func currentRuntimeHostURL() -> URL {
        runtimeHostDirectory().appendingPathComponent("current.json")
    }

    static func storeRuntimeHost(udid: String, bundleID: String, host: URL) throws {
        let directory = runtimeHostDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let record = LoupeRuntimeHostRecord(udid: udid, bundleID: bundleID, host: host.absoluteString, updatedAt: Date())
        try writeJSON(record, to: runtimeHostRecordURL(udid: udid, bundleID: bundleID))
    }

    static func loadRuntimeHost(udid: String) throws -> LoupeRuntimeHostRecord? {
        try loadRuntimeHostRecords().first { $0.udid == udid }
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

    static func removeRuntimeHostRecord(_ record: LoupeRuntimeHostRecord) throws {
        let directory = runtimeHostDirectory()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for url in urls where url.pathExtension == "json" && url.lastPathComponent != "current.json" {
            guard let data = try? Data(contentsOf: url),
                  let candidate = try? decoder.decode(LoupeRuntimeHostRecord.self, from: data),
                  candidate.udid == record.udid,
                  candidate.bundleID == record.bundleID,
                  candidate.host == record.host else {
                continue
            }
            try FileManager.default.removeItem(at: url)
        }
    }

    static func runtimeRecordPathComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? String(scalar) : "_"
        }.joined()
    }
}
