import SwiftUI

/// Il riesame prima di confermare.
///
/// Questo passaggio **non si salta**, e non è una formalità. Qualunque cosa sia stata
/// letta — da regole o da un modello — è un'ipotesi su un documento, e un orario
/// sbagliato qui diventa una persona che resta a terra. Quindi: tutto sotto gli occhi,
/// i dubbi in cima, e la conferma chiusa finché resta qualcosa di irrisolto.
///
/// È un `Form` di sistema, non un documento di bordo: qui si correggono dati, e i
/// moduli di iOS lo fanno meglio di qualunque cosa disegnata da noi. Il biglietto
/// comincia dopo, quando la crociera è salvata.
struct ImportReviewView: View {
    @State private var draft: ItineraryDraft
    private let sourceText: String
    private let onConfirm: (Voyage) -> Void

    @Environment(\.livery) private var livery

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
        Form {
            Section {
                LabeledContent("Letto da", value: draft.source.label)
                LabeledContent("Scali", value: "\(draft.portCalls.count)")
                LabeledContent("Giorni di mare", value: "\(draft.calls.filter(\.isSeaDay).count)")
            } footer: {
                status
            }

            Section("Nave") {
                TextField("Nome della nave", text: Binding(
                    get: { draft.shipName ?? "" },
                    set: { draft.shipName = $0.isEmpty ? nil : $0 }))
                    .textInputAutocapitalization(.words)
            }

            Section {
                ShipClockControls(manualOffset: $manualOffset,
                                  suggestedOffset: TimeZone.current.secondsFromGMT())
            } header: {
                Text("Ora di bordo")
            } footer: {
                Text(ShipClockControls.explanation(isManual: manualOffset != nil))
            }

            ForEach($draft.calls) { $call in
                DraftCallSection(call: $call) { editingPortFor = call.id }
            }
        }
        .tint(livery.tint)
        .safeAreaInset(edge: .bottom) { confirmBar }
        .navigationTitle("Controlla")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Originale") { showsSource = true }
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

    /// Lo stato del riesame, in fondo alla prima sezione: quello che va guardato
    /// prima di confermare.
    @ViewBuilder
    private var status: some View {
        if blockingCount > 0 {
            Label("\(blockingCount) righe da sistemare prima di confermare",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if assumedCount > 0 {
            // Non è un errore, ma è la cosa che va guardata: un all aboard dedotto
            // e sbagliato è esattamente il modo in cui si perde la nave.
            Label("\(assumedCount) orari di all aboard sono dedotti: confrontali col programma di bordo",
                  systemImage: "questionmark.circle.fill")
                .foregroundStyle(.orange)
        } else {
            Label("Tutto agganciato", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    private var confirmBar: some View {
        Button {
            if let voyage { onConfirm(voyage) }
        } label: {
            Text(voyage == nil ? "Sistema le righe segnate" : "Conferma e salva")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(livery.tint)
        .disabled(voyage == nil)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

/// Una sezione del riesame: un giorno, coi suoi orari e i suoi dubbi.
///
/// Gli orari si correggono qui, senza aprire un'altra schermata: sono la cosa che più
/// spesso va ritoccata, e un giro in più li farebbe saltare.
private struct DraftCallSection: View {
    @Binding var call: DraftCall
    let onEditPort: () -> Void

    var body: some View {
        Section {
            if !call.isSeaDay {
                TimeRow(label: String(localized: "Arrivo"), identifier: "orario-arrivo",
                        time: $call.arrival)
                TimeRow(label: String(localized: "Partenza"), identifier: "orario-partenza",
                        time: $call.departure)
                TimeRow(label: String(localized: "All aboard"), identifier: "orario-allaboard",
                        time: $call.allAboard,
                        highlighted: call.issues.contains(.allAboardAssumed)) {
                    call.issues.remove(.allAboardAssumed)
                }
            }
        } header: {
            header
        } footer: {
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(date)
                .monospacedDigit()
            if call.isSeaDay {
                Text(call.displayName)
            } else {
                Button(action: onEditPort) {
                    HStack(spacing: 4) {
                        Text(call.displayName)
                        Image(systemName: "pencil").font(.caption2)
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .textCase(nil)
        .font(TicketType.rowTitle)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !call.isSeaDay, call.port == nil, !call.rawName.isEmpty {
                Text("nel documento: \(call.rawName)")
            }
            ForEach(Array(call.issues).sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { issue in
                Label(issue.label, systemImage: issue.isBlocking
                      ? "exclamationmark.triangle.fill" : "questionmark.circle.fill")
                    .foregroundStyle(issue.isBlocking ? .red : .orange)
            }
        }
    }

    private var date: String {
        let day = call.day.map(String.init) ?? "—"
        guard let month = call.month, (1...12).contains(month),
              let symbols = DateFormatter().shortMonthSymbols, symbols.count == 12 else { return day }
        return "\(day) \(symbols[month - 1].uppercased())"
    }
}

/// Un orario modificabile, scritto a mano, come riga di un modulo.
private struct TimeRow: View {
    let label: String
    /// Stabile e non tradotto: i test di interfaccia cercano gli orari con questo,
    /// perché l'etichetta cambia con la lingua.
    let identifier: String
    @Binding var time: TimeOfDay?
    var highlighted = false
    var onEdit: () -> Void = {}

    @State private var text: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        LabeledContent {
            TextField("—", text: $text)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier(identifier)
                .focused($isFocused)
                .onAppear { text = time?.formatted ?? "" }
                .onChange(of: isFocused) { _, focused in
                    guard !focused else { return }
                    let parsed = TimeOfDay(parsing: text)
                    if parsed != time { onEdit() }
                    time = parsed
                    text = parsed?.formatted ?? ""
                }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                // Un all aboard dedotto si segna: è l'orario che vale la pena
                // confrontare col programma di bordo.
                if highlighted {
                    Image(systemName: "questionmark.circle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("dedotto")
                }
            }
        }
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
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(16)
            }
            .navigationTitle("Testo originale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}
