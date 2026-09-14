import SwiftUI

@main
struct CruisyApp: App {
    @State private var store = VoyageStore()
    @State private var position = PositionService()
    @State private var notifications = NotificationScheduler()
    @State private var activities = LiveActivityController()
    @State private var reachability = Reachability()
    @State private var weather = MarineWeatherService()
    @State private var shipLookup = ShipLookupService()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                // Le navi imparate a bordo valgono quanto quelle impacchettate,
                // ma vanno rilette da disco prima che qualcuno le cerchi.
                .task { ShipDirectory.shared.loadLearned() }
                .environment(store)
                .environment(position)
                .environment(notifications)
                .environment(activities)
                .environment(reachability)
                .environment(weather)
                .environment(shipLookup)
                // L'app si legge in coperta di notte e in banchina di giorno:
                // il tema scuro non è una preferenza, è il progetto.
                .preferredColorScheme(.dark)
        }
    }
}
