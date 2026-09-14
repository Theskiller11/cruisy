import Testing
import Foundation
@testable import Cruisy

/// **Serializzata di proposito**: le prove condividono lo stesso interruttore
/// statico dentro lo stub di rete, e Swift Testing di suo manderebbe i casi in
/// parallelo — uno imposterebbe lo scenario mentre un altro sta leggendo il suo.
@Suite("Ricerca di una nave su Wikidata", .serialized)
@MainActor
struct ShipLookupTests {

    private func service() -> ShipLookupService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WikidataStub.self]
        return ShipLookupService(session: URLSession(configuration: configuration))
    }

    @Test("Una nave trovata si compila per intero")
    func found() async throws {
        WikidataStub.scenario = .explora
        let lookup = service()
        await lookup.search("Explora III")

        guard case .found(let ship) = lookup.outcome else {
            Issue.record("atteso .found, ottenuto \(lookup.outcome)")
            return
        }
        #expect(ship.name == "Explora III")
        #expect(ship.imo == "9869899")
        #expect(ship.tonnage == 73904)
        #expect(ship.length == 268)
        #expect(ship.year == 2026)
        // L'armatore è un'altra voce: il nome va risolto con una seconda chiamata.
        #expect(ship.operatorName == "Explora Journeys")
    }

    @Test("Quello che si impara resta nell'elenco")
    func learned() async throws {
        WikidataStub.scenario = .explora
        await service().search("Explora III")

        let found = try #require(ShipDirectory.shared.lookup("explora iii"))
        #expect(found.imo == "9869899")
        // E anche scritta come capita a chi digita.
        #expect(ShipDirectory.shared.lookup("Explora 3") == nil)
        #expect(ShipDirectory.shared.lookup("EXPLORA III")?.imo == "9869899")
    }

    @Test("Un videogioco non è una nave")
    func rejectsNonShips() async {
        // Cercando «Explora III» su Wikidata il primo risultato è davvero un
        // videogioco del 1990. Senza il controllo sulla descrizione, l'app
        // mostrerebbe la stazza di un videogioco.
        WikidataStub.scenario = .onlyVideogame
        let lookup = service()
        await lookup.search("Explora III")
        #expect(lookup.outcome == .notFound)
    }

    @Test("Senza rete non si inventa niente")
    func offline() async {
        WikidataStub.scenario = .offline
        let lookup = service()
        await lookup.search("Explora III")
        guard case .failed = lookup.outcome else {
            Issue.record("atteso .failed, ottenuto \(lookup.outcome)")
            return
        }
    }

    @Test("Un nome troppo corto non fa partire nessuna chiamata")
    func tooShort() async {
        WikidataStub.scenario = .offline
        let lookup = service()
        await lookup.search("Ex")
        #expect(lookup.outcome == .idle)
    }
}

/// Le due risposte di Wikidata che servono, ridotte all'osso.
private final class WikidataStub: URLProtocol {
    enum Scenario { case explora, onlyVideogame, offline }
    nonisolated(unsafe) static var scenario: Scenario = .explora

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url?.absoluteString ?? ""
        if Self.scenario == .offline {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }

        let body: String
        if url.contains("wbsearchentities") {
            body = Self.scenario == .onlyVideogame
                ? #"{"search":[{"id":"Q53126208","label":"Explora III","description":"1990 video game"}]}"#
                : #"{"search":[{"id":"Q53126208","label":"Explora III","description":"1990 video game"},{"id":"Q141212402","label":"Explora III","description":"Cruise ship of Explora Journeys"}]}"#
        } else if url.contains("Q114357978") {
            body = #"{"entities":{"Q114357978":{"labels":{"it":{"value":"Explora Journeys"}},"claims":{}}}}"#
        } else {
            body = #"""
            {"entities":{"Q141212402":{
              "labels":{"mul":{"value":"Explora III"},"en":{"value":"Explora III"}},
              "claims":{
                "P458":[{"mainsnak":{"datavalue":{"value":"9869899"}}}],
                "P1093":[{"mainsnak":{"datavalue":{"value":{"amount":"+73904"}}}}],
                "P2043":[{"mainsnak":{"datavalue":{"value":{"amount":"+268"}}}}],
                "P729":[{"mainsnak":{"datavalue":{"value":{"time":"+2026-00-00T00:00:00Z"}}}}],
                "P137":[{"mainsnak":{"datavalue":{"value":{"id":"Q114357978"}}}}]
              }}}}
            """#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
