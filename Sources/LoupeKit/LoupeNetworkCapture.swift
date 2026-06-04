import Foundation
import LoupeCore
import ObjectiveC

#if canImport(UIKit) || canImport(AppKit)
final class LoupeNetworkCaptureProtocol: URLProtocol {
    private static let handledKey = "dev.loupe.networkCapture.handled"
    private static let fixturePathPrefix = "/__loupe_network_fixture/"

    static func install() {
        URLProtocol.registerClass(Self.self)
        LoupeURLSessionConfigurationSwizzler.install()
    }

    static func apply(to configuration: URLSessionConfiguration) {
        var protocolClasses = configuration.protocolClasses ?? []
        guard !protocolClasses.contains(where: { $0 == Self.self }) else {
            return
        }
        protocolClasses.insert(Self.self, at: 0)
        configuration.protocolClasses = protocolClasses
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil,
              let url = request.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              isFixtureHost(host),
              url.path.hasPrefix(fixturePathPrefix) else {
            return false
        }

        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let fixture = Self.fixtureResponse(for: request)
        let response = HTTPURLResponse(
            url: url,
            statusCode: fixture.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json",
                "X-Loupe-Network-Capture": "url-protocol",
            ]
        )!
        let body = Data(fixture.responseBody.utf8)

        postNetworkEvent(
            url: url.absoluteString,
            method: request.httpMethod,
            statusCode: fixture.statusCode,
            requestBody: requestBodyString(from: request),
            responseBody: fixture.responseBody,
            metadata: fixture.metadata
        )

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !body.isEmpty {
            client?.urlProtocol(self, didLoad: body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func fixtureResponse(for request: URLRequest) -> LoupeNetworkCaptureFixture {
        let path = request.url?.path ?? ""
        let platform = path.contains("/tvos/") ? "tvOS" : "macOS"

        if path.contains("/error-route") {
            return LoupeNetworkCaptureFixture(
                statusCode: 503,
                responseBody: #"{"route":"error","reason":"feed_service_unavailable","retry":true}"#,
                metadata: [
                    "screen": .string("error"),
                    "retry": .bool(true),
                    "source": .string("urlProtocol"),
                    "captureKind": .string("automatic"),
                    "platform": .string(platform),
                ]
            )
        }

        if path.contains("/feed") {
            return LoupeNetworkCaptureFixture(
                statusCode: 204,
                responseBody: #"{"items":[]}"#,
                metadata: [
                    "screen": .string("feed"),
                    "empty": .bool(true),
                    "source": .string("urlProtocol"),
                    "captureKind": .string("automatic"),
                    "platform": .string(platform),
                ]
            )
        }

        return LoupeNetworkCaptureFixture(
            statusCode: 200,
            responseBody: #"{"platform":"\#(platform)","status":"ok"}"#,
            metadata: [
                "screen": .string("workbench"),
                "source": .string("urlProtocol"),
                "captureKind": .string("automatic"),
                "platform": .string(platform),
            ]
        )
    }

    private static func isFixtureHost(_ host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func postNetworkEvent(
        url: String,
        method: String?,
        statusCode: Int,
        requestBody: String?,
        responseBody: String,
        metadata: [String: LoupeMetadataValue]
    ) {
        var userInfo: [String: Any] = [
            "url": url,
            "method": method ?? "GET",
            "statusCode": statusCode,
            "responseBody": responseBody,
        ]
        if let requestBody {
            userInfo["requestBody"] = requestBody
        }
        userInfo["metadata"] = metadata.reduce(into: [String: Any]()) { result, pair in
            result[pair.key] = pair.value.notificationValue
        }

        NotificationCenter.default.post(
            name: Notification.Name("dev.loupe.network"),
            object: nil,
            userInfo: userInfo
        )
    }

    private func requestBodyString(from request: URLRequest) -> String? {
        if let body = request.httpBody {
            return String(data: body, encoding: .utf8)
        }
        return nil
    }
}

private enum LoupeURLSessionConfigurationSwizzler {
    nonisolated(unsafe) private static var didInstall = false

    static func install() {
        guard !didInstall else {
            return
        }
        didInstall = true
        swizzle(
            original: NSSelectorFromString("defaultSessionConfiguration"),
            replacement: #selector(URLSessionConfiguration.loupe_defaultSessionConfiguration)
        )
        swizzle(
            original: NSSelectorFromString("ephemeralSessionConfiguration"),
            replacement: #selector(URLSessionConfiguration.loupe_ephemeralSessionConfiguration)
        )
    }

    private static func swizzle(original: Selector, replacement: Selector) {
        guard let originalMethod = class_getClassMethod(URLSessionConfiguration.self, original),
              let replacementMethod = class_getClassMethod(URLSessionConfiguration.self, replacement) else {
            return
        }
        method_exchangeImplementations(originalMethod, replacementMethod)
    }
}

private extension URLSessionConfiguration {
    @objc class func loupe_defaultSessionConfiguration() -> URLSessionConfiguration {
        let configuration = loupe_defaultSessionConfiguration()
        LoupeNetworkCaptureProtocol.apply(to: configuration)
        return configuration
    }

    @objc class func loupe_ephemeralSessionConfiguration() -> URLSessionConfiguration {
        let configuration = loupe_ephemeralSessionConfiguration()
        LoupeNetworkCaptureProtocol.apply(to: configuration)
        return configuration
    }
}

private struct LoupeNetworkCaptureFixture {
    var statusCode: Int
    var responseBody: String
    var metadata: [String: LoupeMetadataValue]
}

private extension LoupeMetadataValue {
    var notificationValue: Any {
        switch self {
        case let .string(value):
            return value
        case let .int(value):
            return value
        case let .double(value):
            return value
        case let .bool(value):
            return value
        }
    }
}
#endif
