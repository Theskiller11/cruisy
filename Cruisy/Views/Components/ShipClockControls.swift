import SwiftUI

/// «Segui i porti» oppure uno scarto fisso: la scelta dell'ora di bordo.
///
/// Esiste in due posti — la revisione di un itinerario importato e l'editor della
/// crociera — e deve comportarsi **allo stesso modo** in entrambi. Fino al 14 settembre
/// 2026 non era così: l'importazione aveva l'interruttore, l'editor solo il selettore
/// dello scarto, che metteva l'orologio in manuale senza più modo di tornare
/// all'automatico. E la nota sotto l'editor diceva ancora «tutti gli orari sono in ora
/// di bordo», mentre gli scali ormai si scrivono in ora del porto.
///
/// Qui ci sono solo i controlli e il testo: il contenitore — una sezione di un `Form`
/// o una card — lo decide chi li usa.
struct ShipClockControls: View {
    /// Nullo quando l'orologio segue i porti. Valorizzato quando è fisso.
    @Binding var manualOffset: Int?

    /// Lo scarto da proporre quando si passa al manuale: quello che l'orologio ha già,
    /// così l'ora sullo schermo non salta nel momento in cui si tocca l'interruttore.
    var suggestedOffset: Int

    static let offsets: [Int] = stride(from: -11, through: 13, by: 1).map { $0 * 3600 }

    var body: some View {
        Toggle("Segui i porti", isOn: Binding(
            get: { manualOffset == nil },
            set: { manualOffset = $0 ? nil : suggestedOffset }))
            .tint(Palette.underway)

        if let offset = manualOffset {
            Picker("Scarto da UTC", selection: Binding(
                get: { offset }, set: { manualOffset = $0 })) {
                ForEach(Self.offsets, id: \.self) { seconds in
                    Text(ShipClock.offsetLabel(secondsFromGMT: seconds)).tag(seconds)
                }
            }
            .pickerStyle(.menu)
            .tint(Palette.action)
        }
    }

    /// La spiegazione sotto i controlli, che cambia con la scelta.
    static func explanation(isManual: Bool) -> String {
        isManual
            ? String(localized: "L'orologio resta fermo su questo scarto per tutta la crociera. Usalo solo se a bordo hanno annunciato un'ora diversa.")
            : String(localized: "Gli orari degli scali sono ora locale di ogni porto. L'app sposta l'orologio alle 02:00 della notte che apre l'ultimo giorno di mare, come fanno le compagnie.")
    }
}

extension ShipClock {
    /// Lo scarto fisso, se l'orologio è stato impostato a mano; nullo se segue i porti.
    var manualOffset: Int? {
        changes.contains(where: { $0.source == .manual }) ? changes[0].secondsFromGMT : nil
    }
}
