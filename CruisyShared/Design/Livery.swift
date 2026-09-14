import SwiftUI

/// Quale livrea veste l'app.
///
/// La scelta sta nelle Impostazioni e vale per widget e Live Activity: per questo
/// si scrive anche nel contenitore condiviso, che l'estensione può leggere.
public enum LiveryChoice: String, Codable, Sendable, CaseIterable {
    /// La livrea di Cruisy, sempre.
    case cruisy
    /// I colori ispirati alla compagnia della nave, quando la nave è nell'elenco.
    case company

    public static let key = "cruisy.livery"

    /// Il dominio condiviso con i widget.
    public static var shared: UserDefaults? { UserDefaults(suiteName: VoyageArchive.appGroup) }

    /// La scelta come la vede un altro processo: widget e Live Activity.
    public static func stored() -> LiveryChoice {
        guard let raw = shared?.string(forKey: key), let choice = LiveryChoice(rawValue: raw)
        else { return .company }
        return choice
    }
}

/// I colori dell'app: lo scafo, la carta, il segnale.
///
/// Il linguaggio è quello dei documenti di bordo. Lo **scafo** è il fondo di ogni
/// schermata, blu livrea. La **carta** è il biglietto, bianca, con l'inchiostro del
/// colore dello scafo e i campi in grigio. Il **segnale** è l'arancio dei salvagente
/// e delle scialuppe: si usa **solo** per il rientro a bordo e per i timbri, così
/// quando compare vuol dire qualcosa.
///
/// ## La livrea segue la compagnia
///
/// I colori possono seguire la compagnia della nave, ricavata da
/// `ShipRecord.operatorName`. **Vincolo legale, non estetico** (App Store 5.2.1):
/// sono palette *ispirate* ai colori di una compagnia — mai loghi, caratteri
/// proprietari, motivi grafici riconoscibili, né il nome usato come marchio. Il nome
/// della compagnia compare solo come dato, nella scheda della nave; le livree hanno
/// nomi di colori. Chi preferisce tiene quella di Cruisy dalle Impostazioni.
///
/// ## Contrasto
///
/// Ogni livrea passa `LiveryContrastTests`, che scorre **tutte** le coppie
/// inchiostro/fondo: il testo sullo scafo, sulla carta, e il segnale in entrambe le
/// misure. L'arancio SOLAS puro (`#E4570F`) sul bianco sta a 3,7:1 — abbastanza per
/// un timbro e per un'ora stampata grande, non per un'etichetta piccola. Per quella
/// c'è `signalInk`, più scuro, che supera 4,5:1. Due valori, non uno: il primo è il
/// colore del salvagente, il secondo è quel colore che si legge.
public struct Livery: Identifiable, Equatable, Sendable {

    public let id: String
    /// Un nome di colori, mai di compagnia.
    public let name: String

    /// Lo scafo: il fondo di ogni schermata che mostra una crociera.
    public let hullHex: UInt32
    /// Lo scafo sotto la linea di galleggiamento: barre, fondi delle onde.
    public let hullDeepHex: UInt32
    /// Testo di appoggio sullo scafo.
    public let onHullMutedHex: UInt32
    /// Il segnale visto sullo scafo: la scheda selezionata, un timbro sul blu.
    public let signalOnHullHex: UInt32

    /// L'inchiostro sulla carta. Di norma lo scafo stesso.
    public let inkHex: UInt32
    /// Le etichette dei campi sulla carta.
    public let fieldHex: UInt32
    /// Il biglietto di dietro, nella pila.
    public let paperShadeHex: UInt32

    /// Il segnale come grafica e testo grande: timbri, l'ora stampata, l'anello.
    public let signalHex: UInt32
    /// Il segnale come testo piccolo sulla carta, scurito fino a leggersi.
    public let signalInkHex: UInt32

