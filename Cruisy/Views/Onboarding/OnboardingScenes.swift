import SwiftUI

// Le due scene animate dell'onboarding: la Live Activity su un iPhone in
// miniatura, e la nave scelta che arriva in scena.

// MARK: - La Live Activity, come la si vedrà

/// Un iPhone in miniatura con la schermata di blocco e la Dynamic Island.
///
/// Il primo tentativo era una pillola nera con due parole dentro, e sembrava finto:
/// la Dynamic Island è riconoscibile per come **si muove**, non per il colore. Qui
/// fa quello che fa sul telefono: parte chiusa, si allarga nella forma compatta —
/// glifo a sinistra della fotocamera, conto alla rovescia a destra — e poi si apre
/// nella forma espansa. Il contenuto ricalca `AllAboardLiveActivity` regione per
/// regione, e la schermata di blocco ricalca la sua matrice: quello che si vede qui
/// è quello che arriverà. Toccandola si apre e si chiude, come col dito sull'isola
/// vera.
///
/// Lo sfondo è `SeaScene`: la carta da parati è il mare dell'app.
struct LiveActivityDemo: View {
    @Environment(\.livery) private var livery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Island { case idle, compact, expanded }

    @State private var island: Island = .idle
    @State private var start = Date.now
    /// Dopo il primo tocco la sequenza automatica si ferma: comanda il dito.
    @State private var userTookOver = false
    @State private var taps = 0

    /// 2:59:52 al rientro, come nel biglietto di Puerto Plata degli esempi.
    private let total: TimeInterval = 2 * 3600 + 59 * 60 + 52
    /// In porto l'attività si accende nelle ultime otto ore: la barra parte da lì.
    private let window: TimeInterval = 8 * 3600

