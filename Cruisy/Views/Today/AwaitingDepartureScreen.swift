import SwiftUI

/// La schermata di chi ha la crociera davanti, ma non ancora sotto i piedi.
///
/// Finché mancano più di dodici ore, i countdown al secondo, la velocità e la carta
/// live non dicono niente di utile: non c'è ancora niente da misurare. Quello che
/// serve è sapere quanto manca e restare con la voglia. Da lì in poi si accende la
/// vista normale, perché la sera prima l'app torna a essere uno strumento.
struct AwaitingDepartureScreen: View {
    let voyage: Voyage
    let call: PortCall
    let countdown: Countdown
    let now: Date

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var photos = ShipPhotoService()
    @Environment(Reachability.self) private var reachability

    /// La nave, se è nell'elenco: serve solo a sapere quale foto chiedere.
    private var record: ShipRecord? { ShipDirectory.shared.lookup(voyage.shipName) }

    /// Giorni di bordo che restano: la differenza fra le due mezzanotti, che è come
    /// una persona conta i giorni a una partenza.
    private var daysAway: Int {
        // Ogni mezzanotte col **suo** scarto: fra oggi e l'imbarco l'orologio di
        // bordo può essersi spostato. Poi si arrotonda, perché un'ora di scarto non
        // deve poter aggiungere o togliere un giorno all'attesa.
        let today = voyage.clock.startOfDay(for: now)
        let boarding = voyage.clock.startOfDay(for: countdown.target)
        return max(0, Int((boarding.timeIntervalSince(today) / 86_400).rounded()))
    }

    private var hasBoardingTime: Bool {
        let calendar = voyage.clock.calendar(at: countdown.target)
        return calendar.component(.hour, from: countdown.target) != 0
            || calendar.component(.minute, from: countdown.target) != 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ShipHero(voyage: voyage, now: now,
                         photo: photos.photo.map { Image(uiImage: $0.image) },
                         credit: photos.photo?.credit)

                VStack(spacing: 22) {
                    counter
                    routeCard
                    details
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 110)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .ignoresSafeArea(edges: .top)
        .task(id: "\(record?.imageFile ?? "")|\(reachability.isExpensive)") {
            if let record {
                await photos.load(record, allowsDownload: PhotoDownloadPolicy.allows(isMetered: reachability.isExpensive))
            }
        }
    }

    // MARK: Il numero

    private var counter: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(daysAway)")
                    .displayNumeral(size: 108, cap: 150)
                    .foregroundStyle(Palette.inkPrimary)
                Text(daysAway == 1 ? "giorno" : "giorni")
                    .font(.title.weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(daysAway == 1 ? "Manca un giorno alla partenza"
                                     : "Mancano \(daysAway) giorni alla partenza"))

            Text(encouragement)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.action)
                .multilineTextAlignment(.center)
        }
    }

    /// Il tono si stringe man mano che la data si avvicina.
    private var encouragement: String {
        switch daysAway {
        case 0: String(localized: "È il giorno giusto.")
        case 1: String(localized: "Domani si parte.")
        case 2...6: String(localized: "Ci siamo quasi: prepara la valigia.")
        case 7...29: String(localized: "Preparati a salpare.")
        default: String(localized: "Buona attesa. Goditela già da adesso.")
        }
    }

    /// La rotta, toccabile.
    ///
    /// Da quando la testata è diventata la fotografia della nave, la carta da qui
    /// non si raggiungeva più: la scheda Carta non c'è più — ci si arriva dalla card
    /// — e prima della partenza quella card non compariva da nessuna parte. Sono i
    /// giorni in cui uno la guarda di più, per giunta: la rotta è tutto ciò che c'è
    /// da vedere finché non si sale a bordo.
    private var routeCard: some View {
        NavigationLink(value: TodayScreen.Route.chart) {
            ChartPreviewCard(voyage: voyage, fix: nil, now: now,
                             framing: .wholeVoyage,
                             title: String(localized: "La rotta"),
                             showsPortNames: true,
                             showsGraticule: true,
                             height: 196)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Apri la carta con tutta la rotta"))
    }

    // MARK: Il contorno

    private var details: some View {
        VStack(spacing: 12) {
            InfoRow(glyph: "mappin.and.ellipse", tint: Palette.action,
                    title: String(localized: "Imbarco a \(call.name)"),
                    subtitle: whenLine)

            InfoRow(glyph: "list.bullet.indent", tint: Palette.underway,
                    title: String(localized: "\(voyage.intermediateCalls.count) scali · \(voyage.nights) notti"),
                    subtitle: String(localized: "L'itinerario è già pronto nella scheda Itinerario."))

            HStack {
                ProvenanceChip(origin: countdown.origin)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private var whenLine: String {
        let date = Format.dayMonth(countdown.target, clock: voyage.clock)
        guard hasBoardingTime else { return date }
        return "\(date) · \(voyage.clock.time(countdown.target)) · ora di bordo"
    }
}

/// La testata della schermata d'attesa.
///
/// Oggi mostra la rotta della crociera, disegnata dagli scali veri. È una scelta,
/// non un ripiego: un rettangolo vuoto in attesa di una foto sarebbe contenuto
/// segnaposto — che tra l'altro non supera la revisione — mentre la propria rotta
/// disegnata dice già qualcosa di vero e fa venire voglia di partire.
///
/// Il posto per la foto della nave c'è già: quando arriverà basterà passarla a
/// `photo`, e prenderà il posto della carta senza toccare altro.
struct ShipHero: View {
    let voyage: Voyage
    let now: Date
    var photo: Image?
    /// Il credito della fotografia. **Obbligatorio quando c'è una foto**: le
    /// immagini di Commons sono libere ma quasi tutte impongono di citare l'autore.
    var credit: String?

    @ScaledMetric(relativeTo: .largeTitle) private var height: CGFloat = 300

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(height: min(height, 420))
                .overlay { backdrop }
                .clipped()

            LinearGradient(
                stops: [.init(color: .clear, location: 0),
                        .init(color: Palette.abyss.opacity(0.55), location: 0.55),
                        .init(color: Palette.abyss, location: 1)],
                startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Text(voyage.shipName)
                    .font(.largeTitle.weight(.bold))
                    .tracking(Type.titleTracking)
                    .foregroundStyle(Palette.inkPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let first = voyage.calls.first, let last = voyage.calls.last {
                    Text("\(first.name) → \(last.name)")
                        .font(Type.screenSubtitle)
                        .foregroundStyle(Palette.inkSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)

            // Il credito sta in basso a destra, accanto al nome e non sopra la
            // barra di stato. È la condizione con cui l'autore concede la foto,
            // quindi deve stare **sulla** foto — ma dove non copre il sistema.
            if let credit {
                Text(credit)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Palette.abyss.opacity(0.7)))
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity,
                           alignment: .bottomTrailing)
            }
        }
        .frame(height: min(height, 420))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var backdrop: some View {
        if let photo {
            photo.resizable().aspectRatio(contentMode: .fill)
        } else {
            SeaChart(voyage: voyage, fix: nil, now: now,
                     framing: .wholeVoyage,
                     showsPortNames: false, showsGraticule: true, showsShip: false,
                     padding: 34)
        }
    }
}
