import SwiftUI

/// Gli inchiostri dei timbri del passaporto.
///
/// **Fissi**, come quelli veri, e non della livrea: un passaporto ha timbri blu,
/// rossi, verdi e viola perché ogni porto ha il suo tampone, e una pagina tutta
/// nel colore della compagnia sembrerebbe un volantino. Ogni porto prende sempre
/// lo stesso inchiostro e la stessa forma, così lo si riconosce da una pagina
/// all'altra.
///
/// In chiaro sono scuri abbastanza da leggersi sulla carta bianca; in scuro si
/// schiariscono finché non si leggono sulla carta scura della livrea — la stessa
/// regola del segnale, e lo stesso test.
public enum StampInk: CaseIterable, Sendable {
    case blue, red, green, violet

    var lightHex: UInt32 {
        switch self {
        case .blue: 0x2F5DA8
        case .red: 0xB83A26
        case .green: 0x2A7454
        case .violet: 0x6B4FA0
        }
    }

    /// L'inchiostro di un porto: sempre lo stesso, per nome.
    public static func of(_ name: String) -> StampInk {
        allCases[StampStyle.seed(name) % allCases.count]
    }
}

/// La forma del timbro di un porto.
public enum StampStyle: CaseIterable, Sendable {
    case round, framed, oval, octagon

    public static func of(_ name: String) -> StampStyle {
        // Diviso per quattro prima, così forma e inchiostro non vanno a coppie
        // fisse: un tondo non è sempre blu.
        allCases[(seed(name) / 4) % allCases.count]
    }

    /// Un numero dal nome, uguale a ogni avvio. `hashValue` no: Swift lo mescola a
    /// ogni lancio, e i timbri cambierebbero forma da un giorno all'altro.
    static func seed(_ name: String) -> Int {
        ShipDirectory.fold(name).unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
    }
}

public extension Livery {
    func stampInkPair(_ ink: StampInk) -> Pair {
        Pair(light: ink.lightHex,
             dark: Self.lightened(ink.lightHex, toContrast: Contrast.bodyMinimum, over: darkPaperHex))
    }

    func stampInk(_ ink: StampInk) -> Color { stampInkPair(ink).color }
}
