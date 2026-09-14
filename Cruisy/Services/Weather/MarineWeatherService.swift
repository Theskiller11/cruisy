import Foundation
import Observation

/// Il meteo del mare lungo la rotta.
///
/// Due sorgenti Open-Meteo: la previsione atmosferica (vento, temperatura, cielo) e
/// il modello marino (onda, periodo, temperatura dell'acqua). WeatherKit l'altezza
/// d'onda non la espone, ed è proprio il numero che interessa a chi sta in mezzo al
/// mare.
///
/// Tutto passa da un solo posto perché a bordo la rete è cara e intermittente: si
/// scarica una finestra di tre giorni per volta, la si tiene su disco, e finché
/// non scade non si chiede più niente. Se la rete non c'è si serve la copia
/// vecchia — dichiarando quanto è vecchia, che è l'unica cosa che rende un dato
/// scaduto ancora utile.
@Observable
@MainActor
final class MarineWeatherService {

    /// La finestra oraria scaricata, per un punto.
    private struct Series: Codable, Sendable {
        var coordinate: Coordinate
        var fetchedAt: Date
        var hours: [MarineConditions]

        /// L'ora più vicina, timbrata con **il** momento in cui la serie è stata
        /// scaricata. Quando lo scaricamento lo si registra in due posti, prima o poi
        /// i due non concordano e la scheda dichiara vecchio un dato appena preso.
        func conditions(at date: Date) -> MarineConditions? {
            guard var best = hours.min(by: {
                abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date))
            }) else { return nil }
            best.fetchedAt = fetchedAt
            return best
        }
    }

    private(set) var isLoading = false
    /// L'ultimo errore, se serve raccontarlo. Non è una condizione bloccante: il
    /// meteo è un di più, e un'app che smette di dire quanto manca all'all aboard
    /// perché non ha caricato le onde ha sbagliato le priorità.
    private(set) var lastError: String?

    private var series: [String: Series] = [:]
    private let session: URLSession
    private let directory: URL?

    /// Le previsioni restano valide un'ora: i modelli globali girano ogni sei ore,
    /// ma la finestra oraria avanza, e un'ora è il passo con cui i valori cambiano.
    private let timeToLive: TimeInterval = 3600

    init(session: URLSession = .shared, directory: URL? = nil) {
        self.session = session
        if let directory {
            self.directory = directory
        } else {
            let caches = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
            let folder = caches?.appendingPathComponent("Meteo", isDirectory: true)
            if let folder {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }
            self.directory = folder
        }
    }

    // MARK: Lettura

    /// Le condizioni note per un punto a una certa ora, se ne abbiamo.
    func conditions(for coordinate: Coordinate, at date: Date) -> MarineConditions? {
        cached(for: coordinate)?.conditions(at: date)
    }

    /// Carica, se serve. Chiamarla spesso non costa: se la finestra in memoria è
    /// ancora buona non tocca la rete.
    func load(for coordinate: Coordinate, now: Date = .now) async {
        let key = Self.key(for: coordinate)
        if let existing = cached(for: coordinate),
           now.timeIntervalSince(existing.fetchedAt) < timeToLive {
            return
        }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            let hours = try await fetch(coordinate: coordinate)
            guard !hours.isEmpty else { return }
            let fresh = Series(coordinate: coordinate, fetchedAt: now, hours: hours)
            series[key] = fresh
            write(fresh, key: key)
            lastError = nil
        } catch is CancellationError {
            // Uscire da una schermata non è un errore.
        } catch {
            // Restiamo con quello che c'è: la copia vecchia è già in `series`.
            lastError = error.localizedDescription
        }
    }

    // MARK: Rete

    private func fetch(coordinate: Coordinate) async throws -> [MarineConditions] {
        async let air = decode(url(service: .forecast, coordinate: coordinate))
        async let sea = decode(url(service: .marine, coordinate: coordinate))
        let (airHours, seaHours) = try await (air, sea)

        // Le due serie hanno la stessa griglia oraria, ma il modello marino può
        // saltare del tutto un punto in acque chiuse: si tiene la serie
        // atmosferica come impalcatura e si innesta il mare dov'è disponibile.
        let seaByTime = Dictionary(seaHours.map { ($0.time, $0) }, uniquingKeysWith: { first, _ in first })
        return airHours.map { hour in
            var merged = hour
            if let sea = seaByTime[hour.time] {
                merged.waveHeight = sea.waveHeight
                merged.wavePeriod = sea.wavePeriod
                merged.seaTemperature = sea.seaTemperature
            }
            return merged
        }
    }

    enum Service {
        case forecast, marine

        var proxyKey: String { self == .forecast ? "om" : "marine" }
        var host: String { self == .forecast ? "api.open-meteo.com" : "marine-api.open-meteo.com" }
        var path: String { self == .forecast ? "/v1/forecast" : "/v1/marine" }
        var hourly: String {
            self == .forecast
                ? "temperature_2m,weather_code,wind_speed_10m,wind_direction_10m"
                : "wave_height,wave_period,sea_surface_temperature"
        }
    }

    /// L'indirizzo del proxy, se ne è stato configurato uno.
    ///
    /// Serve a chi ne ha uno in casa — la stessa risposta serve tutti i telefoni,
    /// e il piano gratuito di Open-Meteo ha un tetto giornaliero. Senza, si va
    /// direttamente all'origine: l'app funziona lo stesso, per chiunque.
    static var proxyBase: URL? { normalisedProxy(UserDefaults.standard.string(forKey: "cruisy.proxy")) }

    /// Un indirizzo scritto a mano arriva quasi sempre senza schema: "192.168.1.174:8099"
    /// è quello che si legge sulla dashboard, e rifiutarlo per un `http://` mancante
    /// sarebbe pedanteria.
    static func normalisedProxy(_ raw: String?) -> URL? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.hasPrefix("http") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: withScheme), url.host() != nil else { return nil }
        return url
    }

    private func url(service: Service, coordinate: Coordinate) -> URL {
        Self.endpoint(service, coordinate: coordinate, proxy: Self.proxyBase)
    }

    static func endpoint(_ service: Service, coordinate: Coordinate, proxy: URL?) -> URL {
        var components: URLComponents
        if let base = proxy, var proxied = URLComponents(url: base, resolvingAgainstBaseURL: false) {
            proxied.path = "/proxy/\(service.proxyKey)\(service.path)"
            components = proxied
        } else {
            components = URLComponents()
            components.scheme = "https"
            components.host = service.host
            components.path = service.path
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.2f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", coordinate.longitude)),
            URLQueryItem(name: "hourly", value: service.hourly),
            URLQueryItem(name: "wind_speed_unit", value: "kn"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "UTC"),
            URLQueryItem(name: "forecast_days", value: "3"),
        ]
        return components.url!
    }

    /// La risposta di Open-Meteo: colonne parallele, non righe.
    private struct Payload: Decodable {
        struct Hourly: Decodable {
            var time: [Double]
            var temperature_2m: [Double?]?
            var weather_code: [Int?]?
            var wind_speed_10m: [Double?]?
            var wind_direction_10m: [Double?]?
            var wave_height: [Double?]?
            var wave_period: [Double?]?
            var sea_surface_temperature: [Double?]?
        }
        var hourly: Hourly?
    }

    private func decode(_ url: URL) async throws -> [MarineConditions] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let hourly = try JSONDecoder().decode(Payload.self, from: data).hourly else { return [] }

        let now = Date()
        return hourly.time.indices.map { index in
            func value(_ column: [Double?]?) -> Double? {
                index < (column?.count ?? 0) ? column?[index] ?? nil : nil
            }
            return MarineConditions(
                time: Date(timeIntervalSince1970: hourly.time[index]),
                fetchedAt: now,
                waveHeight: value(hourly.wave_height),
                wavePeriod: value(hourly.wave_period),
                seaTemperature: value(hourly.sea_surface_temperature),
                airTemperature: value(hourly.temperature_2m),
                windSpeed: value(hourly.wind_speed_10m),
                windDirection: value(hourly.wind_direction_10m),
                weatherCode: index < (hourly.weather_code?.count ?? 0)
                    ? hourly.weather_code?[index] ?? nil : nil)
        }
    }

    // MARK: Disco

    /// La chiave arrotonda a due decimali, ~1,1 km: i modelli hanno maglie da 2 a 20
    /// km, quindi due punti così vicini danno la stessa risposta e non vale la pena
    /// scaricarla due volte.
    private static func key(for coordinate: Coordinate) -> String {
        String(format: "%.2f_%.2f", coordinate.latitude, coordinate.longitude)
    }

    private func cached(for coordinate: Coordinate) -> Series? {
        let key = Self.key(for: coordinate)
        if let inMemory = series[key] { return inMemory }
        guard let url = directory?.appendingPathComponent("\(key).json"),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode(Series.self, from: data) else { return nil }
        series[key] = stored
        return stored
    }

    private func write(_ value: Series, key: String) {
        guard let url = directory?.appendingPathComponent("\(key).json") else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(value).write(to: url, options: .atomic)
    }
}
