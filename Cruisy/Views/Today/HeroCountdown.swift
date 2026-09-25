import SwiftUI

/// Il numero grande di Oggi: quanto manca, in ore e minuti. Nell'ultima ora in
/// minuti e secondi.
///
/// Prima il biglietto aveva due numeri grandi che si contendevano l'occhio: l'ora
/// stampata («09:00») e, sotto, il countdown coi secondi («19:29:56»). Chi apre Oggi
/// vuole sapere quanto manca; l'orario resta, ma scende in una riga. E sotto le
/// cifre c'è scritto che cosa sono — «ore», «min» — perché «19:29» da solo si
/// leggerebbe come un orario, che è l'errore peggiore che questa schermata possa
/// indurre.
///
/// Sopra l'ora i secondi sono rumore, come nella Dynamic Island: tornano
/// nell'ultima ora, quando contano.
struct HeroCountdown: View {
    @Environment(\.livery) private var livery
    let countdown: Countdown
    var colour: Color?
    /// Scarto fra l'ora vera e il punto di osservazione: zero in produzione.
    var offset: TimeInterval = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            digits(countdown.components(at: context.date.addingTimeInterval(offset)))
        }
    }

    private func digits(_ c: (hours: Int, minutes: Int, seconds: Int)) -> some View {
        let overHour = c.hours > 0
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            group(overHour ? String(c.hours) : String(c.minutes),
                  unit: overHour ? Text("ore") : Text("min"))
            Text(verbatim: ":").ticketHour()
            group(String(format: "%02d", overHour ? c.minutes : c.seconds),
                  unit: overHour ? Text("min") : Text("sec"))
        }
        .foregroundStyle(colour ?? livery.ink)
        // Un filo d'aria fra «ore / min» e il nome del porto sotto: attaccati, le
        // due righe di maiuscolette si leggevano come una sola.
        .padding(.bottom, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken(c)))
    }

    private func group(_ value: String, unit: Text) -> some View {
        VStack(spacing: -6) {
            Text(verbatim: value).ticketHour()
            unit.ticketFieldLabel(livery.field)
        }
    }

    /// VoiceOver non sente i secondi: cambierebbero a ogni ridisegno. Si legge al minuto.
    private func spoken(_ c: (hours: Int, minutes: Int, seconds: Int)) -> String {
        if c.hours > 0 {
            return String(localized: "\(c.hours) ore e \(c.minutes) minuti", comment: "Countdown letto da VoiceOver")
        }
        if c.minutes > 0 {
            return String(localized: "\(c.minutes) minuti", comment: "Countdown letto da VoiceOver")
        }
        return String(localized: "meno di un minuto", comment: "Countdown letto da VoiceOver")
    }
}

/// La traversata come una linea: da dove si è partiti a dove si arriva, con la
/// nave dove l'orario dice che dovrebbe essere.
///
/// La posizione sulla linea è quella **dell'orario**, non del GPS: è la stessa
/// grandezza del countdown, che viene dall'itinerario. Le miglia che restano,
/// quelle sì, vengono dalla posizione, quando c'è.
struct PassageTrack: View {
    @Environment(\.livery) private var livery
    let from: PortCall
    let to: PortCall
    let now: Date
    let clock: ShipClock
    var milesLeft: Double?

    private var progress: Double {
        let total = to.arrival.timeIntervalSince(from.castOff)
        guard total > 0 else { return 0 }
        return min(max(now.timeIntervalSince(from.castOff) / total, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(from.name).lineLimit(1)
                Spacer(minLength: 12)
                Text(to.name).lineLimit(1)
            }
            .font(TicketType.rowTitle)
            .foregroundStyle(livery.ink)

            line
                .frame(height: 16)

            HStack(alignment: .firstTextBaseline) {
                if let milesLeft {
                    Text("\(Format.nauticalMiles(milesLeft)) alla meta")
                }
                Spacer(minLength: 12)
                Text("partita alle \(clock.time(from.castOff))")
            }
            .font(TicketType.rowDetail)
            .foregroundStyle(livery.field)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    private var line: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = width * progress
            ZStack(alignment: .leading) {
                Path { p in
                    p.move(to: CGPoint(x: x, y: 8))
                    p.addLine(to: CGPoint(x: width - 5, y: 8))
                }
                .stroke(livery.perforation, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 4]))
                Capsule().fill(livery.ink).frame(width: max(x, 4), height: 2.5).offset(y: 0)
                Circle().fill(livery.ink).frame(width: 7, height: 7).offset(x: -1)
                Circle().stroke(livery.ink, lineWidth: 2).frame(width: 8, height: 8).offset(x: width - 8)
                Image(systemName: "ferry.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(livery.ink)
                    .background(Circle().fill(livery.paper).frame(width: 22, height: 22))
                    .offset(x: min(max(x - 8, 0), width - 18), y: -1)
            }
            .frame(height: 16)
        }
    }

    private var spoken: String {
        let percent = Int((progress * 100).rounded())
        var text = String(localized: "Da \(from.name) a \(to.name), traversata al \(percent) per cento")
        if let milesLeft { text += ", " + String(localized: "\(Int(milesLeft)) miglia alla meta") }
        return text
    }
}

