import Foundation
import Observation
import UIKit

/// Scarica la foto della nave da Wikimedia Commons.
///
/// Il nome del file arriva da `ships.bin`, che a sua volta lo prende da Wikidata: per
/// una nave esiste un'immagine dichiarata, quindi non c'è niente da indovinare. Per i
/// porti la strada è un'altra — vedi `PortPhotoService`.
///
/// È una delle cose che fanno uscire l'app in rete, insieme al satellite, al meteo e
/// alle foto dei porti — tutte facoltative, tutte che degradano senza.
///
/// **Legata al thread principale**, e non per abitudine. Il 14 settembre 2026 la
/// schermata dei porti faceva crashare l'app: ogni riga lanciava il proprio `load`, i
/// `load` giravano in parallelo fuori dal thread principale, e tutti modificavano lo
/// stesso insieme `attempted` nello stesso momento. L'insieme si corrompeva e l'app
/// moriva dentro `Set.contains`. Il progetto compila in modalità Swift 5 senza controlli
/// di concorrenza, quindi il compilatore non l'aveva segnalato. Con `@MainActor` lo
/// stato si tocca da un solo posto alla volta; le attese di rete restano fuori dal
/// thread principale, perché le funzioni di `Commons` non sono legate a nessun attore.
@MainActor
@Observable
final class ShipPhotoService {

    private(set) var photo: CommonsPhoto?
    private(set) var isLoading = false
    /// L'ultima nave per cui si è provato: evita di riscaricare a ogni ridisegno.
    private var attempted: String?

    private let cache = Commons.cacheDirectory("Navi")

    /// - Parameter allowsDownload: falso su rete a consumo senza permesso; vedi
    ///   `PhotoDownloadPolicy`.
    func load(_ ship: ShipRecord, allowsDownload: Bool = true) async {
        guard !ship.imageFile.isEmpty, attempted != ship.imageFile else { return }
        photo = nil

        if let cached = await Commons.readCache(cache, key: ship.imageFile) {
            attempted = ship.imageFile
            photo = cached
            return
        }
        guard allowsDownload else { return }
        attempted = ship.imageFile

        isLoading = true
        defer { isLoading = false }

        async let image = Commons.downloadImage(file: ship.imageFile)
        async let credit = Commons.credit(for: ship.imageFile)

        guard let image = await image else { return }
        let (author, licence) = await credit
        // Senza credito non si mostra: è la condizione della licenza, non una
        // gentilezza. Meglio nessuna foto che una foto senza il suo autore.
        guard !author.isEmpty || !licence.isEmpty else { return }

        let result = CommonsPhoto(image: image, author: author, licence: licence)
        photo = result
        await Commons.writeCache(result, to: cache, key: ship.imageFile)
    }
}
