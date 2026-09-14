import Foundation
import UIKit

/// Il livello di rete comune: un posto solo per timeout, user agent, cache e reti a
/// consumo.
///
/// Fino al 14 settembre 2026 c'erano tre client scritti a mano — `Commons`,
/// `ShipLookupService`, `MarineWeatherService` — ognuno col suo `URLRequest`, il suo
/// timeout e il suo modo di controllare la risposta. Tre copie della stessa cosa
/// divergono sempre: uno controllava lo stato HTTP, uno no; uno ignorava la cache,
/// gli altri la usavano senza dirlo. Qui c'è una regola sola, e chi la usa dice
/// soltanto **cosa** vuole.
///
/// Tutto quello che passa di qui è **facoltativo** per l'app: foto, meteo, ricerca di
/// una nave. Il cuore — countdown, carta, itinerario — non tocca mai la rete.
struct NetworkClient: Sendable {

    /// Che cosa non è andato. Poche categorie, quelle che cambiano cosa mostrare.
    enum Failure: Error, Equatable {
        /// Il server ha risposto, ma non con un successo.
        case status(Int)
        /// La risposta non era il JSON atteso.
        case malformed
    }

    /// Come trattare la rete a consumo per una richiesta.
    ///
    /// `frugal` è per le foto: su cellulare, hotspot o Risparmio dati il sistema
    /// rifiuta la richiesta da sé, senza che si debba indovinare da fuori. È la
    /// seconda rete di sicurezza dopo `PhotoDownloadPolicy`, che decide prima se
    /// provarci — e che tiene il porto "non ancora provato" quando non ci si prova.
    enum Cost: Sendable {
        /// Va bene su qualunque rete: è piccolo, o serve davvero.
        case any
        /// Solo su reti che non si pagano a peso.
        case frugal
    }

    let session: URLSession
    /// Chi siamo, per i servizi che lo chiedono. Wikimedia e Wikidata rifiutano le
    /// richieste anonime, e comunque è educazione.
    let userAgent: String
    /// Quanto aspettare. A bordo la rete è lenta ma c'è: dodici secondi bastano a
    /// distinguere «lenta» da «assente» senza tenere una schermata in attesa.
    let timeout: TimeInterval

    static let defaultAgent = "Cruisy/1.0 (app iOS personale)"

    init(session: URLSession = .shared, userAgent: String = NetworkClient.defaultAgent,
         timeout: TimeInterval = 12) {
        self.session = session
        self.userAgent = userAgent
        self.timeout = timeout
    }

    /// Il client dell'app, con la sessione condivisa e la sua cache su disco.
    static let shared = NetworkClient()

    // MARK: Richieste

    func request(_ url: URL, cost: Cost = .any,
                 cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: cachePolicy, timeoutInterval: timeout)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if cost == .frugal {
            request.allowsExpensiveNetworkAccess = PhotoDownloadPolicy.allowsMetered
            request.allowsConstrainedNetworkAccess = PhotoDownloadPolicy.allowsMetered
        }
        return request
    }

    /// I byte di una risorsa, se il server ha risposto bene.
    func data(_ url: URL, cost: Cost = .any,
              cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) async throws -> Data {
        let (data, response) = try await session.data(for: request(url, cost: cost, cachePolicy: cachePolicy))
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.status(http.statusCode)
        }
        return data
    }

    /// Un oggetto JSON. Le API di Wikimedia e Wikidata rispondono con dizionari
    /// dalla forma variabile, e un `Decodable` per ognuna sarebbe più fragile del
    /// dizionario stesso.
    func json(_ url: URL, cost: Cost = .any) async throws -> [String: Any] {
        let data = try await data(url, cost: cost)
        // Un corpo che non si legge è un caso solo, qualunque sia il motivo: una
        // pagina di manutenzione HTML e un JSON troncato si trattano allo stesso modo.
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Failure.malformed
        }
        return object
    }

    /// Un valore `Decodable`.
    func decode<T: Decodable>(_ type: T.Type, from url: URL, cost: Cost = .any,
                              cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
                              decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        let data = try await data(url, cost: cost, cachePolicy: cachePolicy)
        return try decoder.decode(type, from: data)
    }

    /// Un'immagine. Le foto sono la cosa più pesante che l'app scarica: sempre
    /// `frugal`, salvo che chi usa l'app abbia detto altrimenti nelle Impostazioni.
    func image(_ url: URL) async throws -> UIImage {
        let data = try await data(url, cost: .frugal)
        guard let image = UIImage(data: data) else { throw Failure.malformed }
        return image
    }
}
