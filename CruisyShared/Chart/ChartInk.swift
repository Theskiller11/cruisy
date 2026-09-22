import SwiftUI

/// I colori della carta nautica: rotta percorsa, porti, evidenziato, fondo.
///
/// Perché stanno qui e non fra i token della livrea: la carta non è un documento di
/// bordo, è uno strumento. Il verde acqua della rotta e l'azzurro del porto scelto sono
/// convenzioni da carta nautica, si leggono su qualunque mare e non devono cambiare
/// quando cambia la compagnia — se la rotta prendesse il colore della livrea, su una
/// livrea rossa sparirebbe dentro la terra e su una blu dentro il mare.
///
/// Sono i valori che aveva `Palette`, il sistema di colori di prima del redesign del
/// 14 settembre 2026: la carta è rimasta identica, il resto dell'app no.
public enum ChartInk {
    /// La rotta già percorsa e i porti toccati.
    public static let route = Color(hex: 0x46E0C0)
    /// Lo scalo evidenziato, quello che si sta guardando.
    public static let highlight = Color(hex: 0x7FD8FF)
    /// Il porto non ancora toccato: un pieno scuro col bordo chiaro.
    public static let portFill = Color(hex: 0x091A28)
    /// Il nero del fondo, per le ombre sotto i segnaposto.
    public static let abyss = Color(hex: 0x030C14)
    /// Il bordo chiaro dei segnaposto e la rotta ancora da fare.
    public static let hairline = Color(hex: 0xEAF2F8)
}
