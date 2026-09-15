import Testing
import Foundation
@testable import Cruisy

/// Il livello di rete comune: una regola sola per tutti i client.
@Suite("Client di rete", .serialized)
struct NetworkClientTests {

    private func client(timeout: TimeInterval = 12) -> NetworkClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [EchoStub.self]
        return NetworkClient(session: URLSession(configuration: configuration),
                             userAgent: "Cruisy/test", timeout: timeout)
    }

    @Test("Ogni richiesta dice chi siamo e quanto aspetta")
    func requestCarriesAgentAndTimeout() {
        let request = client(timeout: 7).request(URL(string: "https://example.org/x")!)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Cruisy/test")
        #expect(request.timeoutInterval == 7)
        #expect(request.allowsExpensiveNetworkAccess)
    }

    @Test("Una richiesta frugale rispetta la scelta sulle reti a consumo")
    func frugalRequestsFollowThePolicy() {
        let request = client().request(URL(string: "https://example.org/foto.jpg")!, cost: .frugal)
        #expect(request.allowsExpensiveNetworkAccess == PhotoDownloadPolicy.allowsMetered)
        #expect(request.allowsConstrainedNetworkAccess == PhotoDownloadPolicy.allowsMetered)
    }

    @Test("Un JSON buono torna come dizionario")
    func jsonDecodes() async throws {
        EchoStub.reply = (200, #"{"query":{"pages":{}}}"#)
        let object = try await client().json(URL(string: "https://example.org/api")!)
        #expect(object["query"] != nil)
    }

    @Test("Uno stato HTTP di errore è un errore, non un dizionario vuoto")
    func badStatusThrows() async {
        EchoStub.reply = (503, "{}")
        await #expect(throws: NetworkClient.Failure.status(503)) {
            try await client().json(URL(string: "https://example.org/api")!)
        }
    }

    @Test("Un corpo che non è JSON è un errore dichiarato")
    func malformedThrows() async {
        EchoStub.reply = (200, "<html>manutenzione</html>")
        await #expect(throws: NetworkClient.Failure.malformed) {
            try await client().json(URL(string: "https://example.org/api")!)
        }
    }
}

/// Risponde a tutto con quello che gli si dice.
private final class EchoStub: URLProtocol {
    nonisolated(unsafe) static var reply: (status: Int, body: String) = (200, "{}")

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.reply.status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
