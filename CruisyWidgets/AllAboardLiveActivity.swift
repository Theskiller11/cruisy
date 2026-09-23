import ActivityKit
import WidgetKit
import SwiftUI

/// Il countdown sulla schermata di blocco e nella Dynamic Island.
///
/// È il posto in cui questa app dà il meglio: sei in banchina, il telefono in tasca,
/// e la risposta è già lì senza sbloccare niente. Sulla schermata di blocco è la
/// matrice di un biglietto: carta, l'etichetta in colore segnale, l'ora stampata e
/// le cifre che scorrono. Nella Dynamic Island, che è nera, restano il bianco e il
/// segnale sullo scafo.
///
/// **Il rosso dell'ultima ora arriva da solo.** Un'attività in tempo reale non
/// ricalcola nulla per conto suo — sa solo far scorrere le date con
/// `Text(timerInterval:)` e `ProgressView(timerInterval:)`; qualunque testo calcolato
/// da noi resterebbe congelato fino al prossimo aggiornamento. L'unica transizione
/// automatica che il sistema concede è `staleDate`, quindi la si mette **a un'ora dal
/// traguardo** e si usa `context.isStale` come segnale di allarme. Un solo scatto,
/// ma è quello che conta.
struct AllAboardLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AllAboardAttributes.self) { context in
            let livery = context.livery
            LockScreenView(context: context)
                .environment(\.livery, livery)
                .activityBackgroundTint(livery.paper)
                .activitySystemActionForegroundColor(livery.signalInk)
        } dynamicIsland: { context in
            let livery = context.livery
            let accent: Color = context.isStale ? .red : livery.signalOnHull
            return DynamicIsland {
                // Espansa, come un biglietto: in alto a sinistra **che cosa** si
                // aspetta e dove, in alto a destra **quanto** manca, sotto la barra e
                // l'ora di bordo del traguardo. Prima il numero stava a sinistra, la
                // didascalia fluttuava a metà riga e l'angolo in alto a destra teneva
                // un'ora piccola che non diceva niente di nuovo: l'occhio non sapeva
                // da dove cominciare.
                //
                // Le regioni laterali stanno accanto alla fotocamera e si allungano
                // sotto di lei: ci entrano due righe corte per parte. Il nome del
                // porto si stringe prima di tagliarsi.
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: context.isStale ? "exclamationmark.triangle.fill" : context.glyph)
                            Text(context.eyebrow)
                                .textCase(.uppercase)
                                .tracking(0.6)
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                        Text(context.attributes.portName)
                            .font(.system(size: 19, weight: .heavy).width(.condensed))
                            .textCase(.uppercase)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    .padding(.leading, 4)
                    .padding(.top, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 0) {
                        ActivityCountdown(range: context.state.range, urgent: context.isStale,
                                          size: 34, alignment: .trailing)
                            .foregroundStyle(context.isStale ? .red : .white)
                        Text(context.caption)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(livery.onHullMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    // Un paio di punti di respiro: a filo del bordo il sistema
                    // taglia l'ultima cifra.
                    .padding(.trailing, 4)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 7) {
                        // **Non toccare questa barra con modificatori di stile o
                        // di larghezza.** `ProgressView(timerInterval:)` la disegna
                        // il sistema, e in una Live Activity ci arriva dentro un
                        // layout che misura lo spazio disponibile: `.progressViewStyle`
                        // più `.frame(maxWidth: .infinity)` gli propongono una
                        // larghezza infinita, `LayoutSubview.place` va in assertion e
                        // il renderer muore — sullo schermo resta una barra nera
                        // vuota. Occupa già tutta la riga da sola.
                        ProgressView(timerInterval: context.state.range, countsDown: false) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(accent)

                        HStack(spacing: 8) {
                            Text(context.deadline)
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer(minLength: 8)
                            if let berth = context.attributes.berthLabel, !context.state.kind.isAtSea {
                                Text(berth)
                                    .foregroundStyle(livery.onHullMuted)
                            }
                        }
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "exclamationmark.triangle.fill" : context.glyph)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
                    .padding(.leading, 2)
            } compactTrailing: {
                // Largo quanto le cifre e non di più: `Text(timerInterval:)` da solo
                // si prenota la larghezza del conto più lungo possibile, e l'isola si
                // allargava fino ai bordi dello schermo con le cifre sperdute nel nero.
                ActivityCountdown(range: context.state.range, urgent: context.isStale,
                                  size: 15, alignment: .trailing)
                    .foregroundStyle(accent)
                    .padding(.trailing, 2)
            } minimal: {
                // Nell'ultima ora la nave lascia il posto a un segnale di pericolo:
                // il colore da solo non basta a farsi notare in un cerchio da
                // ventiquattro punti.
                Image(systemName: context.isStale ? "exclamationmark.triangle.fill" : context.glyph)
                    .foregroundStyle(accent)
            }
            .keylineTint(context.isStale ? .red : livery.signalOnHull)
            .widgetURL(URL(string: "cruisy://today"))
        }
    }
}

