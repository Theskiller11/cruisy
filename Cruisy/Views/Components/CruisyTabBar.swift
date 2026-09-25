import SwiftUI

/// La barra delle schede di Cruisy: quattro voci in una capsula di vetro che,
/// scorrendo verso il basso, **si rimpicciolisce** invece di sparire.
///
/// La barra di sistema di iOS 26, con `.onScrollDown`, si riduce a una sola icona:
/// quella della scheda in cui sei. Per cambiare scheda bisogna prima riaprirla, e
/// le altre tre spariscono proprio quando si sta guardando altro. Qui, come nelle
/// app di messaggi e di foto, la capsula si stringe e perde le etichette, ma le
/// quattro icone restano lì, a un tocco.
///
/// Costa la barra nativa, quindi quello che lei dava gratis va rifatto: il tratto
/// di scheda per VoiceOver, il visore dei contenuti grandi a pressione lunga, il
/// limite al corpo del testo, Riduci movimento.
struct CruisyTabBar<Section: Hashable>: View {
    struct Item: Identifiable {
        let section: Section
        let title: LocalizedStringKey
        let symbol: String
        var id: Section { section }
    }

    @Environment(\.livery) private var livery
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: Section
    let items: [Item]
    let compact: Bool
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                button(for: item)
            }
        }
        .padding(compact ? 4 : 5)
        .frame(maxWidth: compact ? TabBarMetrics.compactWidth : .infinity)
        .glassEffect(.regular.tint(livery.hull.opacity(0.6)).interactive(), in: .capsule)
        // La barra sta sempre sullo scafo, scuro in entrambe le modalità: il vetro
        // si tiene scuro, così le scritte restano bianche.
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, compact ? 0 : 18)
        .animation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.82),
                   value: compact)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isTabBar)
        .accessibilityIdentifier("barra-schede")
    }

    private func button(for item: Item) -> some View {
        let selected = item.section == selection
        return Button {
            selection = item.section
        } label: {
            VStack(spacing: compact ? 0 : 2) {
                Image(systemName: item.symbol)
                    .font(.system(size: compact ? 17 : 20, weight: .semibold))
                    .symbolVariant(selected ? .fill : .none)
                    .frame(height: compact ? 22 : 26)
                if !compact {
                    Text(item.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .top)))
                }
            }
            .foregroundStyle(selected ? livery.signalOnHull : livery.onHull)
            .frame(maxWidth: .infinity)
            .frame(height: compact ? TabBarMetrics.compactHeight - 8 : TabBarMetrics.height - 10)
            .background {
                if selected {
                    Capsule()
                        .fill(.white.opacity(0.1))
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        // Le etichette piccole non crescono oltre un limite, come nella barra di
        // sistema: a chi ha il testo grande la pressione lunga mostra la voce in
        // grande, al centro dello schermo.
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityShowsLargeContentViewer {
            Label(item.title, systemImage: item.symbol)
        }
        .accessibilityLabel(Text(item.title))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

enum TabBarMetrics {
    /// L'altezza della barra aperta: è anche lo spazio che le schede lasciano in
    /// fondo, così l'ultima card non ci finisce sotto.
    static let height: CGFloat = 62
    static let compactHeight: CGFloat = 46
    static let compactWidth: CGFloat = 232
}

/// Lo stato della barra, condiviso fra chi scorre e chi la disegna.
///
/// Non è uno stato di una schermata: la barra è una sola e le schermate che
/// scorrono sono tante, anche dentro una navigazione. Chi scorre lo scrive
/// (`shrinksTabBar()`), la barra lo legge.
@MainActor
@Observable
final class TabBarState {
    private(set) var isCompact = false
    /// Le schermate che vogliono la barra nascosta, come la carta: ci si toglie
    /// ognuna da sé, quindi due che si accavallano non si pestano i piedi.
    private var hiders: Set<UUID> = []
    var isHidden: Bool { !hiders.isEmpty }

    /// Quanto bisogna scorrere nella stessa direzione prima che la barra cambi:
    /// sotto questa soglia un dito che trema la farebbe pulsare.
    private static let travel: CGFloat = 28
    /// Vicino alla cima la barra è sempre aperta.
    private static let top: CGFloat = 24

    private var run: CGFloat = 0

    func expand() {
        run = 0
        isCompact = false
    }

    func scrolled(from old: CGFloat, to new: CGFloat) {
        guard new > Self.top else {
            expand()
            return
        }
        let delta = new - old
        guard delta != 0 else { return }
        // Si accumula finché la direzione non cambia.
        if (delta > 0) != (run > 0) { run = 0 }
        run += delta
        if run > Self.travel, !isCompact { isCompact = true }
        if run < -Self.travel, isCompact { isCompact = false }
    }

    func hide(_ id: UUID) { hiders.insert(id) }
    func show(_ id: UUID) { hiders.remove(id) }
}

extension View {
    /// Rimpicciolisce la barra delle schede quando si scorre verso il basso e la
    /// riapre quando si torna su.
    func shrinksTabBar() -> some View { modifier(ShrinksTabBar()) }

    /// Nasconde la barra delle schede finché questa schermata è a video.
    func hidesTabBar() -> some View { modifier(HidesTabBar()) }
}

private struct ShrinksTabBar: ViewModifier {
    @Environment(TabBarState.self) private var bar: TabBarState?

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geometry in
            // Lo scostamento **dentro** i limiti: il rimbalzo in fondo farebbe
            // tornare indietro il contenuto, e la barra si riaprirebbe da sola
            // proprio quando sei arrivato alla fine.
            let bottom = geometry.contentSize.height + geometry.contentInsets.bottom
                - geometry.containerSize.height
            let offset = geometry.contentOffset.y + geometry.contentInsets.top
            return min(max(offset, 0), max(bottom + geometry.contentInsets.top, 0))
        } action: { old, new in
            bar?.scrolled(from: old, to: new)
        }
    }
}

private struct HidesTabBar: ViewModifier {
    @Environment(TabBarState.self) private var bar: TabBarState?
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear { bar?.hide(id) }
            .onDisappear { bar?.show(id) }
    }
}
