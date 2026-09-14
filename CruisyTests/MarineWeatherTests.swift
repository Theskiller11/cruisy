import Testing
import Foundation
@testable import Cruisy

@Suite("Stato del mare")
struct SeaStateTests {

    @Test("La scala Douglas si aggancia alle altezze giuste")
    func douglas() {
        #expect(SeaState(waveHeight: 0) == .calmo)
        #expect(SeaState(waveHeight: 0.3) == .pocoMosso)
        #expect(SeaState(waveHeight: 1.0) == .mosso)
        #expect(SeaState(waveHeight: 2.1) == .moltoMosso)
        #expect(SeaState(waveHeight: 3.5) == .agitato)
        #expect(SeaState(waveHeight: 12) == .moltoGrosso)
        #expect(SeaState(waveHeight: 20) == .tempestoso)
    }

    @Test("Il mare diventa impegnativo da 'agitato' in su")
    func rough() {
        #expect(SeaState.moltoMosso.isRough == false)
        #expect(SeaState.agitato.isRough)
        #expect(SeaState.tempestoso.isRough)
    }

    @Test("Ogni gradino ha un nome e una conseguenza, non solo un numero")
    func everyStepSpeaks() {
        for state in SeaState.allCases {
            #expect(!state.label.isEmpty)
            #expect(!state.comfort.isEmpty)
        }
    }

    @Test("Una scheda senza nessun valore non si mostra")
    func emptiness() {
        let nothing = MarineConditions(time: .now, fetchedAt: .now)
        #expect(nothing.isEmpty)
        #expect(nothing.seaState == nil)

        let something = MarineConditions(time: .now, fetchedAt: .now, waveHeight: 1.4)
        #expect(!something.isEmpty)
        #expect(something.seaState == .moltoMosso)
    }

    @Test("Oltre le tre ore il dato si dichiara vecchio")
    func staleness() {
        let now = Date()
        let fresh = MarineConditions(time: now, fetchedAt: now.addingTimeInterval(-1800), waveHeight: 1)
        let old = MarineConditions(time: now, fetchedAt: now.addingTimeInterval(-5 * 3600), waveHeight: 1)
        #expect(!fresh.isStale(at: now))
        #expect(old.isStale(at: now))
        #expect(old.age(at: now) > 4 * 3600)
    }
}

@Suite("Chiamate al meteo")
@MainActor
struct MarineWeatherServiceTests {

    private let point = Coordinate(latitude: 41.8919, longitude: 12.4812)

    @Test("Senza proxy si va all'origine, in HTTPS")
    func direct() throws {
        let url = MarineWeatherService.endpoint(.forecast, coordinate: point, proxy: nil)
        #expect(url.scheme == "https")
        #expect(url.host() == "api.open-meteo.com")
        #expect(url.path() == "/v1/forecast")

        let marine = MarineWeatherService.endpoint(.marine, coordinate: point, proxy: nil)
        #expect(marine.host() == "marine-api.open-meteo.com")
        #expect(marine.path() == "/v1/marine")
    }

    @Test("Col proxy si passa dal servizio giusto")
    func throughProxy() throws {
        let proxy = try #require(URL(string: "http://192.168.1.174:8099"))
        let air = MarineWeatherService.endpoint(.forecast, coordinate: point, proxy: proxy)
        #expect(air.absoluteString.hasPrefix("http://192.168.1.174:8099/proxy/om/v1/forecast?"))

        let sea = MarineWeatherService.endpoint(.marine, coordinate: point, proxy: proxy)
        #expect(sea.absoluteString.hasPrefix("http://192.168.1.174:8099/proxy/marine/v1/marine?"))
    }

    @Test("Le coordinate si arrotondano a due decimali, come fa la cache del proxy")
    func roundedCoordinates() throws {
        let url = MarineWeatherService.endpoint(.forecast, coordinate: point, proxy: nil)
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.contains { $0.name == "latitude" && $0.value == "41.89" })
        #expect(items.contains { $0.name == "longitude" && $0.value == "12.48" })
        // L'ora in secondi da epoch evita di dover interpretare fusi nella risposta.
        #expect(items.contains { $0.name == "timeformat" && $0.value == "unixtime" })
        #expect(items.contains { $0.name == "wind_speed_unit" && $0.value == "kn" })
    }

    @Test("Un indirizzo scritto senza schema vale lo stesso")
    func lenientProxyAddress() {
        #expect(MarineWeatherService.normalisedProxy("192.168.1.174:8099")?.host() == "192.168.1.174")
        #expect(MarineWeatherService.normalisedProxy(" http://nas.local:8099 ")?.port == 8099)
        #expect(MarineWeatherService.normalisedProxy("") == nil)
        #expect(MarineWeatherService.normalisedProxy(nil) == nil)
    }

    @Test("Senza rete resta quello che c'era, e non si sbaglia")
    func survivesFailure() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineProtocol.self]
        let service = MarineWeatherService(session: URLSession(configuration: configuration),
                                           directory: folder)

        await service.load(for: point, now: .now)
        // Nessun dato, ma nemmeno un crollo: il meteo è un di più, e un'app che
        // smette di dire quanto manca all'all aboard perché non ha le onde ha
        // sbagliato le priorità.
        #expect(service.conditions(for: point, at: .now) == nil)
        #expect(service.isLoading == false)
        #expect(service.lastError != nil)
    }
}

/// Una rete che non c'è: risponde subito con l'errore che darebbe il telefono in
/// modalità aereo, senza aspettare nessun timeout.
private final class OfflineProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }
    override func stopLoading() {}
}

@Suite("Età del dato meteo")
@MainActor
struct MarineFreshnessTests {

    /// Una serie scaricata a un'ora e letta a un'altra deve dichiarare **quella**
    /// età, non quella con cui le singole righe erano state decodificate.
    @Test("L'ora di scaricamento è una sola")
    func singleStamp() async throws {
        let folder = URL.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let service = MarineWeatherService(session: URLSession(configuration: configuration),
                                           directory: folder)

        let observed = Date(timeIntervalSince1970: 1_800_000_000)
        await service.load(for: Coordinate(latitude: 41.89, longitude: 12.48), now: observed)

        let hour = Date(timeIntervalSince1970: 1_800_000_000)
        let conditions = try #require(service.conditions(
            for: Coordinate(latitude: 41.89, longitude: 12.48), at: hour))
        #expect(conditions.fetchedAt == observed)
        #expect(conditions.age(at: observed) == 0)
        #expect(!conditions.isStale(at: observed))
        #expect(conditions.waveHeight == 1.4)
        #expect(conditions.seaState == .moltoMosso)
    }
}

/// Risponde con una griglia oraria minima, uguale per entrambi i servizi.
private final class StubProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let isMarine = request.url?.absoluteString.contains("marine") ?? false
        let body = isMarine
            ? #"{"hourly":{"time":[1800000000],"wave_height":[1.4],"wave_period":[7.0],"sea_surface_temperature":[24.0]}}"#
            : #"{"hourly":{"time":[1800000000],"temperature_2m":[22.0],"weather_code":[3],"wind_speed_10m":[12.0],"wind_direction_10m":[180.0]}}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