/// La giornata in porto come una barra: l'attracco, adesso, il rientro a bordo, la
/// partenza. Si capisce quanto resta senza fare conti, e dove sta il rientro
/// rispetto alla partenza — che non sono la stessa ora, e confonderle è il modo
/// di perdere la nave.
struct PortDayBar: View {
    @Environment(\.livery) private var livery
    let call: PortCall
    let now: Date
    let clock: ShipClock

    private func position(_ date: Date) -> Double {
        let total = call.castOff.timeIntervalSince(call.arrival)
        guard total > 0 else { return 0 }
        return min(max(date.timeIntervalSince(call.arrival) / total, 0), 1)
    }

    var body: some View {
        let nowAt = position(now)
        let aboardAt = call.allAboard.map(position)
        VStack(spacing: 4) {
            // L'ora del rientro sopra la sua tacca, allineata a lei.
            if let aboardAt, let aboard = call.allAboard {
                GeometryReader { proxy in
                    Text(clock.time(aboard))
                        .font(TicketType.fieldLabel.weight(.heavy))
                        .foregroundStyle(livery.signalInk)
                        .fixedSize()
                        .position(x: proxy.size.width * aboardAt, y: 6)
                }
                .frame(height: 12)
            }

            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(livery.rule).frame(height: 6)
                    Capsule().fill(livery.ink).frame(width: max(width * nowAt, 6), height: 6)
                    if let aboardAt {
                        Capsule().fill(livery.signal)
                            .frame(width: 2.5, height: 18)
                            .offset(x: width * aboardAt - 1.25)
                    }
                    Circle()
                        .fill(livery.paper)
                        .overlay(Circle().stroke(livery.ink, lineWidth: 2.5))
                        .frame(width: 13, height: 13)
                        .offset(x: min(max(width * nowAt - 6.5, 0), width - 13))
                }
                .frame(height: 18)
            }
            .frame(height: 18)

            HStack(alignment: .firstTextBaseline) {
                Text("attracco \(clock.time(call.arrival))")
                Spacer(minLength: 8)
                Text("partenza \(clock.time(call.castOff))")
            }
            .font(TicketType.rowDetail)
            .foregroundStyle(livery.field)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spoken))
    }

    private var spoken: String {
        var parts = [String(localized: "Attracco alle \(clock.time(call.arrival))")]
        if let aboard = call.allAboard {
            parts.append(String(localized: "rientro a bordo alle \(clock.time(aboard))"))
        }
        parts.append(String(localized: "partenza alle \(clock.time(call.castOff))"))
        return parts.joined(separator: ", ")
    }
}

/// Il countdown in una riga: «fra 2:59», e nell'ultima ora «fra 19:56». Le stesse
/// regole del numero grande di Oggi, per le righe che non sono Oggi.
struct CompactCountdown: View {
    let countdown: Countdown
    var offset: TimeInterval = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let c = countdown.components(at: context.date.addingTimeInterval(offset))
            let digits = c.hours > 0 ? String(format: "%d:%02d", c.hours, c.minutes)
                                     : String(format: "%d:%02d", c.minutes, c.seconds)
            Text("fra \(digits)")
                .monospacedDigit()
                .lineLimit(1)
                .accessibilityLabel(Text(c.hours > 0
                    ? String(localized: "fra \(c.hours) ore e \(c.minutes) minuti")
                    : String(localized: "fra \(c.minutes) minuti")))
        }
    }
}