    /// La molla dell'isola. Il resto dell'app non rimbalza, ma l'isola vera sì, e
    /// una che si allarga smorzata sembra un'altra cosa.
    private static let islandSpring = Animation.spring(response: 0.42, dampingFraction: 0.68)

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.periodic(from: start, by: 1)) { context in
                phone(left: max(0, total - context.date.timeIntervalSince(start)))
            }
            Text("Tocca l'isola per aprirla e chiuderla.")
                .font(.caption)
                .foregroundStyle(livery.onHullMuted)
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
        .task { await play() }
    }

    private func phone(left: TimeInterval) -> some View {
        ZStack(alignment: .top) {
            // Il cielo è di un'ora e mezza più tardi dell'orologio: alle 14:30 il sole
            // sta alto al centro, dietro le cifre; alle 16 scende a destra e le lascia
            // libere. Nessuno misura l'angolo del sole su una miniatura.
            SeaScene(hour: 16)

            VStack(spacing: 0) {
                Text("Sabato 17 ottobre")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.top, 50)
                Text(verbatim: "14:30")
                    .font(.system(size: 66, weight: .semibold).width(.condensed))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
                Spacer(minLength: 0)
                if island != .idle {
                    lockCard(left: left)
                        .padding(10)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }

            islandView(left: left)
                .padding(.top, 10)
        }
        .frame(width: 300, height: 380)
        .clipShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 46, style: .continuous)
            .strokeBorder(Color.black, lineWidth: 7))
        .contentShape(RoundedRectangle(cornerRadius: 46, style: .continuous))
        .onTapGesture { toggle() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Esempio: la schermata di blocco e la Dynamic Island con il countdown del rientro a bordo."))
        .accessibilityAction(named: Text("Apri o chiudi l'isola")) { toggle() }
    }

    // MARK: L'isola

    private func islandView(left: TimeInterval) -> some View {
        let size: CGSize = switch island {
        case .idle: CGSize(width: 96, height: 28)
        case .compact: CGSize(width: 204, height: 28)
        case .expanded: CGSize(width: 272, height: 132)
        }
        return ZStack {
            RoundedRectangle(cornerRadius: island == .expanded ? 38 : 14, style: .continuous)
                .fill(.black)
            switch island {
            case .idle:
                EmptyView()
            case .compact:
                compact(left: left)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            case .expanded:
                expanded(left: left)
                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .top)))
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Le due fessure accanto alla fotocamera: il glifo e le cifre, nient'altro.
    private func compact(left: TimeInterval) -> some View {
        HStack {
            Image(systemName: "figure.walk.departure")
                .font(.system(size: 12, weight: .semibold))
            Spacer(minLength: 0)
            countdown(left, size: 13)
        }
        .foregroundStyle(livery.signalOnHull)
        .padding(.horizontal, 13)
    }

    /// Come la regione espansa vera: a sinistra che cosa e dove, a destra quanto
    /// manca, sotto la barra e il traguardo in ora di bordo.
    private func expanded(left: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.walk.departure")
                        Text("Rientro a bordo")
                            .textCase(.uppercase)
                            .tracking(0.6)
                    }
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(livery.signalOnHull)
                    Text(verbatim: "PUERTO PLATA")
                        .font(.system(size: 15, weight: .heavy).width(.condensed))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 0) {
                    countdown(left, size: 27)
                        .foregroundStyle(.white)
                    Text("al tutti a bordo")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(livery.onHullMuted)
                }
            }
            Spacer(minLength: 0)
            ProgressView(value: progress(left))
                .tint(livery.signalOnHull)
            Text("Entro le 17:30 · ora di bordo")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 18)
        .padding(.top, 13)
        .padding(.bottom, 14)
    }

    // MARK: La schermata di blocco

    /// La matrice del biglietto, come la disegna `LockScreenView` nel widget.
    private func lockCard(left: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Rientro a bordo · Puerto Plata")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1)
                    .textCase(.uppercase)
                    .lineLimit(1)
            } icon: {
                Image(systemName: "figure.walk.departure")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(livery.signalInk)

            HStack(alignment: .lastTextBaseline) {
                Text(verbatim: "17:30")
                    .font(.system(size: 36, weight: .black).width(.compressed))
                    .foregroundStyle(livery.ink)
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 0) {
                    Text("al tutti a bordo")
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(livery.field)
                    countdown(left, size: 24)
                        .foregroundStyle(livery.ink)
                }
            }

            ProgressView(value: progress(left))
                .tint(livery.signal)
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(livery.paper))
    }

    // MARK: Pezzi

    /// Come `ActivityCountdown` nell'attività vera: ore e minuti sopra l'ora, i
    /// secondi solo nell'ultima.
    private func countdown(_ left: TimeInterval, size: CGFloat) -> some View {
        let s = Int(left)
        let text = s >= 3600
            ? String(format: "%d:%02d", s / 3600, s / 60 % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
        return Text(verbatim: text)
            .font(.system(size: size, weight: .black).width(.condensed))
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            .animation(.snappy, value: s)
    }

    private func progress(_ left: TimeInterval) -> Double {
        min(max((window - left) / window, 0), 1)
    }

    /// Chiusa, poi compatta, poi aperta: la sequenza che si vede in banchina quando
    /// l'attività parte e la si guarda col dito.
    private func play() async {
        if reduceMotion {
            island = .expanded
            return
        }
        try? await Task.sleep(for: .milliseconds(700))
        withAnimation(Self.islandSpring) { island = .compact }
        try? await Task.sleep(for: .milliseconds(1900))
        guard !userTookOver else { return }
        withAnimation(Self.islandSpring) { island = .expanded }
    }

    private func toggle() {
        userTookOver = true
        taps += 1
        withAnimation(reduceMotion ? Motion.reduced : Self.islandSpring) {
            island = island == .expanded ? .compact : .expanded
        }
    }
}

// MARK: - La nave che arriva

/// La nave scelta entra in scena da sinistra, rallenta con l'onda di prua e la
/// scia che si spengono, e resta a beccheggiare. Con «Cambia» se ne va a destra.
///
/// È disegnata e non un simbolo: `ferry.fill` che rimbalza era un'icona, non una
/// nave. La nave è `CruiseShipDrawing`, la stessa della scena del giorno di mare;
/// tutto sta in un `Canvas` guidato dal tempo — un `Canvas` non anima niente da
/// solo, e posizione, velocità, schiuma e beccheggio sono funzioni dello stesso
/// istante.
///
/// Con Riduci movimento la nave compare ferma al centro, e il mare è immobile.
struct ShipArrivalScene: View {
    let ship: ShipRecord?

