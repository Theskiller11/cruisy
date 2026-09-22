import SwiftUI

/// Tutti i porti toccati, in dettaglio, con le loro fotografie.
///
/// Esiste perché la pagina dei timbri nel diario non può contenerli tutti: dopo
/// qualche crociera diventa un muro in cui non si trova più niente. Lì restano
/// **solo i porti visitati tre volte o più** — quelli che raccontano qualcosa di chi
/// li ha toccati — e da lì si arriva qui, dove ci sono tutti.
struct PortsScreen: View {
    let stamps: [Logbook.Stamp]

    @Environment(\.livery) private var livery
    @State private var photos = PortPhotoService()
    @Environment(Reachability.self) private var reachability
    @State private var query = ""

    private var shown: [Logbook.Stamp] {
        guard !query.isEmpty else { return stamps }
        let needle = ShipDirectory.fold(query)
        return stamps.filter { ShipDirectory.fold($0.port.name).contains(needle) }
    }

    var body: some View {
        ZStack {
            livery.hull.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(shown) { stamp in
                        PortCard(stamp: stamp, photo: photos.photo(for: call(stamp)))
                            // Ogni card chiede la propria foto quando compare, non
                            // tutte all'apertura: con quaranta porti sarebbero
                            // quaranta richieste insieme, e `LazyVStack` è fatto
                            // apposta perché non succeda.
                            .task(id: reachability.isExpensive) {
                                await photos.load(call(stamp), allowsDownload:
                                    PhotoDownloadPolicy.allows(isMetered: reachability.isExpensive))
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Porti toccati")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: Text("Cerca un porto"))
    }

    /// Uno scalo finto per chiedere la foto: al servizio servono solo nome e
    /// coordinate, e il diario tiene esattamente quelli.
    private func call(_ stamp: Logbook.Stamp) -> PortCall {
        PortCall(name: stamp.port.name, region: stamp.port.region,
                 coordinate: stamp.port.coordinate, arrival: stamp.port.arrival)
    }
}

/// Un porto nel dettaglio: la foto, il timbro, quando la prima volta.
private struct PortCard: View {
    @Environment(\.livery) private var livery
    let stamp: Logbook.Stamp
    var photo: CommonsPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let photo {
                // Nell'`overlay` e non figlia diretta: un'immagine `.fill` come figlia
                // detta la larghezza alla colonna e taglia i nomi lunghi.
                Color.clear
                    .frame(height: 160)
                    .overlay {
                        Image(uiImage: photo.image).resizable().aspectRatio(contentMode: .fill)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Text(photo.credit)
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.6)))
                            .padding(6)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(6)
            }

            // Ai corpi accessibili il timbro scende sotto: accanto al nome rubava
            // tanta larghezza che «Puerto Plata» si spezzava una lettera per riga.
            AdaptiveHStack(verticalAlignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(stamp.port.name)
                        .font(TicketType.place)
                        .tracking(0.4)
                        .textCase(.uppercase)
                        .foregroundStyle(livery.ink)
                    Text(subtitle)
                        .font(TicketType.rowDetail)
                        .foregroundStyle(livery.field)
                }
                AdaptiveSpacer(minLength: 8)
                // Senza `diameter` il timbro si allarga finché il testo ci sta intero:
                // sotto il nome c'è tutta la larghezza, e «TOC-CATO» spezzato era peggio
                // di un timbro grande.
                Stamp(stamp.visits > 1 ? String(localized: "×\(stamp.visits)\nvolte") : String(localized: "Toccato"),
                      color: stamp.visits >= 3 ? livery.signal : livery.field, rotation: -9)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .paperCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(stamp.visits > 1
            ? Text("\(stamp.port.name), \(stamp.visits) volte")
            : Text(stamp.port.name))
    }

    private var subtitle: String {
        var parts: [String] = []
        if !stamp.port.region.isEmpty { parts.append(stamp.port.region) }
        parts.append(Format.coordinate(stamp.port.coordinate))
        return parts.joined(separator: " · ")
    }
}
