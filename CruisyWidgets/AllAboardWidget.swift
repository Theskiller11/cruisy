import WidgetKit
import SwiftUI

/// Il countdown sulla schermata Home: una matrice di biglietto.
///
/// Il numero **non** lo disegna il widget: lo disegna il sistema, con
/// `Text(timerInterval:)`. In un widget non si può far girare un timer, e ricaricare
/// la timeline ogni secondo per aggiornare le cifre sarebbe impossibile prima ancora
/// che sconveniente. Consegnare al sistema due date e lasciarlo contare è l'unico
/// modo che funziona — e il motivo per cui, in tutta l'app, un countdown è una coppia
/// di istanti e mai un contatore.
///
/// Parla la lingua dell'app: carta, l'ora stampata grande, l'etichetta in colore
/// segnale, i campi. La livrea è quella scelta nelle Impostazioni, letta dal
/// contenitore condiviso, e i token sono dinamici: chiaro e scuro vengono da soli.
struct AllAboardWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "it.matteopapini.Cruisy.AllAboard",
                            provider: VoyageTimelineProvider()) { entry in
            AllAboardWidgetView(entry: entry)
                .environment(\.livery, entry.livery)
                .containerBackground(for: .widget) { entry.livery.paper }
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

    /// La livrea come la vede l'app: la scelta condivisa e la compagnia della nave.
    var livery: Livery {
        Livery.resolve(LiveryChoice.stored(),
                       operatorName: voyage.flatMap { ShipDirectory.shared.lookup($0.shipName)?.operatorName })
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

struct AllAboardWidgetView: View {
    let entry: VoyageEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.livery) private var livery

    var body: some View {
        if let voyage = entry.voyage, let focus = entry.focus {
            switch family {
            case .systemMedium: medium(voyage: voyage, focus: focus)
            default: small(voyage: voyage, focus: focus)
            }
        } else {
            empty
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "ticket")
                .font(.title3)
                .foregroundStyle(livery.field)
            Text("Nessuna crociera")
                .font(.system(.caption, weight: .bold).width(.condensed))
                .textCase(.uppercase)
                .foregroundStyle(livery.ink)
            Text("Aggiungi il tuo itinerario in Cruisy.")
                .font(.caption2)
                .foregroundStyle(livery.field)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Piccolo: l'ora stampata e il conto

    private func small(voyage: Voyage, focus: Voyage.Focus) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            eyebrow(focus: focus)
            hour(voyage: voyage, focus: focus)
            place(focus: focus)
            Spacer(minLength: 2)
            // Il sistema conta da sé, senza ricaricare la timeline.
            Text(timerInterval: focus.countdown.range,
                 pauseTime: nil, countsDown: true, showsHours: true)
                .font(.system(size: 22, weight: .black).width(.condensed))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .foregroundStyle(livery.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(URL(string: "cruisy://today"))
    }

    // MARK: Medio: biglietto e matrice, con la perforazione in mezzo

    private func medium(voyage: Voyage, focus: Voyage.Focus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                eyebrow(focus: focus)
                hour(voyage: voyage, focus: focus)
                place(focus: focus)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VerticalPerforation()

            VStack(alignment: .leading, spacing: 6) {
                Text("Mancano")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .foregroundStyle(livery.field)
                Text(timerInterval: focus.countdown.range,
                     pauseTime: nil, countsDown: true, showsHours: true)
                    .font(.system(size: 24, weight: .black).width(.condensed))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(livery.ink)
                ProgressView(timerInterval: focus.countdown.range, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .progressViewStyle(.linear)
                .tint(livery.signal)
                fields(voyage: voyage, focus: focus)
                Spacer(minLength: 0)
            }
            .frame(width: 118, alignment: .leading)
        }
        .widgetURL(URL(string: "cruisy://today"))
    }

    // MARK: I pezzi

    private func eyebrow(focus: Voyage.Focus) -> some View {
        Text(headline(focus: focus))
            .font(.system(size: 9, weight: .bold))
            .tracking(1.2)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(livery.signalInk)
    }

    private func hour(voyage: Voyage, focus: Voyage.Focus) -> some View {
        Text(voyage.clock.time(focus.countdown.target))
            .font(.system(size: family == .systemSmall ? 40 : 44, weight: .black).width(.compressed))
            .monospacedDigit()
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .foregroundStyle(livery.ink)
    }

    private func place(focus: Voyage.Focus) -> some View {
        Text(focus.port.name)
            .font(.system(size: 12, weight: .bold).width(.condensed))
            .textCase(.uppercase)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .foregroundStyle(livery.ink)
    }

    /// Due campi della matrice: quelli che servono per non perdere la nave.
    @ViewBuilder
    private func fields(voyage: Voyage, focus: Voyage.Focus) -> some View {
        let clock = voyage.clock
        HStack(alignment: .top, spacing: 10) {
            switch focus.kind {
            case .allAboard(let call), .sailAway(let call):
                if let departure = call.departure {
                    field(String(localized: "Partenza"), clock.time(departure))
                }
                field(String(localized: "Molo"), call.berth.name ?? call.berth.label.capitalized)
            case .arrival(let call):
                if let miles = milesRemaining(voyage: voyage) {
                    field(String(localized: "Alla meta"), Format.nauticalMiles(miles))
                }
                field(String(localized: "Molo"), call.berth.name ?? call.berth.label.capitalized)
            case .boarding(let call):
                field(String(localized: "Imbarco dalle"), clock.time(call.arrival))
                field(String(localized: "Orario"), call.scheduleOrigin.fieldValue)
            }
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(livery.field)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(livery.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Le miglia che restano, ricavate dagli orari: senza GPS il widget non ha altro,
    /// ed è comunque l'ordine di grandezza giusto.
    private func milesRemaining(voyage: Voyage) -> Double? {
        guard let fix = voyage.scheduledFix(at: entry.date) else { return nil }
        return voyage.milesRemaining(from: fix, at: entry.date)
    }

    private func headline(focus: Voyage.Focus) -> String {
        switch focus.kind {
        case .allAboard: String(localized: "Rientro a bordo")
        case .sailAway: String(localized: "Partenza")
        case .arrival: String(localized: "Arrivo")
        case .boarding: String(localized: "Imbarco")
        }
    }
}

/// La perforazione in verticale: nel widget medio biglietto e matrice stanno
/// affiancati, non uno sopra l'altro.
private struct VerticalPerforation: View {
    @Environment(\.livery) private var livery

    var body: some View {
        Line()
            .stroke(livery.perforation, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            .frame(width: 1.5)
            .accessibilityHidden(true)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            return path
        }
    }
}