    @Environment(\.livery) private var livery
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private enum Phase { case empty, arriving, moored, leaving }
    @State private var phase: Phase = .empty
    @State private var since = Date.now

    private static let arrival: TimeInterval = 2.8
    private static let departure: TimeInterval = 1.7

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || scenePhase != .active)) { context in
            let now = context.date
            Canvas { canvas, size in
                draw(in: &canvas, size: size, now: now)
            }
        }
        .frame(height: 150)
        .accessibilityHidden(true)
        .onAppear {
            // Tornando indietro a questo passo la nave è già in porto.
            if ship != nil { phase = .moored }
        }
        .onChange(of: ship?.id) { _, id in
            since = .now
            if id != nil {
                phase = reduceMotion ? .moored : .arriving
            } else {
                phase = reduceMotion ? .empty : .leaving
            }
        }
    }

    // MARK: Il disegno

    private func draw(in canvas: inout GraphicsContext, size: CGSize, now: Date) {
        let time = reduceMotion ? 0 : now.timeIntervalSinceReferenceDate
        let scheme: Livery.Scheme = colorScheme == .dark ? .dark : .light
        let hull = livery.hullPair.hex(scheme)
        let waterline = size.height * 0.64
        let center = size.width * 0.5
        let scale = min(1.2, size.width / 330)
        let drift = CGFloat(sin(time * 0.35)) * 4

        // Dove sta la nave e quanto corre. La velocità va da 0 a 1 e comanda la
        // schiuma: a pieno moto all'ingresso, spenta quando si ferma.
        var x: CGFloat?
        var speed: CGFloat = 0
        let elapsed = now.timeIntervalSince(since)
        switch phase {
        case .empty:
            break
        case .moored:
            x = center + drift
        case .arriving:
            let p = CGFloat(min(elapsed / Self.arrival, 1))
            let eased = 1 - pow(1 - p, 3)
            x = -120 + (center + 120) * eased + drift * eased
            speed = pow(1 - p, 2)
        case .leaving:
            let p = CGFloat(min(elapsed / Self.departure, 1))
            if p < 1 {
                let eased = p * p * p
                x = center + (size.width + 140 - center) * eased + drift * (1 - eased)
                speed = min(1, p * 1.6)
            }
        }

        let waves: [(offset: CGFloat, amplitude: CGFloat, wavelength: CGFloat, speed: Double, color: UInt32)] = [
            (-6, 3, 160, 0.40, Livery.mix(hull, 0xFFFFFF, 0.22)),
            (5, 4, 118, 0.62, Livery.mix(hull, 0xFFFFFF, 0.11)),
            (17, 5, 92, 0.90, hull),
        ]
        for (index, wave) in waves.enumerated() {
            // La nave sta fra la prima onda e la seconda: la carena nell'acqua.
            if index == 1, let x {
                let bob = CGFloat(sin(time * 1.1)) * 1.6
                // A tutta forza la prua si alza un poco; ferma, beccheggia e basta.
                let pitch = sin(time * 0.8 + 0.5) * 0.016 - Double(speed) * 0.03
                var ship = canvas
                ship.translateBy(x: x, y: waterline + bob)
                ship.rotate(by: .radians(pitch))
                ship.scaleBy(x: scale, y: scale)
                CruiseShipDrawing.draw(in: &ship, band: Color(hex: livery.hullHex),
                                       funnelTop: Color(hex: livery.signalOnHullHex),
                                       lit: false, foam: speed, time: time)
            }
            canvas.fill(wavePath(wave, baseY: waterline + wave.offset, width: size.width,
                                 height: size.height, time: time),
                        with: .color(Color(hex: wave.color)))
        }
    }

    private func wavePath(_ wave: (offset: CGFloat, amplitude: CGFloat, wavelength: CGFloat, speed: Double, color: UInt32),
                          baseY: CGFloat, width: CGFloat, height: CGFloat, time: TimeInterval) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: height))
        path.addLine(to: CGPoint(x: 0, y: baseY))
        var x: CGFloat = 0
        while x <= width + 4 {
            let y = baseY + CGFloat(sin(Double(x) / Double(wave.wavelength) * 2 * .pi + time * wave.speed)) * wave.amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 4
        }
        path.addLine(to: CGPoint(x: width, y: height))
        path.closeSubpath()
        return path
    }
}
