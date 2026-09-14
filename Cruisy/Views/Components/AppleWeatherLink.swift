import SwiftUI
import UIKit

/// Il collegamento a Meteo di Apple, nei giorni in porto.
///
/// Chiesto da Matteo su Figma: in navigazione il meteo che serve è quello del mare —
/// onda, stato del mare — e lo dà Cruisy. In porto la domanda diventa «piove mentre
/// giro?», e lì Meteo di Apple fa meglio di qualunque cosa possa fare l'app.
///
/// **Da verificare su un iPhone vero.** Lo schema `weather://` non è documentato da
/// Apple: si apre l'app, ma non c'è un modo pubblico di passarle il porto. Il pulsante
/// compare solo se iOS dice che lo schema si può aprire — per chiederlo serve
/// `LSApplicationQueriesSchemes` in `Cruisy-Info.plist` — quindi nel caso peggiore non
/// si vede, invece di non fare niente. Sul simulatore l'app Meteo non c'è, e il
/// pulsante non compare mai.
struct AppleWeatherLink: View {
    @Environment(\.openURL) private var openURL

    static let url = URL(string: "weather://")!

    private var isAvailable: Bool { UIApplication.shared.canOpenURL(Self.url) }

    var body: some View {
        if isAvailable {
            Button {
                openURL(Self.url)
            } label: {
                InfoRow(glyph: "cloud.sun.fill", tint: Palette.action,
                        title: String(localized: "Il tempo a terra"),
                        subtitle: String(localized: "Apri Meteo di Apple")) {
                    Disclosure()
                }
            }
            .buttonStyle(.plain)
        }
    }
}