    public init(id: String, name: String,
                hull: UInt32, hullDeep: UInt32, onHullMuted: UInt32, signalOnHull: UInt32,
                ink: UInt32? = nil, field: UInt32 = 0x5D7389, paperShade: UInt32 = 0xD9E2EA,
                signal: UInt32, signalInk: UInt32) {
        self.id = id
        self.name = name
        self.hullHex = hull
        self.hullDeepHex = hullDeep
        self.onHullMutedHex = onHullMuted
        self.signalOnHullHex = signalOnHull
        self.inkHex = ink ?? hull
        self.fieldHex = field
        self.paperShadeHex = paperShade
        self.signalHex = signal
        self.signalInkHex = signalInk
    }

    // MARK: Costanti della carta

    /// La carta del biglietto, in chiaro. Bianca: è il motivo per cui il biglietto si
    /// legge col sole in banchina.
    public static let paperHex: UInt32 = 0xFFFFFF
    /// La perforazione fra biglietto e matrice, in chiaro.
    public static let perforationHex: UInt32 = 0xB7C4D0
    /// Le righe sottili fra i campi, in chiaro.
    public static let ruleHex: UInt32 = 0xE3E9EE
    /// Il testo sullo scafo.
    public static let onHullHex: UInt32 = 0xFFFFFF
    /// L'inchiostro sulla carta scura.
    public static let darkInkHex: UInt32 = 0xF2F5F8

    // MARK: Le due modalità
    //
    // In chiaro il biglietto è bianco con l'inchiostro dello scafo. In scuro il
    // biglietto è **di carta scura** — il blu della livrea — con l'inchiostro chiaro,
    // e lo scafo attorno si fa quasi nero, così il biglietto resta un cartoncino
    // appoggiato su un fondo. L'arancio del segnale si schiarisce quanto basta a
    // leggersi sulla carta scura. Ogni token ha le due varianti, e i `Color` esposti
    // le portano entrambe: sceglie SwiftUI, con l'ambiente.
    //
    // Le varianti scure si **ricavano** da quelle chiare, con il contrasto come
    // vincolo e non come speranza: `lightened(_:toContrast:over:)` schiarisce finché
    // la soglia WCAG è superata. Così una livrea nuova va bene in scuro senza che
    // nessuno debba scegliere altri otto colori a mano — e i test lo verificano.

    public enum Scheme: Sendable, CaseIterable { case light, dark }

    /// Un token nelle due modalità.
    public struct Pair: Equatable, Sendable {
        public let light: UInt32
        public let dark: UInt32
        public func hex(_ scheme: Scheme) -> UInt32 { scheme == .light ? light : dark }
        var color: Color { Color(light: light, dark: dark) }
    }

    /// La carta scura: lo scafo appena schiarito, e poi scurito quanto basta perché
    /// l'inchiostro chiaro ci stia a 7:1 — serve per le livree con lo scafo chiaro,
    /// come un rosso mattone. Lo scafo scuro si ricava **da lei**, molto più scuro:
    /// un biglietto dello stesso colore dello scafo non si staccherebbe dal fondo, e
    /// il test pretende almeno 1,4:1 fra carta e scafo.
    public var darkPaperHex: UInt32 {
        Self.darkened(Self.mix(hullHex, 0xFFFFFF, 0.10), toContrast: 7, forInk: Self.darkInkHex)
    }

