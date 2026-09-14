import SwiftUI

/// La carta che si può muovere e ingrandire con le dita.
///
/// I gesti seguono le regole delle interfacce fluide: la carta sta **incollata** al
/// dito per tutta la durata del trascinamento, non solo alla fine; al rilascio il
/// movimento prosegue alla velocità che aveva, senza giunture; ai limiti di zoom
/// resiste progressivamente invece di bloccarsi di colpo; e qualunque animazione in
/// corso si può riafferrare a metà.
///
/// Trascinamento e pizzico sono simultanei e non alternativi: una mano che ingrandisce
/// sposta anche, e costringere a scegliere fra i due si sente subito.
struct InteractiveSeaChart: View {
    let voyage: Voyage
    let fix: ShipFix?
    let now: Date
    @Binding var camera: ChartCamera
    var showsPortNames = true
    var showsGraticule = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// La telecamera all'inizio del gesto: ogni aggiornamento parte da lì, non
    /// dall'ultimo fotogramma, così gli scostamenti non si accumulano alla deriva.
    @State private var anchorCamera: ChartCamera?
    @State private var size: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            SeaChart(voyage: voyage, fix: fix, now: now,
                     framing: .camera(camera),
                     showsPortNames: showsPortNames,
                     showsGraticule: showsGraticule)
                .contentShape(Rectangle())
                .onAppear { size = geometry.size }
                .onChange(of: geometry.size) { _, new in size = new }
                .gesture(pan.simultaneously(with: magnify))
                .onTapGesture(count: 2) { location in zoom(by: 2, at: location) }
                .accessibilityElement()
                .accessibilityLabel(Text("Carta nautica"))
                .accessibilityValue(Text(Format.coordinate(camera.center)))
                .accessibilityAdjustableAction { direction in
                    // Con VoiceOver lo zoom si fa con su/giù, che è il gesto standard
                    // per un valore regolabile.
                    zoom(by: direction == .increment ? 1.6 : 1 / 1.6,
                         at: CGPoint(x: size.width / 2, y: size.height / 2))
                }
        }
    }

    // MARK: Gesti

    private var pan: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let start = anchorCamera ?? camera
                if anchorCamera == nil { anchorCamera = start }
                camera = start.panned(by: value.translation, in: size)
            }
            .onEnded { value in
                let start = anchorCamera ?? camera
                anchorCamera = nil

                // `predictedEndTranslation` è già la proiezione dello slancio: dice
                // dove il gesto **andrà**, non dove è stato lasciato. Usarla invece
                // della traslazione finale è ciò che fa sì che un colpetto lanci la
                // carta invece di fermarla di netto.
                let landing = start.panned(by: value.predictedEndTranslation, in: size).clamped()

                if reduceMotion {
                    camera = start.panned(by: value.translation, in: size).clamped()
                } else {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        camera = landing
                    }
                }
            }
    }

    private var magnify: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                let start = anchorCamera ?? camera
                if anchorCamera == nil { anchorCamera = start }
                let anchor = CGPoint(x: value.startAnchor.x * size.width,
                                     y: value.startAnchor.y * size.height)
                // Durante il gesto si applica solo la resistenza: il limite netto
                // arriva al rilascio, così ai bordi si sente il materiale.
                camera = start.zoomed(by: value.magnification, around: anchor, in: size).resisted()
            }
            .onEnded { _ in
                anchorCamera = nil
                let settled = camera.clamped()
                if reduceMotion {
                    camera = settled
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 1.0)) {
                        camera = settled
                    }
                }
            }
    }

    private func zoom(by factor: Double, at location: CGPoint) {
        let target = camera.zoomed(by: factor, around: location, in: size).clamped()
        if reduceMotion {
            camera = target
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { camera = target }
        }
    }
}
