import SwiftUI

/// La sequenza di benvenuto, una volta sola.
///
/// Quattro passi e nessun modulo da compilare: non c'è niente da registrare, quindi
/// non c'è niente da chiedere. I permessi — posizione e notifiche — **non** si
/// chiedono qui: si chiedono quando servono davvero, perché un permesso chiesto
/// mentre si guarda la carta ha una ragione evidente, e uno chiesto al primo avvio no.
struct OnboardingFlow: View {
    let onFinish: () -> Void

    @Environment(VoyageStore.self) private var store
    @Environment(Preferences.self) private var preferences
    @Environment(\.dismiss) private var dismiss
    @Environment(\.livery) private var livery

    @State private var step = {
        #if DEBUG
        // `-onboardingStep 2` apre direttamente un passo, per poterlo verificare
        // dal simulatore senza toccare lo schermo.
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-onboardingStep"),
           arguments.index(after: flag) < arguments.endIndex,
           let value = Int(arguments[arguments.index(after: flag)]) {
            return min(max(value, 0), 3)
        }
        #endif
        return 0
    }()
    @State private var isImporting = false

    private let lastStep = 4

    var body: some View {
        VStack(spacing: 0) {
            progress
                .padding(.top, 20)
                .padding(.horizontal, 24)

            ScrollView {
                content
                    .padding(.horizontal, 26)
                    .padding(.top, 28)
                    .padding(.bottom, 20)
            }

            actions
                .padding(.horizontal, 26)
                .padding(.bottom, 16)
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $isImporting) {
            ItineraryImportView { voyage in
                store.replace(with: voyage)
                finish()
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0...lastStep, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? livery.tint : Color(.tertiaryLabel))
                    .frame(height: 3)
            }
        }
        .fluid(Motion.settle, value: step)
        .accessibilityElement()
        .accessibilityLabel(Text("Passo \(step + 1) di \(lastStep + 1)"))
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0: welcome
        case 1: howItWorks
        case 2: iCloudStep
        case 3: liveActivityStep
        default: itineraryStep
        }
    }

    // MARK: I cinque passi

    private var welcome: some View {
        OnboardingPage(
            glyph: "location.north.circle.fill", tint: .green,
            title: String(localized: "Cruisy"),
            subtitle: String(localized: "Quanto manca. Nient'altro."),
            text: String(localized: "In giorno di porto conta al rientro obbligatorio a bordo. In giorno di mare, all'arrivo nel prossimo scalo. È tutto quello che fa, e lo fa bene."))
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Tre cose da sapere")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)

            OnboardingPoint(glyph: "megaphone.fill", tint: .orange,
                            title: String(localized: "Gli annunci di bordo fanno fede"),
                            text: String(localized: "Cruisy conta dagli orari che le hai dato. Se a bordo ne annunciano altri, quelli vincono: correggili dal dettaglio del porto."))

            OnboardingPoint(glyph: "wifi.slash", tint: .green,
                            title: String(localized: "Funziona senza rete"),
                            text: String(localized: "Countdown e carta si calcolano sul telefono. In mezzo all'oceano, in modalità aereo, continuano a funzionare."))

            OnboardingPoint(glyph: "clock.badge.exclamationmark.fill", tint: livery.tint,
                            title: String(localized: "Tutti gli orari sono in ora di bordo"),
                            text: String(localized: "Le navi tengono la propria ora e non sempre la cambiano in porto. Se il tuo telefono non è allineato, Cruisy te lo dice."))
        }
    }

    private var iCloudStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingPage(
                glyph: "square.and.arrow.up.on.square.fill", tint: livery.tint,
                title: String(localized: "Portala con te"),
                subtitle: String(localized: "Senza creare nessun account."),
                text: String(localized: "Puoi salvare la crociera come file e mandarla a chi viaggia con te, o al tuo iPad. Chi la riceve la apre e ce l'ha: nessun account, nessuna password, nessun nostro server."),
                alignment: .leading)

            // Il punto che vale la pena dire, perché è controintuitivo: in crociera
            // questa strada funziona **meglio** della sincronizzazione automatica.
            OnboardingPoint(glyph: "wifi.slash", tint: .green,
                            title: String(localized: "Funziona anche in mezzo al mare"),
                            text: String(localized: "AirDrop fra due telefoni sullo stesso ponte non ha bisogno di rete. Una sincronizzazione automatica, in mezzo all'oceano, non sincronizzerebbe niente."))

            Text("Trovi «Condividi la crociera» nelle Impostazioni, dal menu dell'Itinerario.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Il countdown sulla schermata di blocco, chiesto qui e non a bordo.
    ///
    /// Si chiede adesso perché a bordo, tre ore dall'all aboard, non è il momento
    /// di scoprire un'impostazione: è il momento di vedere il numero. E si chiede
    /// come **preferenza**, non come interruttore: qui una crociera non c'è ancora
    /// e non ci sarebbe niente da accendere. L'app se la ricorda.
    private var liveActivityStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            OnboardingPage(
                glyph: "clock.badge.checkmark", tint: .orange,
                title: String(localized: "Prima di salpare"),
                subtitle: String(localized: "Il countdown sulla schermata di blocco."),
                text: String(localized: "Nelle ore che contano, Cruisy può tenere il tempo che manca sulla schermata di blocco e nella Dynamic Island: lo guardi senza aprire nulla, anche con le mani occupate."),
                alignment: .leading)

            Toggle(isOn: Binding(
                get: { preferences.wantsLiveActivity },
                set: { preferences.wantsLiveActivity = $0 })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mostralo quando serve")
                            .font(TicketType.rowTitle)
                            .foregroundStyle(.primary)
                        // La rassicurazione va detta qui, non nascosta in un aiuto:
                        // chi accetta qualcosa nell'onboarding vuole sapere di poter
                        // tornare indietro.
                        Text("Puoi disattivarlo quando vuoi dalle Impostazioni.")
                            .font(TicketType.rowDetail)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(livery.tint)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(Color(.secondarySystemGroupedBackground),
                            in: .rect(cornerRadius: 20, style: .continuous))

            Text("Si accende in porto nelle ultime otto ore prima dell'all aboard, e in mare nell'ultima ora e mezza prima dell'attracco. Fuori da quelle finestre non ci sarebbe niente da contare.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var itineraryStep: some View {
        OnboardingPage(
            glyph: "text.viewfinder", tint: .green,
            title: String(localized: "Aggiungi la tua crociera"),
            subtitle: String(localized: "Incolla, fotografa o importa."),
            text: String(localized: "L'email della compagnia, la pagina del sito, una foto del programma di bordo: Cruisy ne ricava l'itinerario e ti fa controllare tutto prima di salvarlo."))
    }

    // MARK: Comandi

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if step == lastStep { isImporting = true } else { advance() }
            } label: {
                Text(step == lastStep ? "Aggiungi l'itinerario" : "Avanti")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(livery.tint)

            if step == lastStep {
                Button("Lo faccio più tardi") { finish() }
                    .tint(livery.tint)
            } else if step > 0 {
                Button("Indietro") { withAnimation(Motion.settle) { step -= 1 } }
                    .tint(livery.tint)
            }
        }
    }

    private func advance() {
        withAnimation(Motion.settle) { step = min(step + 1, lastStep) }
    }

    private func finish() {
        onFinish()
        dismiss()
    }
}

/// Una schermata dell'onboarding: glifo, titolo, sottotitolo, testo.
private struct OnboardingPage: View {
    let glyph: String
    let tint: Color
    let title: String
    let subtitle: String
    let text: String
    var alignment: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alignment, spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.bottom, 6)

            Text(title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.title3.weight(.medium))
                .foregroundStyle(tint)
            Text(text)
                .font(TicketType.rowDetail)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        .accessibilityElement(children: .combine)
    }
}

/// Un punto elencato, con glifo a sinistra.
private struct OnboardingPoint: View {
    let glyph: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: glyph)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.16)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(TicketType.rowTitle)
                    .foregroundStyle(.primary)
                Text(text)
                    .font(TicketType.rowDetail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
