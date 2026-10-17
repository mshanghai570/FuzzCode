import Foundation

final class MockURLProtocol: URLProtocol {
    struct Response {
        let statusCode: Int
        let headers: [String: String]
        let body: Data

        init(statusCode: Int = 200, headers: [String: String] = ["Content-Type": "application/json"], body: Data) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }
    }

    typealias RequestHandler = (URLRequest) throws -> Response

    private static let lock = NSLock()
    private static var handler: RequestHandler?
    private static var requests: [URLRequest] = []

    static var capturedRequests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    static func install(handler: @escaping RequestHandler) {
        lock.lock()
        self.handler = handler
        requests = []
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        requests = []
        lock.unlock()
    }

    static func execute(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        guard let response = try Self.response(for: request) else {
            throw URLError(.unsupportedURL)
        }
        var responseHeaders = response.headers
        responseHeaders["Content-Length"] = String(response.body.count)
        guard let url = request.url,
              let httpResponse = HTTPURLResponse(
                url: url,
                statusCode: response.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: responseHeaders
              ) else {
            throw URLError(.badServerResponse)
        }
        return (response.body, httpResponse)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let response = try Self.response(for: request) else {
                throw URLError(.unsupportedURL)
            }
            var responseHeaders = response.headers
            responseHeaders["Content-Length"] = String(response.body.count)
            guard let url = request.url,
                  let httpResponse = HTTPURLResponse(
                    url: url,
                    statusCode: response.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: responseHeaders
                  ) else {
                throw URLError(.badServerResponse)
            }

            client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
            if !response.body.isEmpty {
                client?.urlProtocol(self, didLoad: response.body)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func response(for request: URLRequest) throws -> Response? {
        lock.lock()
        requests.append(request)
        let handler = self.handler
        lock.unlock()
        return try handler?(request)
    }
}
