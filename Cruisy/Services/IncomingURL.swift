import Foundation

/// Che cosa vuol dire un indirizzo con cui si apre l'app.
///
/// Ne arrivano di due specie, e prima si confondevano. Widget e Live Activity
/// aprono l'app con `cruisy://today`; un file `.cruisy` condiviso per AirDrop,
/// messaggio o email arriva come indirizzo di file. `onOpenURL` li riceve tutti e
/// due, e li trattava tutti come file: toccando la Dynamic Island espansa o la
/// scheda sulla schermata di blocco compariva «Non riesco ad aprirlo», perché
/// `cruisy://today` non è una crociera da leggere.
enum IncomingURL: Equatable {
    /// Una destinazione dentro l'app: per ora c'è solo Oggi.
    case today
    /// Una crociera condivisa, da leggere e far confermare.
    case voyageFile(URL)
    /// Un indirizzo che non è per noi: si ignora, senza avvisi.
    case unknown

    static let scheme = "cruisy"

    init(_ url: URL) {
        if url.scheme?.lowercased() == Self.scheme {
            // `cruisy://today` e, per tolleranza, qualunque altra destinazione nostra
            // che non conosciamo ancora: si apre l'app su Oggi, che è la cosa giusta
            // da mostrare a chi ha toccato un countdown.
            self = .today
        } else if url.isFileURL {
            self = .voyageFile(url)
        } else {
            self = .unknown
        }
    }
}
