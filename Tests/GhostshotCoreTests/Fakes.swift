import Foundation
@testable import GhostshotCore

final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    var responses: [(Data, Int)] = []
    var thrownError: Error?
    private(set) var sentRequests: [URLRequest] = []

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sentRequests.append(request)
        if let thrownError { throw thrownError }
        guard !responses.isEmpty else {
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let (data, status) = responses.removeFirst()
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    var lastBodyJSON: [String: Any] {
        guard let body = sentRequests.last?.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        else { return [:] }
        return json
    }
}

final class FakeProcessRunner: ProcessRunner, @unchecked Sendable {
    var results: [ProcessResult] = []
    var thrownError: Error?
    private(set) var calls: [(executable: String, arguments: [String], stdin: String)] = []

    func run(executable: String, arguments: [String], stdin: String) async throws -> ProcessResult {
        calls.append((executable, arguments, stdin))
        if let thrownError { throw thrownError }
        guard !results.isEmpty else { return ProcessResult(exitCode: 0, stdout: "", stderr: "") }
        return results.removeFirst()
    }
}
