import WidgetKit
import SwiftUI

/// Il countdown sulla schermata Home.
///
/// Il numero **non** lo disegna il widget: lo disegna il sistema, con
/// `Text(timerInterval:)`. In un widget non si può far girare un timer, e ricaricare
/// la timeline ogni secondo per aggiornare le cifre sarebbe impossibile prima ancora
/// che sconveniente. Consegnare al sistema due date e lasciarlo contare è l'unico
/// modo che funziona — e il motivo per cui, in tutta l'app, un countdown è una coppia
/// di istanti e mai un contatore.
struct AllAboardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "it.matteopapini.Cruisy.AllAboard",
                            provider: VoyageTimelineProvider()) { entry in
            AllAboardWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetBackgroundBridge(entry: entry)
                }
        }
        .configurationDisplayName("Prossimo countdown")
        .description("Quanto manca al rientro a bordo, o all'arrivo nel prossimo porto.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: Timeline

struct VoyageEntry: TimelineEntry {
    let date: Date
    let voyage: Voyage?
    let focus: Voyage.Focus?

    var isInPort: Bool {
        guard let focus else { return false }
        if case .allAboard = focus.kind { return true }
        if case .sailAway = focus.kind { return true }
        return false
    }
}

struct VoyageTimelineProvider: TimelineProvider {

    func placeholder(in context: Context) -> VoyageEntry {
        VoyageEntry(date: .now, voyage: nil, focus: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (VoyageEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// La timeline ha pochissime voci: una adesso, e una a ogni cambio di **stato**
    /// (l'all aboard che scade, l'arrivo in porto). Le cifre che scorrono non sono
    /// affar nostro, quindi non servono voci al minuto.
    func getTimeline(in context: Context, completion: @escaping (Timeline<VoyageEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)

        var dates: [Date] = []
        if let target = current.focus?.countdown.target, target > now {
            dates.append(target.addingTimeInterval(1))
        }
        if let voyage = current.voyage {
            // I prossimi due appuntamenti bastano: oltre, il sistema ci avrà già
            // richiesto una nuova timeline.
            let upcoming = voyage.calls
                .flatMap { [$0.allAboard, $0.arrival, $0.departure].compactMap(\.self) }
                .filter { $0 > now }
                .sorted()
                .prefix(2)
            dates.append(contentsOf: upcoming)
        }

        let entries = [current] + dates.sorted().map { entry(at: $0) }
        let refresh = dates.min() ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }

    private func entry(at date: Date) -> VoyageEntry {
        let voyage = VoyageArchive.load()
        return VoyageEntry(date: date, voyage: voyage, focus: voyage?.focus(at: date))
    }
}

// MARK: Aspetto

/// Legge la famiglia dall'ambiente e la passa allo sfondo, che ne ha bisogno per
/// sapere se disegnare la carta.
private struct WidgetBackgroundBridge: View {
    let entry: VoyageEntry
    @Environment(\.widgetFamily) private var family

    var body: some View { WidgetBackground(entry: entry, family: family) }
}

/// Lo sfondo del widget.
///
/// Sul medio è la **carta**, a tutto riquadro. Non è decorazione: è la stessa
/// geometria che l'app disegna, quindi dice davvero dove sei — e non costa rete,
/// perché le coste viaggiano nel bundle dell'estensione.
///
/// Sopra ci va una velatura scura con un gradiente da sinistra a destra: il testo
/// deve restare leggibile dove sta, e la nave deve respirare dove finisce il testo.
private struct WidgetBackground: View {
    let entry: VoyageEntry
    let family: WidgetFamily

    private var tint: Color { entry.isInPort ? Palette.ashore : Palette.underway }

    var body: some View {
        ZStack {
            if family == .systemMedium, let voyage = entry.voyage {
                SeaChart(voyage: voyage,
                         fix: voyage.scheduledFix(at: entry.date),
                         now: entry.date,
                         // La nave finisce a destra, nello spazio che il testo lascia
                         // libero, invece che al centro sotto le cifre.
                         framing: .shipAnchored(spanDegrees: entry.isInPort ? 1.6 : 7.5,
                                                at: UnitPoint(x: 0.76, y: 0.52)),
                         showsPortNames: false, showsGraticule: false)

                // Esposizione ridotta: la carta resta leggibile ma smette di
                // competere col countdown, che è il motivo per cui il widget esiste.
                LinearGradient(
                    stops: [.init(color: Palette.abyss.opacity(0.92), location: 0),
                            .init(color: Palette.abyss.opacity(0.74), location: 0.45),
                            .init(color: Palette.abyss.opacity(0.34), location: 1)],
                    startPoint: .leading, endPoint: .trailing)
            } else {
                LinearGradient(colors: entry.isInPort
                               ? [Color(hex: 0x2A1E0E), Color(hex: 0x0B1725)]
                               : [Color(hex: 0x0D3350), Color(hex: 0x061826)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
    }
}

struct AllAboardWidgetView: View {
    let entry: VoyageEntry
    @Environment(\.widgetFamily) private var family

    private var tint: Color { entry.isInPort ? Palette.ashore : Palette.underway }

    var body: some View {
        if let voyage = entry.voyage, let focus = entry.focus {
            content(voyage: voyage, focus: focus)
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "ferry")
                .font(.title3)
                .foregroundStyle(Palette.underway)
            Text("Nessuna crociera")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Palette.inkPrimary)
            Text("Aggiungi il tuo itinerario in Cruisy.")
                .font(.caption2)
                .foregroundStyle(Palette.inkSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func content(voyage: Voyage, focus: Voyage.Focus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Label {
                Text(headline(focus: focus))
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } icon: {
                Image(systemName: entry.isInPort ? "figure.walk.departure" : "water.waves")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(tint)

            Spacer(minLength: 4)

            // Il sistema conta da sé, senza ricaricare la timeline.
            Text(timerInterval: focus.countdown.range,
                 pauseTime: nil, countsDown: true, showsHours: true)
                .font(.system(size: family == .systemSmall ? 28 : 32,
                              weight: .semibold, design: .default))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(Palette.inkPrimary)

            Text(subtitle(voyage: voyage, focus: focus))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(2)
                .padding(.top, 2)

            if let miles = milesRemaining(voyage: voyage) {
                Text("\(Format.nauticalMiles(miles)) alla meta")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.top, 3)
            }

            if family == .systemMedium {
                ProgressView(timerInterval: focus.countdown.range, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(tint)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: family == .systemMedium ? 178 : .infinity,
               maxHeight: .infinity, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "cruisy://today"))
    }

    /// Le miglia che restano, ricavate dagli orari: senza GPS il widget non ha altro,
    /// ed è comunque l'ordine di grandezza giusto.
    private func milesRemaining(voyage: Voyage) -> Double? {
        guard let fix = voyage.scheduledFix(at: entry.date) else { return nil }
        return voyage.milesRemaining(from: fix, at: entry.date)
    }

    private func headline(focus: Voyage.Focus) -> String {
        switch focus.kind {
        case .allAboard: String(localized: "ALL ABOARD")
        case .sailAway: String(localized: "PARTENZA")
        case .arrival: String(localized: "ARRIVO")
        case .boarding: String(localized: "IMBARCO")
        }
    }

    private func subtitle(voyage: Voyage, focus: Voyage.Focus) -> String {
        "\(focus.port.name) · \(voyage.clock.time(focus.countdown.target))"
    }
}
