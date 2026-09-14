import SwiftUI

/// Il riesame prima di confermare.
///
/// Questo passaggio **non si salta**, e non è una formalità. Qualunque cosa sia stata
/// letta — da regole o da un modello — è un'ipotesi su un documento, e un orario
/// sbagliato qui diventa una persona che resta a terra. Quindi: tutto sotto gli occhi,
/// i dubbi in cima, e la conferma chiusa finché resta qualcosa di irrisolto.
struct ImportReviewView: View {
    @State private var draft: ItineraryDraft
    private let sourceText: String
    private let onConfirm: (Voyage) -> Void

    /// Nullo quando l'ora di bordo la calcola l'app dagli scali, che è il caso
    /// normale. Valorizzato solo se chi è a bordo la impone.
    @State private var manualOffset: Int?
    @State private var editingPortFor: DraftCall.ID?
    @State private var showsSource = false

    init(draft: ItineraryDraft, sourceText: String, onConfirm: @escaping (Voyage) -> Void) {
        _draft = State(initialValue: draft)
        self.sourceText = sourceText
        self.onConfirm = onConfirm
        // Si parte dal fuso del telefono; quasi sempre va corretto, e la sezione
        // lo dice a chiare lettere.
        _manualOffset = State(initialValue: nil)
    }

    /// L'orologio di partenza. Se non è imposto a mano è solo un seme: `voyage`
    /// lo sostituisce con la scaletta ricavata dagli scali, coi cambi delle 02:00.
    private var clock: ShipClock {
        if let manualOffset {
            ShipClock(secondsFromGMT: manualOffset, source: .manual)
        } else {
            ShipClock(secondsFromGMT: TimeZone.current.secondsFromGMT(), source: .portTimeZone)
        }
    }
    private var voyage: Voyage? { draft.voyage(clock: clock) }

    private var blockingCount: Int { draft.calls.filter(\.isBlocked).count }
    private var assumedCount: Int {
        draft.calls.filter { $0.issues.contains(.allAboardAssumed) }.count
    }

    var body: some View {
        ZStack {
            Palette.seaBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    summary
                    shipSection
                    clockSection
                    ForEach($draft.calls) { $call in
                        DraftCallRow(call: $call, clock: clock) { editingPortFor = call.id }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 120)
            }
            .safeAreaInset(edge: .bottom) { confirmBar }
        }
        .navigationTitle("Controlla")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Originale") { showsSource = true }
                    .tint(Palette.action)
            }
        }
        .sheet(isPresented: $showsSource) {
            SourceTextSheet(text: sourceText)
        }
        .sheet(item: Binding(
            get: { editingPortFor.flatMap { id in draft.calls.first { $0.id == id } } },
            set: { _ in editingPortFor = nil })) { call in
            PortPickerSheet(initialQuery: call.rawName) { match in
                guard let index = draft.calls.firstIndex(where: { $0.id == call.id }) else { return }
                draft.calls[index].port = match
                draft.calls[index].issues.remove(.portUnknown)
                draft.calls[index].issues.remove(.portUncertain)
            }
        }
    }

    // MARK: Pezzi

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(draft.portCalls.count) scali · \(draft.calls.filter(\.isSeaDay).count) giorni di mare")
                    .font(Type.rowTitle)
                    .foregroundStyle(Palette.inkPrimary)
                Spacer(minLength: 8)
                Text(draft.source.label)
                    .font(Type.technical)
                    .foregroundStyle(Palette.inkTertiary)
            }

            if blockingCount > 0 {
                Label("\(blockingCount) righe da sistemare prima di confermare",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(Type.rowDetail)
                    .foregroundStyle(Palette.ashore)
            } else if assumedCount > 0 {
                // Non è un errore, ma è la cosa che va guardata: un all aboard dedotto
                // e sbagliato è esattamente il modo in cui si perde la nave.
                Label("\(assumedCount) orari di all aboard sono dedotti: confrontali col programma di bordo",
                      systemImage: "questionmark.circle.fill")
                    .font(Type.rowDetail)
                    .foregroundStyle(Palette.ashore)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label("Tutto agganciato", systemImage: "checkmark.circle.fill")
                    .font(Type.rowDetail)
                    .foregroundStyle(Palette.underway)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassSurface(cornerRadius: 22, prominence: .card)
        .padding(.top, 8)
    }

    private var shipSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nave").eyebrow()
            TextField("Nome della nave", text: Binding(
                get: { draft.shipName ?? "" },
                set: { draft.shipName = $0.isEmpty ? nil : $0 }))
                .font(Type.rowTitle)
                .foregroundStyle(Palette.inkPrimary)
                .textFieldStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassSurface(cornerRadius: 20, prominence: .chip)
    }

    private var clockSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ora di bordo").eyebrow()

            ShipClockControls(manualOffset: $manualOffset,
                              suggestedOffset: TimeZone.current.secondsFromGMT())

            Text(ShipClockControls.explanation(isManual: manualOffset != nil))
                .font(Type.rowDetail)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassSurface(cornerRadius: 20, prominence: .chip)
    }

    private var confirmBar: some View {
        VStack(spacing: 0) {
            Button {
                if let voyage { onConfirm(voyage) }
            } label: {
                Text(voyage == nil ? "Sistema le righe segnate" : "Conferma e salva")
                    .font(Type.rowTitle)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.glassProminent)
            .tint(voyage == nil ? Palette.inkTertiary : Palette.underway)
            .disabled(voyage == nil)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }
}