    public var hullPair: Pair { Pair(light: hullHex, dark: Self.mix(darkPaperHex, 0x000000, 0.8)) }
    public var hullDeepPair: Pair { Pair(light: hullDeepHex, dark: Self.mix(darkPaperHex, 0x000000, 0.88)) }
    public var onHullPair: Pair { Pair(light: Self.onHullHex, dark: Self.onHullHex) }
    public var onHullMutedPair: Pair { Pair(light: onHullMutedHex, dark: onHullMutedHex) }
    public var signalOnHullPair: Pair { Pair(light: signalOnHullHex, dark: signalOnHullHex) }
    /// In scuro la carta è lo scafo della livrea, appena schiarito.
    public var paperPair: Pair { Pair(light: Self.paperHex, dark: darkPaperHex) }
    public var paperShadePair: Pair {
        Pair(light: paperShadeHex, dark: Self.mix(darkPaperHex, hullPair.dark, 0.5))
    }
    public var inkPair: Pair { Pair(light: inkHex, dark: Self.darkInkHex) }
    public var fieldPair: Pair {
        Pair(light: fieldHex,
             dark: Self.lightened(onHullMutedHex, toContrast: Contrast.bodyMinimum, over: darkPaperHex))
    }
    public var perforationPair: Pair {
        Pair(light: Self.perforationHex, dark: Self.mix(darkPaperHex, 0xFFFFFF, 0.35))
    }
    public var rulePair: Pair { Pair(light: Self.ruleHex, dark: Self.mix(darkPaperHex, 0xFFFFFF, 0.14)) }
    public var signalPair: Pair {
        Pair(light: signalHex,
             dark: Self.lightened(signalOnHullHex, toContrast: Contrast.largeTextMinimum, over: darkPaperHex))
    }
    public var signalInkPair: Pair {
        Pair(light: signalInkHex,
             dark: Self.lightened(signalOnHullHex, toContrast: Contrast.bodyMinimum, over: darkPaperHex))
    }
    /// La tinta dei controlli di sistema: lo scafo sui fondi chiari di un `Form`;
    /// sui fondi scuri lo stesso colore reso **vivo** — stessa tinta, più chiaro e
    /// saturo — e poi schiarito finché si legge sul nero. Schiarire il blu navy
    /// verso il bianco dava un grigio spento, e i pulsanti sembravano disabilitati.
    public var tintPair: Pair {
        Pair(light: inkHex,
             dark: Self.lightened(Self.vivid(hullHex), toContrast: Contrast.bodyMinimum, over: 0x000000))
    }

    // MARK: Colori

    public var hull: Color { hullPair.color }
    public var hullDeep: Color { hullDeepPair.color }
    public var onHull: Color { onHullPair.color }
    public var onHullMuted: Color { onHullMutedPair.color }
    public var signalOnHull: Color { signalOnHullPair.color }
    public var paper: Color { paperPair.color }
    public var paperShade: Color { paperShadePair.color }
    public var ink: Color { inkPair.color }
    public var field: Color { fieldPair.color }
    public var perforation: Color { perforationPair.color }
    public var rule: Color { rulePair.color }
    public var signal: Color { signalPair.color }
    public var signalInk: Color { signalInkPair.color }
    public var tint: Color { tintPair.color }

    /// Una linea sottile sullo scafo, per separare senza pesare.
    public var hullHairline: Color { onHull.opacity(0.14) }

    // MARK: Aritmetica dei colori

