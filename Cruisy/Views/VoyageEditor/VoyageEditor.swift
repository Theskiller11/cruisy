import SwiftUI

/// Composizione della crociera: la nave, l'ora di bordo, gli scali.
///
/// Tutto inserito a mano da chi usa l'app. Nessun catalogo di itinerari preconfezionati:
/// gli orari e i piani di una compagnia sono roba sua, e un'app che li ridistribuisce
/// si mette in un guaio che non le serve. I porti restano fatti geografici.
struct VoyageEditor: View {
    @State private var draft: Voyage
    @State private var editingCall: PortCall?
    @FocusState private var nameFocused: Bool
    @Environment(ShipLookupService.self) private var lookup
    private let onSave: (Voyage) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.livery) private var livery

    init(voyage: Voyage?, onSave: @escaping (Voyage) -> Void) {
        _draft = State(initialValue: voyage ?? Self.blank())
        self.onSave = onSave
    }

    /// Una crociera vuota parte da domani mattina: è la data che quasi sempre serve
    /// correggere di poco invece che comporre da zero.
    private static func blank() -> Voyage {
        let tomorrow = Calendar.current.startOfDay(for: Date().addingTimeInterval(86_400))
        return Voyage(shipName: "", clock: ShipClock(secondsFromGMT: TimeZone.current.secondsFromGMT()),
                      calls: [
                        PortCall(name: "", region: "", coordinate: Coordinate(latitude: 0, longitude: 0),
                                 role: .embarkation,
                                 arrival: tomorrow.addingTimeInterval(14 * 3600),
                                 departure: tomorrow.addingTimeInterval(20 * 3600),
                                 allAboard: tomorrow.addingTimeInterval(19 * 3600))
                      ])
    }

    /// La nave riconosciuta dal nome scritto finora, se c'è.
    private var match: ShipRecord? { ShipDirectory.shared.lookup(draft.shipName) }

    /// I nomi da proporre mentre si scrive. Spariscono appena il nome corrisponde
    /// già a una nave: continuare a proporre quello che hai appena scelto è rumore.
    private var suggestions: [ShipRecord] {
        guard nameFocused, draft.shipName.count >= 2 else { return [] }
        let hits = ShipDirectory.shared.suggestions(for: draft.shipName, limit: 5)
        if hits.count == 1, hits[0] == match { return [] }
        return hits
    }

    /// Riempie i campi dalla nave scelta. Il nome prende la grafia dell'elenco:
    /// se hai scritto "explora 1" ti ritrovi "Explora I", che è come si chiama.
    private func adopt(_ record: ShipRecord) {
        draft.shipName = record.name
        if !record.imo.isEmpty { draft.imo = record.imo }
        if !record.mmsi.isEmpty { draft.mmsi = record.mmsi }
        nameFocused = false
    }

    @ViewBuilder
    private var lookupRow: some View {
        switch lookup.outcome {
        case .searching:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Cerco su Wikidata…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        case .notFound:
            Text("Su Wikidata non c'è nessuna nave con questo nome.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .failed:
            Button("Riprova la ricerca su Wikidata") {
                Task { await lookup.search(draft.shipName) }
            }
            .foregroundStyle(livery.tint)
        default:
            Button {
                Task {
                    await lookup.search(draft.shipName)
                    if case .found(let record) = lookup.outcome { adopt(record) }
                }
            } label: {
                Label("Cerca «\(draft.shipName)» su Wikidata", systemImage: "magnifyingglass")
            }
            .foregroundStyle(livery.tint)
        }
    }

    private func recognised(_ record: ShipRecord) -> String {
        var parts: [String] = [record.name]
        if !record.operatorName.isEmpty { parts.append(record.operatorName) }
        if record.year > 0 { parts.append(String(record.year)) }
        return parts.joined(separator: " · ")
    }

    /// Scarti da UTC che le navi usano davvero: ore intere, più le mezz'ore in uso
    /// in alcune zone.
    private var canSave: Bool {
        !draft.shipName.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.calls.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            && draft.calls.count >= 2
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome della nave", text: $draft.shipName)
                        .focused($nameFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)

                    ForEach(suggestions) { record in
                        Button { adopt(record) } label: { SuggestionRow(record: record) }
                            .buttonStyle(.plain)
                    }

                    // Nome scritto per intero e nessuna corrispondenza: la nave può
                    // essere più recente dell'elenco impacchettato. Si può andare a
                    // chiederla, ma è una scelta di chi scrive, non un automatismo.
                    if match == nil, draft.shipName.count >= 3, suggestions.isEmpty {
                        lookupRow
                    }

                    TextField("MMSI (facoltativo)", text: Binding(
                        get: { draft.mmsi ?? "" },
                        set: { draft.mmsi = $0.isEmpty ? nil : $0 }))
                        .keyboardType(.numberPad)
                    TextField("IMO (facoltativo)", text: Binding(
                        get: { draft.imo ?? "" },
                        set: { draft.imo = $0.isEmpty ? nil : $0 }))
                        .keyboardType(.numberPad)
                } header: {
                    Text("Nave")
                } footer: {
                    if let match {
                        Label(recognised(match), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(livery.tint)
                    } else {
                        Text("Scrivi il nome: se la nave è nell'elenco, identificativi e misure si compilano da soli.")
                    }
                }

                Section {
                    ShipClockControls(
                        manualOffset: Binding(
                            get: { draft.clock.manualOffset },
                            set: { offset in
                                // Tornando all'automatico la scaletta si rifà subito,
                                // non al salvataggio: gli orari degli scali qui sotto
                                // si leggono con questo orologio.
                                draft.clock = offset.map { ShipClock(secondsFromGMT: $0, source: .manual) }
                                    ?? draft.scheduledClock
                            }),
                        suggestedOffset: draft.clock.secondsFromGMT(at: draft.calls.first?.arrival ?? .now))
                } header: {
                    Text("Ora di bordo")
                } footer: {
                    Text(ShipClockControls.explanation(isManual: draft.clock.manualOffset != nil))
                }

                Section("Scali") {
                    ForEach(draft.calls) { call in
                        Button {
                            editingCall = call
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(call.name.isEmpty ? String(localized: "Senza nome") : call.name)
                                        .foregroundStyle(.primary)
                                    Text(Format.window(from: call.arrival, to: call.departure, clock: draft.clock))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        draft.calls.remove(atOffsets: indexSet)
                    }

                    Button("Aggiungi scalo", systemImage: "plus") { addCall() }
                }
            }
            .tint(livery.tint)
            .environment(\.timeZone, draft.clock.timeZone(at: draft.calls.first?.arrival ?? .now))
            .navigationTitle(draft.shipName.isEmpty ? String(localized: "Nuova crociera") : draft.shipName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        onSave(normalised())
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
            .sheet(item: $editingCall) { call in
                PortCallEditor(call: call, clock: draft.clock) { amended in
                    if let index = draft.calls.firstIndex(where: { $0.id == amended.id }) {
                        draft.calls[index] = amended
                    }
                }
            }
        }
    }

    /// Il nuovo scalo nasce il giorno dopo l'ultimo, con orari plausibili: quasi
    /// sempre servirà solo ritoccarli.
    private func addCall() {
        let previous = draft.calls.last
        let base = (previous?.castOff ?? Date()).addingTimeInterval(13 * 3600)
        draft.calls.append(PortCall(
            name: "", region: "",
            coordinate: previous?.coordinate ?? Coordinate(latitude: 0, longitude: 0),
            arrival: base,
            departure: base.addingTimeInterval(9 * 3600),
            allAboard: base.addingTimeInterval(8.5 * 3600)))
    }

    /// Rimette in ordine e riassegna i ruoli: primo scalo imbarco, ultimo sbarco.
    /// Così l'utente può inserire gli scali in qualunque ordine senza rompere nulla.
    private func normalised() -> Voyage {
        var voyage = draft
        voyage.calls.sort { $0.arrival < $1.arrival }
        for index in voyage.calls.indices {
            voyage.calls[index].role = index == 0 ? .embarkation
                : index == voyage.calls.count - 1 ? .disembarkation : .port
        }
        // Allo sbarco non c'è né partenza né rientro obbligatorio.
        if var last = voyage.calls.last {
            last.departure = nil
            last.allAboard = nil
            voyage.calls[voyage.calls.count - 1] = last
        }
        return voyage
    }
}

/// Una riga d'elenco: il nome, e sotto quel tanto che basta a distinguere due navi
/// omonime — la compagnia e l'anno.
private struct SuggestionRow: View {
    @Environment(\.livery) private var livery
    let record: ShipRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "ferry.fill")
                .font(.footnote)
                .foregroundStyle(livery.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.name)
                    .foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        [record.operatorName, record.year > 0 ? String(record.year) : ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}