/// Una riga del riesame: modificabile sul posto, coi dubbi in evidenza.
private struct DraftCallRow: View {
    @Binding var call: DraftCall
    let clock: ShipClock
    let onEditPort: () -> Void

    private var tint: Color {
        if call.isBlocked { return Palette.adrift }
        if !call.issues.isEmpty { return Palette.ashore }
        return Palette.underway
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                dateColumn

                VStack(alignment: .leading, spacing: 3) {
                    Button(action: onEditPort) {
                        HStack(spacing: 6) {
                            Text(call.displayName)
                                .font(Type.rowTitle)
                                .foregroundStyle(Palette.inkPrimary)
                                .multilineTextAlignment(.leading)
                            if !call.isSeaDay {
                                Image(systemName: "pencil")
                                    .font(.caption2)
                                    .foregroundStyle(Palette.inkTertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(call.isSeaDay)

                    if !call.isSeaDay, call.port == nil, !call.rawName.isEmpty {
                        Text("nel documento: \(call.rawName)")
                            .font(Type.technical)
                            .foregroundStyle(Palette.inkTertiary)
                    }
                }
                Spacer(minLength: 0)
            }

            if !call.isSeaDay {
                times
            }

            if !call.issues.isEmpty {
                FlowRow(spacing: 6) {
                    ForEach(Array(call.issues).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { issue in
                        Text(issue.label)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(issue.isBlocking ? Palette.adrift : Palette.ashore)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill((issue.isBlocking ? Palette.adrift : Palette.ashore).opacity(0.16)))
                    }
                }
            }
        }
        .padding(14)
        .glassSurface(cornerRadius: 20, prominence: .chip, tint: call.issues.isEmpty ? nil : tint)
    }

    private var dateColumn: some View {
        VStack(spacing: 1) {
            Text(call.day.map(String.init) ?? "—")
                .font(.body.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.inkPrimary)
            Text(call.month.map { monthAbbreviation($0) } ?? "")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.inkTertiary)
        }
        .frame(width: 36)
    }

    private func monthAbbreviation(_ month: Int) -> String {
        let symbols = DateFormatter().shortMonthSymbols ?? []
        guard (1...12).contains(month), symbols.count == 12 else { return "" }
        return symbols[month - 1].uppercased()
    }

    /// Gli orari si correggono qui, senza aprire un'altra schermata: sono la cosa
    /// che più spesso va ritoccata, e un giro in più li farebbe saltare.
    private var times: some View {
        HStack(spacing: 8) {
            TimeField(label: String(localized: "Arrivo"), time: $call.arrival)
            TimeField(label: String(localized: "Partenza"), time: $call.departure)
            TimeField(label: String(localized: "All aboard"), time: $call.allAboard,
                      highlighted: call.issues.contains(.allAboardAssumed)) {
                call.issues.remove(.allAboardAssumed)
            }
        }
    }
}

/// Un orario modificabile, scritto a mano.
private struct TimeField: View {
    let label: String
    @Binding var time: TimeOfDay?
    var highlighted = false
    var onEdit: () -> Void = {}

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).eyebrow(highlighted ? Palette.ashore : Palette.inkTertiary)
            TextField("—", text: $text)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.inkPrimary)
                .keyboardType(.numbersAndPunctuation)
                .focused($isFocused)
                .onAppear { text = time?.formatted ?? "" }
                .onChange(of: isFocused) { _, focused in
                    guard !focused else { return }
                    let parsed = TimeOfDay(parsing: text)
                    if parsed != time { onEdit() }
                    time = parsed
                    text = parsed?.formatted ?? ""
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(highlighted ? Palette.ashore.opacity(0.14) : Color.white.opacity(0.05)))
    }
}

/// Ricerca di un porto nell'elenco, per correggere a mano quello che non si è agganciato.
private struct PortPickerSheet: View {
    let initialQuery: String
    let onPick: (PortMatch) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(PortGazetteer.shared.suggestions(for: query, limit: 30)) { match in
                Button {
                    onPick(match)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.name)
                        // Con due omonimi in elenco, il paese è l'unica cosa che li
                        // distingue: va mostrato sempre.
                        Text("\(match.subtitle) · \(Format.coordinate(match.coordinate))")
                            .font(.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Cerca un porto")
            .navigationTitle("Scegli il porto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }
            }
            .onAppear { query = initialQuery }
        }
    }
}

/// Il testo di partenza, per confrontare quando qualcosa non torna.
private struct SourceTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.callout.monospaced())
                    .foregroundStyle(Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .background(Palette.seaBackground.ignoresSafeArea())
            .navigationTitle("Testo originale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}
