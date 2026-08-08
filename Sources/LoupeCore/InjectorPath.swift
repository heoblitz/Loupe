import Foundation

public enum LoupeInjectorPlatform: Sendable, Equatable {
    case iOSSimulator
    case macOS
}

public struct LoupeInjectorPathResolver {
    public var platform: LoupeInjectorPlatform
    public var environment: [String: String]
    public var executableURL: URL?
    public var extraSearchRoots: [URL]
    public var fileExists: (String) -> Bool

    public init(
        platform: LoupeInjectorPlatform = .iOSSimulator,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        executableURL: URL? = Bundle.main.executableURL,
        extraSearchRoots: [URL] = [],
        fileExists: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.platform = platform
        self.environment = environment
        self.executableURL = executableURL
        self.extraSearchRoots = extraSearchRoots
        self.fileExists = fileExists
    }

    public func resolve() -> String? {
        for candidate in candidates() where fileExists(candidate.path) {
            return candidate.path
        }

        return nil
    }

    public func candidates() -> [URL] {
        var candidates: [URL] = []

        if platform == .macOS,
           let explicitMacOSPath = environment["LOUPE_MACOS_INJECTOR_PATH"],
           !explicitMacOSPath.isEmpty
        {
            candidates.append(URL(fileURLWithPath: explicitMacOSPath))
        }
        if let explicitPath = environment["LOUPE_INJECTOR_PATH"], !explicitPath.isEmpty {
            candidates.append(URL(fileURLWithPath: explicitPath))
        }

        if let executableURL {
            let cellarRoot = executableURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            candidates.append(Self.injectorExecutable(in: cellarRoot, platform: platform))
        }

        for root in extraSearchRoots {
            candidates.append(Self.injectorExecutable(in: root, platform: platform))
        }

        candidates.append(Self.injectorExecutable(in: URL(fileURLWithPath: "/opt/homebrew/opt/loupe"), platform: platform))
        candidates.append(Self.injectorExecutable(in: URL(fileURLWithPath: "/usr/local/opt/loupe"), platform: platform))

        var seen: Set<String> = []
        return candidates.filter { url in
            let path = url.path
            guard !seen.contains(path) else {
                return false
            }
            seen.insert(path)
            return true
        }
    }

    public static func injectorExecutable(in root: URL, platform: LoupeInjectorPlatform = .iOSSimulator) -> URL {
        var url = root
            .appendingPathComponent("libexec")
            .appendingPathComponent("LoupeInjector.framework")
        if platform == .macOS {
            url.appendPathComponent("macos")
        }
        return url.appendingPathComponent("LoupeInjector")
    }
}