    /// Lo stesso colore, acceso: stessa tinta, luminosità alta e saturazione piena.
    /// È come si porta uno scafo scuro a fare da accento su un fondo nero.
    public static func vivid(_ hex: UInt32) -> UInt32 {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(Color(hex: hex)).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let lifted = UIColor(hue: hue, saturation: max(0.62, min(saturation, 0.8)), brightness: 0.86, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        lifted.getRed(&r, green: &g, blue: &b, alpha: &alpha)
        return (UInt32((r * 255).rounded()) << 16) | (UInt32((g * 255).rounded()) << 8) | UInt32((b * 255).rounded())
    }

    /// `a` mescolato con `b` per la quota `t`, nello spazio sRGB.
    public static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 255), y = Double((b >> shift) & 255)
            return UInt32((x + (y - x) * min(max(t, 0), 1)).rounded())
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }

    /// Il colore scurito verso il nero, a passi del 2%, finché un inchiostro dato ci
    /// sta sopra con il contrasto voluto. Se già ci sta, torna com'è.
    public static func darkened(_ hex: UInt32, toContrast target: Double, forInk ink: UInt32) -> UInt32 {
        let inkRGB = Contrast.RGB(hex: ink)
        var current = hex
        var step = 0
        while Contrast.ratio(inkRGB, Contrast.RGB(hex: current)) < target, step < 50 {
            step += 1
            current = mix(hex, 0x000000, Double(step) * 0.02)
        }
        return current
    }

    /// Il colore schiarito verso il bianco, a passi del 2%, finché il contrasto sul
    /// fondo supera la soglia. Se già la supera, torna com'è.
    public static func lightened(_ hex: UInt32, toContrast target: Double, over background: UInt32) -> UInt32 {
        let base = Contrast.RGB(hex: background)
        var current = hex
        var step = 0
        while Contrast.ratio(Contrast.RGB(hex: current), base) < target, step < 50 {
            step += 1
            current = mix(hex, 0xFFFFFF, Double(step) * 0.02)
        }
        return current
    }

    // MARK: Il catalogo

    /// La livrea di serie: blu livrea, carta bianca, arancio SOLAS.
    public static let cruisy = Livery(
        id: "cruisy", name: "Cruisy",
        hull: 0x0E2A47, hullDeep: 0x0A2039, onHullMuted: 0x9FB6CC, signalOnHull: 0xFF7A33,
        signal: 0xE4570F, signalInk: 0xBF4708)

    /// Le livree ispirate alle compagnie, con la parola che le aggancia al nome
    /// dell'armatore. Le parole si confrontano sul nome **ripiegato** — vedi
    /// `ShipDirectory.fold` — quindi senza accenti né maiuscole.
    static let companies: [(keyword: String, livery: Livery)] = [
        ("msc", Livery(
            id: "oltremare", name: "Blu oltremare",
            hull: 0x0B2C6E, hullDeep: 0x081F50, onHullMuted: 0xA9BCE0, signalOnHull: 0xFF7A33,
            signal: 0xE4570F, signalInk: 0xBF4708)),
        ("explora", Livery(
            id: "notte-oro", name: "Blu notte e oro",
            hull: 0x0E1B33, hullDeep: 0x0A1326, onHullMuted: 0xA8B3C7, signalOnHull: 0xE0BE6A,
            field: 0x62697A, paperShade: 0xDCDFE6,
            signal: 0xA8862E, signalInk: 0x7D6320)),
        ("virgin", Livery(
            id: "rosso", name: "Rosso",
            hull: 0x7A1024, hullDeep: 0x5C0C1B, onHullMuted: 0xE6B7BE, signalOnHull: 0xFFB3BD,
            field: 0x7A5C61, paperShade: 0xEBDCDE,
            signal: 0xC8102E, signalInk: 0xB00E28)),
        ("costa", Livery(
            id: "blu-giallo", name: "Blu e giallo",
            hull: 0x0A3D7A, hullDeep: 0x082C59, onHullMuted: 0xA9C4E6, signalOnHull: 0xF2C64B,
            signal: 0xB88600, signalInk: 0x8A6400)),
        ("royal caribbean", Livery(
            id: "navy-oro", name: "Navy e oro",
            hull: 0x0A2A5E, hullDeep: 0x071E44, onHullMuted: 0xA5B7D6, signalOnHull: 0xE0BE6A,
            signal: 0xA8862E, signalInk: 0x7D6320)),
        ("celebrity", Livery(
            id: "navy-bronzo", name: "Navy e bronzo",
            hull: 0x0F1F3D, hullDeep: 0x0A162C, onHullMuted: 0xA8B3C7, signalOnHull: 0xE0BE6A,
            signal: 0xA8862E, signalInk: 0x7D6320)),
        ("carnival", Livery(
            id: "blu-rosso", name: "Blu e rosso",
            hull: 0x0B2E6B, hullDeep: 0x08214E, onHullMuted: 0xA9BCE0, signalOnHull: 0xFF8A94,
            signal: 0xD22630, signalInk: 0xB81F28)),
        ("norwegian", Livery(
            id: "azzurro", name: "Blu azzurro",
            hull: 0x0C3B8C, hullDeep: 0x092B66, onHullMuted: 0xAAC3EA, signalOnHull: 0xFFA06A,
            signal: 0xE4570F, signalInk: 0xBF4708)),
        ("princess", Livery(
            id: "blu-profondo", name: "Blu profondo",
            hull: 0x0E2A5C, hullDeep: 0x0A1E43, onHullMuted: 0xA5B7D6, signalOnHull: 0x7FC4F2,
            signal: 0x0B6EA8, signalInk: 0x0B6EA8)),
        ("holland america", Livery(
            id: "navy-azzurro", name: "Navy e azzurro",
            hull: 0x10284A, hullDeep: 0x0B1C35, onHullMuted: 0xA5B7D6, signalOnHull: 0x7FC4F2,
            signal: 0x1F6FB2, signalInk: 0x1F6FB2)),
        ("disney", Livery(
            id: "blu-rosso-scuro", name: "Blu scuro e rosso",
            hull: 0x0E2757, hullDeep: 0x0A1B3F, onHullMuted: 0xA5B7D6, signalOnHull: 0xFF8A94,
            signal: 0xC8102E, signalInk: 0xB00E28)),
        ("aida", Livery(
            id: "blu-rosso-vivo", name: "Blu e rosso vivo",
            hull: 0x123C7E, hullDeep: 0x0D2B5B, onHullMuted: 0xAAC3EA, signalOnHull: 0xFF8A94,
            signal: 0xD22630, signalInk: 0xB81F28)),
        ("cunard", Livery(
            id: "rosso-oro", name: "Rosso e oro",
            hull: 0x8B1D2C, hullDeep: 0x681521, onHullMuted: 0xEBBFC5, signalOnHull: 0xE0BE6A,
            field: 0x7A5C61, paperShade: 0xEBDCDE,
            signal: 0xA8862E, signalInk: 0x7D6320)),
        ("tui", Livery(
            id: "blu-rosso-tui", name: "Blu e rosso",
            hull: 0x0B3F8F, hullDeep: 0x082E69, onHullMuted: 0xAAC3EA, signalOnHull: 0xFFA8B0,
            signal: 0xD40E14, signalInk: 0xB40C11)),
        ("viking", Livery(
            id: "rosso-mattone", name: "Rosso mattone",
            hull: 0xA22E2A, hullDeep: 0x7E221F, onHullMuted: 0xF3C9C6, signalOnHull: 0xFFD3CF,
            field: 0x7A5C5A, paperShade: 0xEBDDDC,
            signal: 0x9E2A2A, signalInk: 0x9E2A2A)),
        ("ponant", Livery(
            id: "navy-azzurro-ponant", name: "Navy e azzurro",
            hull: 0x0D1F3C, hullDeep: 0x09162B, onHullMuted: 0xA8B3C7, signalOnHull: 0x7FC4F2,
            signal: 0x0B6EA8, signalInk: 0x0B6EA8)),
        ("hurtigruten", Livery(
            id: "navy-rosso", name: "Navy e rosso",
            hull: 0x0E2A47, hullDeep: 0x0A2039, onHullMuted: 0x9FB6CC, signalOnHull: 0xFF8A94,
            signal: 0xD22630, signalInk: 0xB81F28)),
    ]

    /// Tutte le livree, per i test di contrasto e per le anteprime.
    public static var all: [Livery] { [cruisy] + companies.map(\.livery) }

    /// La livrea ispirata a un armatore, se ne esiste una; se no quella di Cruisy.
    public static func forOperator(_ operatorName: String?) -> Livery {
        guard let operatorName, !operatorName.isEmpty else { return cruisy }
        let folded = ShipDirectory.fold(operatorName)
        return companies.first { folded.contains($0.keyword) }?.livery ?? cruisy
    }

    /// La livrea da vestire, data la scelta dell'utente e la nave.
    public static func resolve(_ choice: LiveryChoice, operatorName: String?) -> Livery {
        switch choice {
        case .cruisy: cruisy
        case .company: forOperator(operatorName)
        }
    }
}

// MARK: - Nell'ambiente

private struct LiveryKey: EnvironmentKey {
    static let defaultValue: Livery = .cruisy
}

public extension EnvironmentValues {
    /// La livrea in vigore. La imposta la radice dell'app; ogni vista la legge.
    var livery: Livery {
        get { self[LiveryKey.self] }
        set { self[LiveryKey.self] = newValue }
    }
}

public extension Color {
    /// Da esadecimale a 24 bit in spazio sRGB.
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Un colore con le due varianti: sceglie il sistema, secondo l'aspetto in vigore
    /// dove la vista è disegnata — compreso un `.colorScheme` forzato a mano.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }
}
