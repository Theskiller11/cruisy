import ActivityKit
import WidgetKit
import SwiftUI

/// Il countdown sulla schermata di blocco e nella Dynamic Island.
///
/// È il posto in cui questa app dà il meglio: sei in banchina, il telefono in tasca,
/// e la risposta è già lì senza sbloccare niente.
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
            LockScreenView(context: context)
                .activityBackgroundTint(Color(hex: 0x0B1725).opacity(0.92))
                .activitySystemActionForegroundColor(context.tint)
        } dynamicIsland: { context in
            DynamicIsland {
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
                        .foregroundStyle(context.tint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: -1) {
                        Text(context.attributes.allAboardLabel)
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.inkPrimary)
                        Text("ora di bordo")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.inkSecondary)
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
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.inkPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        // Le cifre a sinistra, la didascalia **accanto**: il numero
                        // è la cosa che si legge, la parola che lo spiega gli sta di
                        // fianco. Ai due capi opposti della riga si guardavano da
                        // lontano e bisognava rileggere per collegarli.
                        //
                        // Larghezza **finita** sul contatore, non `fixedSize`:
                        // `Text(timerInterval:)` si prenota la larghezza massima che
                        // il conto potrà occupare, e senza un freno lascia zero alla
                        // didascalia — che è come era sparita. Ma il freno dev'essere
                        // un numero: in questa vista le misure indefinite fanno
                        // cadere il renderer.
                        HStack(alignment: .lastTextBaseline, spacing: 10) {
                            Text(timerInterval: context.state.range, pauseTime: nil,
                                 countsDown: true, showsHours: true)
                                .font(.system(size: 28, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(context.isStale ? Palette.adrift : Palette.inkPrimary)
                                .lineLimit(1)
                                .frame(width: 148, alignment: .leading)

                            Text(context.caption)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.inkSecondary)
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
                        .tint(context.isStale ? Palette.adrift : context.tint)
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                Image(systemName: context.glyph)
                    .foregroundStyle(context.isStale ? Palette.adrift : context.tint)
            } compactTrailing: {
                Text(timerInterval: context.state.range, pauseTime: nil,
                     countsDown: true, showsHours: true)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .frame(maxWidth: 62)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(context.isStale ? Palette.adrift : context.tint)
            } minimal: {
                // Nell'ultima ora la nave lascia il posto a un segnale di pericolo:
                // il colore da solo non basta a farsi notare in un cerchio da
                // ventiquattro punti.
                Image(systemName: context.isStale ? "exclamationmark.triangle.fill" : context.glyph)
                    .foregroundStyle(context.isStale ? Palette.adrift : context.tint)
            }
            .keylineTint(context.isStale ? Palette.adrift : context.tint)
            .widgetURL(URL(string: "cruisy://today"))
        }
    }
}

/// Le cose che dipendono dallo stato, in un posto solo.
extension ActivityViewContext where Attributes == AllAboardAttributes {
    /// Ambra in porto, verde acqua in navigazione: lo stesso codice colore dell'app.
    var tint: Color { state.kind.isAtSea ? Palette.underway : Palette.ashore }

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
}

private struct LockScreenView: View {
    let context: ActivityViewContext<AllAboardAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(context.state.kind.isAtSea
                         ? "In navigazione · \(context.attributes.portName)"
                         : "Rientro a bordo · \(context.attributes.portName)")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: context.isStale ? "exclamationmark.triangle.fill" : context.glyph)
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(context.isStale ? Palette.adrift : context.tint)

                Spacer(minLength: 8)

                Text(context.attributes.allAboardLabel)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.inkSecondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(context.caption)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.inkSecondary)
                Spacer(minLength: 8)
                Text(timerInterval: context.state.range, pauseTime: nil,
                     countsDown: true, showsHours: true)
                    .font(.system(size: 40, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(context.isStale ? Palette.adrift : Palette.inkPrimary)
            }

            ProgressView(timerInterval: context.state.range, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(context.isStale ? Palette.adrift : context.tint)

            HStack {
                if let berth = context.attributes.berthLabel, !context.state.kind.isAtSea {
                    Text(berth)
                }
                Spacer(minLength: 8)
                if let miles = context.state.milesRemaining {
                    Text("\(Format.nauticalMiles(miles)) alla meta")
                        .foregroundStyle(context.tint)
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Palette.inkSecondary)
        }
        .padding(16)
    }
}
