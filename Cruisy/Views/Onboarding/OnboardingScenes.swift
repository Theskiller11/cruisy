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

    private func expanded(left: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                Image(systemName: "figure.walk.departure")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(livery.signalOnHull)
                Spacer()
                VStack(alignment: .trailing, spacing: -1) {
                    Text(verbatim: "17:30")
                        .font(.system(size: 15, weight: .black).width(.compressed))
                        .foregroundStyle(.white)
                    Text("ora di bordo")
                        .font(.system(size: 8))
                        .foregroundStyle(livery.onHullMuted)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: "PUERTO PLATA")
                .font(.system(size: 12, weight: .bold).width(.condensed))
                .foregroundStyle(.white)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                countdown(left, size: 26)
                    .foregroundStyle(.white)
                Text("al tutti a bordo")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(livery.onHullMuted)
                Spacer(minLength: 0)
            }
            ProgressView(value: progress(left))
                .tint(livery.signalOnHull)
                .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.top, 13)
        .padding(.bottom, 15)
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

    private func countdown(_ left: TimeInterval, size: CGFloat) -> some View {
        let s = Int(left)
        return Text(verbatim: String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60))
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
/// nave. Tutto sta in un `Canvas` guidato dal tempo — un `Canvas` non anima niente
/// da solo, e posizione, velocità, schiuma e beccheggio sono funzioni dello stesso
/// istante. Scafo e ponti bianchi, la fascia e il fumaiolo nel colore della livrea,
/// le scialuppe nell'arancio delle scialuppe vere. Nessun marchio.
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
                drawFoam(in: &ship, speed: speed, time: time)
                drawShip(in: &ship)
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

    /// L'onda di prua e la scia: bianche, e tanto più lunghe quanto più la nave corre.
    private func drawFoam(in canvas: inout GraphicsContext, speed: CGFloat, time: TimeInterval) {
        guard speed > 0.02 else { return }
        let foam = Color.white.opacity(Double(0.75 * speed))
        // La scia: strisce che si allungano dietro la poppa e tremano con l'onda.
        for row in 0..<3 {
            let y = CGFloat(row) * 3 + 2
            let length = (60 + CGFloat(row) * 26) * speed
            let wobble = CGFloat(sin(time * 6 + Double(row))) * 2
            var streak = Path()
            streak.addRoundedRect(in: CGRect(x: -84 - length + wobble, y: y, width: length, height: 1.8),
                                  cornerSize: CGSize(width: 1, height: 1))
            canvas.fill(streak, with: .color(.white.opacity(Double(0.6 * speed) / Double(row + 1))))
        }
        // L'onda di prua: un ventaglio d'acqua davanti al tagliamare.
        var bow = Path()
        bow.move(to: CGPoint(x: 70, y: 6))
        bow.addQuadCurve(to: CGPoint(x: 70 + 20 * speed, y: 8),
                         control: CGPoint(x: 80 + 10 * speed, y: -6 * speed))
        bow.addQuadCurve(to: CGPoint(x: 70, y: 10), control: CGPoint(x: 78, y: 10))
        bow.closeSubpath()
        canvas.fill(bow, with: .color(foam))
    }

    /// La nave, di profilo, con la prua a destra e la linea di galleggiamento a y = 0.
    private func drawShip(in canvas: inout GraphicsContext) {
        let white = Color(hex: 0xF4F6F9)
        let band = Color(hex: livery.hullHex)
        let glass = Color(hex: livery.hullDeepHex)
        let lifeboat = Color(hex: 0xF26A1B)

        // Lo scafo: la cimosa sale verso la prua, il dritto di prua è slanciato.
        var hull = Path()
        hull.move(to: CGPoint(x: -84, y: -4))
        hull.addLine(to: CGPoint(x: 76, y: -9))
        hull.addQuadCurve(to: CGPoint(x: 64, y: 12), control: CGPoint(x: 88, y: 2))
        hull.addLine(to: CGPoint(x: -78, y: 12))
        hull.addQuadCurve(to: CGPoint(x: -84, y: -4), control: CGPoint(x: -87, y: 6))
        hull.closeSubpath()
        canvas.fill(hull, with: .color(white))

        // La fascia sulla linea di galleggiamento, nel colore della livrea.
        var boot = canvas
        boot.clip(to: hull)
        boot.fill(Path(CGRect(x: -90, y: 2, width: 180, height: 12)), with: .color(band))
        var stripe = Path()
        stripe.move(to: CGPoint(x: -80, y: -1))
        stripe.addLine(to: CGPoint(x: 72, y: -5.5))
        boot.stroke(stripe, with: .color(band), lineWidth: 1.2)

        // I ponti: rastremati verso poppa, con la fronte inclinata.
        func deck(_ x0: CGFloat, _ x1: CGFloat, _ top: CGFloat, _ bottom: CGFloat, rake: CGFloat) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: x0, y: bottom))
            path.addLine(to: CGPoint(x: x0, y: top))
            path.addLine(to: CGPoint(x: x1 - rake, y: top))
            path.addLine(to: CGPoint(x: x1, y: bottom))
            path.closeSubpath()
            return path
        }
        canvas.fill(deck(-74, 64, -18, -3, rake: 6), with: .color(white))
        canvas.fill(deck(-66, 54, -27, -17, rake: 7), with: .color(white))
        canvas.fill(deck(-54, 40, -35, -26, rake: 6), with: .color(white))
        canvas.fill(deck(-8, 34, -42, -34, rake: 5), with: .color(white))

        // Le finestre: file di punti scuri, una per ponte, due sul più lungo.
        var windows = Path()
        for (y, from, to) in [(-15.5, -68.0, 56.0), (-10.5, -70.0, 60.0), (-24.0, -60.0, 46.0), (-32.5, -48.0, 33.0)] as [(CGFloat, CGFloat, CGFloat)] {
            var x = from
            while x < to {
                windows.addRect(CGRect(x: x, y: y, width: 3, height: 2.2))
                x += 5.5
            }
        }
        windows.addRoundedRect(in: CGRect(x: 0, y: -40.5, width: 27, height: 3),
                               cornerSize: CGSize(width: 1, height: 1))
        canvas.fill(windows, with: .color(glass.opacity(0.75)))

        // Le scialuppe, appese lungo il fianco.
        var boats = Path()
        var bx: CGFloat = -50
        while bx < 34 {
            boats.addRoundedRect(in: CGRect(x: bx, y: -21, width: 10, height: 4.2),
                                 cornerSize: CGSize(width: 2.1, height: 2.1))
            bx += 13
        }
        canvas.fill(boats, with: .color(lifeboat))

        // Il fumaiolo, inclinato all'indietro: bianco, con la fascia della livrea e
        // il segnale in cima. Pieno nel colore della livrea spariva: sullo scafo
        // della schermata, che è dello stesso blu, restava a mezz'aria solo la cima.
        var funnel = Path()
        funnel.move(to: CGPoint(x: -46, y: -34))
        funnel.addLine(to: CGPoint(x: -31, y: -34))
        funnel.addLine(to: CGPoint(x: -35, y: -52))
        funnel.addLine(to: CGPoint(x: -50, y: -52))
        funnel.closeSubpath()
        canvas.fill(funnel, with: .color(white))
        var marks = canvas
        marks.clip(to: funnel)
        marks.fill(Path(CGRect(x: -52, y: -46, width: 24, height: 5)), with: .color(band))
        marks.fill(Path(CGRect(x: -52, y: -52, width: 24, height: 3)),
                   with: .color(Color(hex: livery.signalOnHullHex)))

        // L'albero sopra la plancia, con la cupola del radar.
        var mast = Path()
        mast.move(to: CGPoint(x: 20, y: -42))
        mast.addLine(to: CGPoint(x: 19, y: -53))
        canvas.stroke(mast, with: .color(white), lineWidth: 1.4)
        canvas.fill(Path(ellipseIn: CGRect(x: 15.5, y: -58, width: 7, height: 7)), with: .color(white))
    }
}
