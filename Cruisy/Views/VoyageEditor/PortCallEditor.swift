import SwiftUI

/// Correzione degli orari di uno scalo.
///
/// I selettori girano **nell'ora di questo porto**, non in quella del telefono: si
/// passa `\.timeZone` nell'ambiente, così ciò che si digita è ciò che c'è scritto
/// sull'itinerario. Senza questo, in un porto disallineato ogni orario inserito
/// nascerebbe sbagliato di qualche ora, e sarebbe un errore invisibile.
///
/// Il porto e non la nave perché è il porto a stampare gli orari — e comunque in
/// banchina i due orologi coincidono: la nave si allinea al porto prima di arrivare.
struct PortCallEditor: View {
    @State private var draft: PortCall
    private let clock: ShipClock
    private let onSave: (PortCall) -> Void
    @Environment(\.dismiss) private var dismiss

    init(call: PortCall, clock: ShipClock, onSave: @escaping (PortCall) -> Void) {
        _draft = State(initialValue: call)
        self.clock = clock
        self.onSave = onSave
    }

    /// L'all aboard deve stare fra l'attracco e la partenza, altrimenti il countdown
    /// misurerebbe un intervallo impossibile.
    private var isCoherent: Bool {
        guard let allAboard = draft.allAboard else { return true }
        guard allAboard >= draft.arrival else { return false }
        if let departure = draft.departure { return allAboard <= departure && departure >= draft.arrival }
        return true
    }

    /// Il fuso in cui si leggono e si scrivono gli orari di questo scalo.
    private var zone: TimeZone {
        draft.timeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? clock.timeZone(at: draft.arrival)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nome", text: $draft.name)
                    TextField("Paese o regione", text: $draft.region)
                }

                Section {
                    DatePicker("Attracco", selection: $draft.arrival)
                    DatePicker("All aboard", selection: Binding(
                        get: { draft.allAboard ?? draft.arrival },
                        set: { draft.allAboard = $0 }))
                    DatePicker("Partenza", selection: Binding(
                        get: { draft.departure ?? draft.arrival },
                        set: { draft.departure = $0 }))
                } header: {
                    Text("Orari in ora di \(draft.name) · \(ShipClock.offsetLabel(secondsFromGMT: zone.secondsFromGMT(for: draft.arrival)))")
                } footer: {
                    if !isCoherent {
                        Text("L'all aboard deve cadere fra l'attracco e la partenza.")
                            .foregroundStyle(.red)
                    } else {
                        Text("Quello che salvi qui vince sugli orari pubblicati.")
                    }
                }

                Section("Come si scende") {
                    Picker("Attracco", selection: $draft.berth.kind) {
                        Text("Ormeggio").tag(Berth.Kind.dock)
                        Text("Tender").tag(Berth.Kind.tender)
                    }
                    .pickerStyle(.segmented)

                    TextField("Molo o pontile (facoltativo)", text: Binding(
                        get: { draft.berth.name ?? "" },
                        set: { draft.berth.name = $0.isEmpty ? nil : $0 }))
                }
            }
            // Il punto di tutta la schermata.
            .environment(\.timeZone, zone)
            .navigationTitle(draft.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(!isCoherent)
                }
            }
        }
    }
}
