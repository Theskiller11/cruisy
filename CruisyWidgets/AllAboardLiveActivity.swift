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
            return DynamicIsland {
                // Le regioni laterali sono due fessure accanto alla fotocamera:
                // qualunque testo ci finisca viene rimpicciolito o tagliato. Qui ci
                // sta solo il glifo, che non ha niente da troncare. Il nome del
                // porto sta sotto, dove c'è la larghezza per scriverlo per esteso.
                // Le tre regioni hanno margini propri: il glifo deve poggiare sul
                // margine **naturale** della sua, che è lo stesso su cui poggia la
                // regione sotto. Una cornice a larghezza piena lo sposta e i due
                // bordi sinistri non coincidono più.
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.glyph)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(context.isStale ? .red : livery.signalOnHull)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: -1) {
                        Text(context.attributes.allAboardLabel)
                            .font(.system(size: 16, weight: .black).width(.compressed))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                        Text("ora di bordo")
                            .font(.system(size: 9))
                            .foregroundStyle(livery.onHullMuted)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    // Un paio di punti di respiro: a filo del bordo il sistema
                    // taglia l'ultima cifra.
                    .padding(.trailing, 3)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                // Qui c'è tutta la larghezza, quindi qui va il contenuto. Tre righe
                // che poggiano tutte sullo stesso bordo sinistro: il nome del porto,
                // le cifre con accanto ciò che misurano, la barra.
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(context.attributes.portName)
                            .font(.system(size: 14, weight: .bold).width(.condensed))
                            .textCase(.uppercase)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        // Le cifre a sinistra, la didascalia **accanto**: il numero
                        // è la cosa che si legge, la parola che lo spiega gli sta di
                        // fianco.
                        //
                        // Larghezza **finita** sul contatore, non `fixedSize`:
                        // `Text(timerInterval:)` si prenota la larghezza massima che
                        // il conto potrà occupare, e senza un freno lascia zero alla
                        // didascalia. Ma il freno dev'essere un numero: in questa
                        // vista le misure indefinite fanno cadere il renderer.
                        HStack(alignment: .lastTextBaseline, spacing: 10) {
                            Text(timerInterval: context.state.range, pauseTime: nil,
                                 countsDown: true, showsHours: true)
                                .font(.system(size: 28, weight: .black).width(.condensed))
                                .monospacedDigit()
                                .foregroundStyle(context.isStale ? .red : .white)
                                .lineLimit(1)
                                .frame(width: 148, alignment: .leading)

                            Text(context.caption)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(livery.onHullMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)

                            Spacer(minLength: 0)
                        }

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
                        .tint(context.isStale ? .red : livery.signalOnHull)
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                Image(systemName: context.glyph)
                    .foregroundStyle(context.isStale ? .red : livery.signalOnHull)
            } compactTrailing: {
                Text(timerInterval: context.state.range, pauseTime: nil,
                     countsDown: true, showsHours: true)
                    .font(.system(size: 13, weight: .black).width(.condensed))
                    .monospacedDigit()
                    .frame(maxWidth: 62)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(context.isStale ? .red : livery.signalOnHull)
            } minimal: {
                // Nell'ultima ora la nave lascia il posto a un segnale di pericolo:
                // il colore da solo non basta a farsi notare in un cerchio da
                // ventiquattro punti.
                Image(systemName: context.isStale ? "exclamationmark.triangle.fill" : context.glyph)
                    .foregroundStyle(context.isStale ? .red : livery.signalOnHull)
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
                    Text(timerInterval: context.state.range, pauseTime: nil,
                         countsDown: true, showsHours: true)
                        .font(.system(size: 30, weight: .black).width(.condensed))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .multilineTextAlignment(.trailing)
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