/// Le cose che dipendono dallo stato, in un posto solo.
extension ActivityViewContext where Attributes == AllAboardAttributes {
    /// La livrea come la vede l'app: la scelta condivisa e la compagnia della nave.
    var livery: Livery {
        Livery.resolve(LiveryChoice.stored(),
                       operatorName: ShipDirectory.shared.lookup(attributes.shipName)?.operatorName)
    }

    var glyph: String {
        state.kind.isAtSea ? "water.waves" : "figure.walk.departure"
    }

    /// A che cosa si riferisce il numero grande. **Senza** il nome del porto: ora
    /// sta scritto sopra, e ripeterlo mangiava la larghezza che serve alle cifre.
    var caption: String {
        let what = state.kind.isAtSea
            ? String(localized: "all'arrivo")
            : String(localized: "al tutti a bordo")
        // Le miglia in coda alla didascalia invece che su una riga propria: in
        // navigazione sono corte, e una riga in meno è spazio per le cifre.
        guard let miles = state.milesRemaining else { return what }
        return "\(what) · \(Format.nauticalMiles(miles))"
    }

    /// Il traguardo in ora di bordo, per esteso: la riga sotto la barra.
    var deadline: String {
        state.kind.isAtSea
            ? String(localized: "Attracco alle \(attributes.allAboardLabel) · ora di bordo")
            : String(localized: "Entro le \(attributes.allAboardLabel) · ora di bordo")
    }

    /// L'etichetta del biglietto: che cosa si sta aspettando.
    var eyebrow: String {
        state.kind.isAtSea ? String(localized: "Arrivo") : String(localized: "Rientro a bordo")
    }
}

/// La schermata di blocco: la matrice del biglietto.
private struct LockScreenView: View {
    let context: ActivityViewContext<AllAboardAttributes>
    @Environment(\.livery) private var livery

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text("\(context.eyebrow) · \(context.attributes.portName)")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } icon: {
                    Image(systemName: context.isStale ? "exclamationmark.triangle.fill" : context.glyph)
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(context.isStale ? .red : livery.signalInk)

                Spacer(minLength: 8)

                if let berth = context.attributes.berthLabel, !context.state.kind.isAtSea {
                    Text(berth)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(livery.field)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 12) {
                // L'ora stampata: la cosa che si ricorda.
                Text(context.attributes.allAboardLabel)
                    .font(.system(size: 40, weight: .black).width(.compressed))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(livery.ink)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(context.caption)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(livery.field)
                        .lineLimit(1)
                    ActivityCountdown(range: context.state.range, urgent: context.isStale,
                                      size: 30, alignment: .trailing)
                        .foregroundStyle(context.isStale ? .red : livery.ink)
                }
            }

            ProgressView(timerInterval: context.state.range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(context.isStale ? .red : livery.signal)
        }
        .padding(16)
    }
}
