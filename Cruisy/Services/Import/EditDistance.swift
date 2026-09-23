import Foundation

/// Quante lettere vanno cambiate, aggiunte o tolte per passare da una parola all'altra.
///
/// Serve per gli errori dell'OCR: «Puerto Plsta», «Parenza». Si ferma appena supera
/// `limit`, perché qui interessa solo sapere se due parole sono **quasi** uguali, e
/// confrontare un nome con tutto l'elenco dei porti deve restare veloce.
enum EditDistance {
    static func between(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        guard abs(a.count - b.count) <= limit else { return limit + 1 }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowBest = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                rowBest = min(rowBest, current[j])
            }
            if rowBest > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    static func between(_ a: String, _ b: String, limit: Int) -> Int {
        between(Array(a), Array(b), limit: limit)
    }
}
