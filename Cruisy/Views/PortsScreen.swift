import SwiftUI

/// Tutti i porti toccati, in dettaglio, con le loro fotografie.
///
/// Esiste perché il riquadro nel diario non può contenerli tutti: dopo qualche
/// crociera diventa un muro di pastiglie in cui non si trova più niente. Lì restano
/// **solo i porti visitati tre volte o più** — quelli che raccontano qualcosa di chi
/// li ha toccati — e da lì si arriva qui, dove ci sono tutti.
struct PortsScreen: View {
    let stamps: [Logbook.Stamp]

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
            Palette.seaBackground.ignoresSafeArea()
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
                .padding(.bottom, 96)
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

/// Un porto nel dettaglio: la foto, quante volte ci sei stato, quando la prima.
private struct PortCard: View {
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
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Palette.abyss.opacity(0.7)))
                            .padding(6)
                    }
                    .clipped()
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(stamp.port.name)
                        .font(Type.rowTitle)
                        .foregroundStyle(Palette.inkPrimary)
                    Spacer(minLength: 0)
                    if stamp.visits > 1 {
                        Text("×\(stamp.visits)")
                            .font(Type.metricLabel.weight(.semibold))
                            .foregroundStyle(Palette.underway)
                    }
                }
                Text(subtitle)
                    .font(Type.rowDetail)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 22, prominence: .card)
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
