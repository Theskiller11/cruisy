import Testing
import Foundation
import CoreLocation
@testable import Cruisy

/// Quanto chiedere al GPS: la scelta che decide la batteria in una giornata di mare.
@Suite("Profili del GPS")
struct LocationProfileTests {

    @Test("In tasca si registra col profilo grossolano, a schermo con quello fine")
    func profileFollowsUse() {
        #expect(LocationProfile.profile(isRecording: true, isForeground: false) == .recording)
        #expect(LocationProfile.profile(isRecording: true, isForeground: true) == .foreground)
        #expect(LocationProfile.profile(isRecording: false, isForeground: true) == .foreground)
        #expect(LocationProfile.profile(isRecording: false, isForeground: false) == .foreground)
    }

    @Test("Il filtro della registrazione sta sotto la maglia della traccia")
    func recordingFilterFitsTheTrack() {
        // Sopra la separazione minima si perderebbero punti che la traccia avrebbe
        // tenuto; molto sotto, si sveglierebbe il processo per punti da buttare.
        let separation = Track.minimumSeparation * Geo.metresPerNauticalMile
        #expect(LocationProfile.recording.distanceFilter < separation)
        #expect(LocationProfile.recording.distanceFilter >= separation / 2)
    }

    @Test("La precisione della registrazione è invisibile sulla traccia")
    func recordingAccuracyIsNegligible() {
        // Cento metri contro una maglia di 463: un quinto, che non cambia una rotta.
        let separation = Track.minimumSeparation * Geo.metresPerNauticalMile
        #expect(LocationProfile.recording.accuracy <= separation / 4)
        #expect(LocationProfile.recording.accuracy > LocationProfile.foreground.accuracy)
    }

    @Test("In primo piano resta la precisione della carta")
    func foregroundStaysPrecise() {
        #expect(LocationProfile.foreground.accuracy == kCLLocationAccuracyNearestTenMeters)
        #expect(LocationProfile.foreground.distanceFilter == 50)
    }
}
