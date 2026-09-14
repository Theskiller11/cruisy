import Foundation

/// Sceglie quale porto si intendeva, quando il nome ne indica più di uno.
///
/// Su 15.000 nomi ce ne sono 632 ambigui: St John's sta ad Antigua e a Terranova,
/// Georgetown in cinque posti, Portsmouth in tre. Prendere il primo che capita è
/// esattamente il baco che metteva la nave in Canada durante una crociera caraibica —
/// e lo faceva **senza avvisare**, perché il nome corrispondeva in pieno.
///
/// Due indizi, in ordine di forza:
///
/// 1. **Il paese scritto accanto.** "St John's, Antigua" lo dice da sé, ed è
///    un'informazione che c'era già nel documento e veniva buttata via.
/// 2. **Dove sono gli altri scali.** Un itinerario di crociera è compatto: se gli
///    scali certi stanno ai Caraibi, il St John's giusto è quello dei Caraibi. È
///    l'informazione che il documento non dice ma che la crociera stessa contiene.
enum PortDisambiguator {

    /// Oltre questa distanza da uno scalo certo, un candidato è quasi sicuramente
    /// il porto sbagliato: nessuna crociera fa 2000 miglia fra due scali consecutivi
    /// senza che sia evidente.
    private static let implausibleMiles: Double = 2_000

    static func resolve(_ calls: inout [DraftCall]) {
        // Gli scali con un solo candidato sono i punti fermi da cui si ragiona.
        var anchors: [Coordinate] = calls.compactMap { call in
            call.portCandidates.count == 1 ? call.portCandidates.first?.coordinate : nil
        }

        // Prima passata: l'indizio del paese non ha bisogno di punti fermi.
        for index in calls.indices where calls[index].portCandidates.count > 1 {
            if let picked = byCountryHint(calls[index]) {
                calls[index].port = picked
                calls[index].issues.remove(.portUncertain)
                anchors.append(picked.coordinate)
            }
        }

        // Seconda passata: geografia. Si ripete perché ogni scalo risolto diventa
        // un punto fermo per quelli che restano, ma ogni riga si decide **una volta
        // sola**: senza tenerne il conto, una riga marcata "da confermare" rientrava
        // nella condizione a ogni giro e il ciclo non finiva più.
        var decided = Set<Int>()
        for index in calls.indices where calls[index].portCandidates.count <= 1
            || !calls[index].issues.contains(.portUncertain) && calls[index].port != nil {
            decided.insert(index)
        }

        var progressed = true
        while progressed {
            progressed = false
            for index in calls.indices where !decided.contains(index) {
                guard calls[index].portCandidates.count > 1, !anchors.isEmpty else { continue }
                guard let (picked, isClear) = byProximity(calls[index], anchors: anchors) else { continue }

                calls[index].port = picked
                decided.insert(index)
                progressed = true

                if isClear {
                    calls[index].issues.remove(.portUncertain)
                    anchors.append(picked.coordinate)
                } else {
                    // Due candidati plausibili quasi alla pari: si sceglie il più
                    // vicino ma lo si manda al riesame invece di far finta di sapere.
                    calls[index].issues.insert(.portUncertain)
                }
            }
        }

        // Quello che resta ambiguo senza appigli va guardato da una persona.
        for index in calls.indices where calls[index].portCandidates.count > 1 {
            if calls[index].port == nil {
                calls[index].port = calls[index].portCandidates.first
                calls[index].issues.insert(.portUncertain)
            }
        }
    }

    /// Il paese o la regione scritti nella stessa riga del documento.
    private static func byCountryHint(_ call: DraftCall) -> PortMatch? {
        let haystack = PortGazetteer.fold(call.rawName + " " + call.sourceLine)
        guard !haystack.isEmpty else { return nil }

        let matching = call.portCandidates.filter { candidate in
            let country = PortGazetteer.fold(candidate.country)
            guard country.count >= 4 else { return false }
            // Basta la prima parola del paese: "antigua" pesca "Antigua and Barbuda",
            // "dominicana" non pesca "Dominica".
            let head = country.split(separator: " ").first.map(String.init) ?? country
            return head.count >= 4 && haystack.contains(head)
        }
        return matching.count == 1 ? matching[0] : nil
    }

    /// Il candidato più vicino agli scali già certi.
    ///
    /// Torna anche se la scelta è netta: se il secondo candidato è quasi altrettanto
    /// vicino, la geografia non sta decidendo niente e la riga va confermata a mano.
    private static func byProximity(_ call: DraftCall,
                                   anchors: [Coordinate]) -> (PortMatch, isClear: Bool)? {
        let scored = call.portCandidates
            .map { candidate -> (PortMatch, Double) in
                let nearest = anchors
                    .map { Geo.nauticalMiles(from: candidate.coordinate, to: $0) }
                    .min() ?? .greatestFiniteMagnitude
                return (candidate, nearest)
            }
            .sorted { $0.1 < $1.1 }

        guard let best = scored.first else { return nil }
        guard best.1 < implausibleMiles else { return nil }

        let runnerUp = scored.dropFirst().first?.1 ?? .greatestFiniteMagnitude
        // Netto = il secondo è almeno tre volte più lontano.
        return (best.0, isClear: runnerUp > best.1 * 3)
    }
}
