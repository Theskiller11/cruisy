import SwiftUI
import MapKit

/// La stessa rotta, sulle immagini satellitari di Apple.
///
/// È l'unica cosa in tutta l'app che tocca la rete, ed è per questo che non è il
/// default: le tessere si scaricano, e a bordo la connessione non c'è o si paga a
/// peso d'oro. Chi la sceglie la sceglie sapendo cosa fa — e quando la rete manca
/// l'app lo dice, invece di lasciare un rettangolo grigio senza spiegazioni.
///
/// La rotta e i porti vengono dagli stessi `routeSegments` della carta vettoriale:
/// cambia il fondo, non i dati.
struct SatelliteChart: View {
    let voyage: Voyage
    let fix: ShipFix?
    let now: Date
    @Binding var camera: ChartCamera
    /// Spazio da lasciare in basso perché il logo Apple e il collegamento agli avvisi
    /// legali restino visibili sopra la scheda di stato e la barra delle schede.
    ///
    /// Non è un vezzo grafico: usando MapKit quell'attribuzione **deve** restare
    /// leggibile e toccabile, e senza questo margine finiva sotto la barra.
    var bottomInset: CGFloat = 0

    @State private var position: MapCameraPosition = .automatic
    /// L'ultima inquadratura riferita **dalla mappa stessa**.
    ///
    /// Serve a distinguere chi ha mosso cosa. Senza, i pulsanti non funzionavano:
    /// scrivevano nel legame, la mappa non se ne accorgeva perché `position` si
    /// impostava una volta sola alla comparsa — e se si fosse aggiornata a ogni
    /// cambio si sarebbe innescato un rimpallo fra le due, con la mappa che
    /// combatteva contro sé stessa.
    @State private var reportedByMap: ChartCamera?

    private var segments: (sailed: [Coordinate], ahead: [Coordinate]) {
        voyage.routeSegments(at: now, fix: fix)
    }

    var body: some View {
        Map(position: $position) {
            MapPolyline(coordinates: Voyage.greatCirclePath(through: segments.ahead).map(\.location))
                .stroke(Palette.ink.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [3, 6]))

            MapPolyline(coordinates: Voyage.greatCirclePath(through: segments.sailed).map(\.location))
                .stroke(Palette.underway, style: StrokeStyle(lineWidth: 3, lineCap: .round))

            ForEach(voyage.calls) { call in
                Annotation(call.name, coordinate: call.coordinate.location) {
                    PortDot(visited: call.arrival <= now)
                }
                .annotationTitles(.automatic)
            }

            if let fix {
                Annotation("", coordinate: fix.coordinate.location) {
                    ShipMarker(course: fix.course ?? 0)
                }
            }
        }
        // `.imagery` e non `.hybrid`: le etichette stradali di Apple sopra una rotta
        // in mezzo all'oceano non aggiungono niente e affollano.
        .mapStyle(.imagery(elevation: .flat))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .safeAreaPadding(.bottom, bottomInset)
        .onAppear { position = .region(region(from: camera)) }
        // Un comando ha spostato l'inquadratura da fuori: la mappa deve seguirlo.
        // Se invece il cambio arriva dalla mappa, `reportedByMap` combacia e non si
        // fa nulla — è ciò che rompe il rimpallo.
        .onChange(of: camera) { _, wanted in
            guard !matches(wanted, reportedByMap) else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                position = .region(region(from: wanted))
            }
        }
        // Le due carte condividono l'inquadratura: passando da una all'altra si
        // resta dove si stava guardando, invece di ripartire da capo.
        .onMapCameraChange(frequency: .onEnd) { context in
            let span = context.region.span
            let moved = ChartCamera(
                center: Coordinate(latitude: context.region.center.latitude,
                                   longitude: context.region.center.longitude),
                spanDegrees: max(span.longitudeDelta, ChartCamera.minimumSpan))
            reportedByMap = moved
            camera = moved
        }
    }

    /// Due inquadrature abbastanza vicine da considerarle la stessa.
    ///
    /// Il confronto è approssimato di proposito: MapKit non torna mai esattamente
    /// il riquadro che gli si chiede — lo adatta alle proporzioni della vista — e un
    /// confronto esatto farebbe scattare un aggiornamento a ogni assestamento.
    private func matches(_ a: ChartCamera, _ b: ChartCamera?) -> Bool {
        guard let b else { return false }
        let tolerance = max(a.spanDegrees, b.spanDegrees) * 0.02
        return abs(a.center.latitude - b.center.latitude) < tolerance
            && abs(a.center.longitude - b.center.longitude) < tolerance
            && abs(a.spanDegrees - b.spanDegrees) < tolerance
    }

    private func region(from camera: ChartCamera) -> MKCoordinateRegion {
        MKCoordinateRegion(center: camera.center.location,
                           span: MKCoordinateSpan(latitudeDelta: camera.spanDegrees * 0.7,
                                                  longitudeDelta: camera.spanDegrees))
    }
}

/// Il segnaposto di uno scalo, come sulla carta vettoriale.
private struct PortDot: View {
    let visited: Bool

    var body: some View {
        Circle()
            .fill(visited ? Palette.underway : Color(hex: 0x091A28))
            .frame(width: 11, height: 11)
            .overlay(Circle().stroke(visited ? Palette.abyss : Palette.ink.opacity(0.8), lineWidth: 1.6))
            .shadow(color: Palette.abyss.opacity(0.5), radius: 3, y: 1)
    }
}

/// La nave, orientata come la prua.
private struct ShipMarker: View {
    let course: Double

    var body: some View {
        ZStack {
            Circle().fill(Palette.underway.opacity(0.22)).frame(width: 30, height: 30)
            Triangle()
                .fill(Color(hex: 0xEAFAF6))
                .frame(width: 14, height: 18)
                .rotationEffect(.degrees(course))
                .shadow(color: Palette.abyss.opacity(0.6), radius: 2)
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY * 0.78))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

extension Coordinate {
    var location: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
