#!/usr/bin/env python3
"""Costruisce CruisyShared/Model/ships.bin, la scheda dati delle navi da crociera.

Fonte: **Wikidata**, che rilascia i propri dati in **CC0** — pubblico dominio, nessuna
attribuzione dovuta. Sono fatti: stazza, lunghezza, IMO, anno di consegna. I fatti non
si possono monopolizzare, e infatti nessuno li rivendica.

Le **fotografie** non entrano qui. Stanno su Wikimedia Commons, sono libere ma quasi
tutte sotto licenze che **obbligano a citare l'autore**: si scaricano a richiesta e si
mostrano col credito accanto, non si impacchettano alla cieca.

Uso:
    python3 scripts/build-ships.py ships.json CruisyShared/Model/ships.bin
dove ships.json è il risultato della query SPARQL in coda a questo file.
"""
import json, struct, sys, unicodedata, re
from urllib.parse import unquote


def fold(s):
    """Deve restare identica a ShipDirectory.fold in Swift."""
    s = unicodedata.normalize('NFKD', s)
    s = ''.join(c for c in s if not unicodedata.combining(c))
    s = s.lower().replace('&', ' and ')
    for ch in ("'", '’', 'ʼ'):
        s = s.replace(ch, '')
    return ' '.join(re.sub(r"[^a-z0-9]+", ' ', s).split())


def value(row, key):
    return row.get(key, {}).get('value')


def is_qid(name):
    """Un nome tipo 'Q111169252' è un'etichetta non risolta, non una nave.

    Succedeva con `SERVICE wikibase:label`, che sotto paginazione lasciava indietro
    quasi cento navi in silenzio — Icon of the Seas fra queste. La query non lo usa
    più, ma il controllo resta: un QID nella scheda della nave si vedrebbe.
    """
    return bool(name) and name[0] == 'Q' and name[1:].isdigit()


def number(row, key):
    raw = value(row, key)
    try:
        return float(raw)
    except (TypeError, ValueError):
        return None


def main(source, out_path):
    rows = json.load(open(source))['results']['bindings']
    ships = {}

    for row in rows:
        name = value(row, 'shipLabel')
        # `startswith('Q')` scartava anche Quantum of the Seas e le Queen di Cunard:
        # un'etichetta non risolta è una Q **seguita da sole cifre**, non una nave
        # che comincia per Q.
        if not name or is_qid(name):
            continue
        key = fold(name)
        if len(key) < 3:
            continue

        built = value(row, 'built')
        year = int(built[:4]) if built and built[:4].isdigit() else 0
        image = value(row, 'image') or ''
        # Il nome del file su Commons, non l'URL: l'app lo ricompone quando serve.
        if image:
            # Wikidata dà l'URL completo e percent-encoded. Nel file va il titolo
            # com'è scritto su Commons: l'app lo codificherà una volta sola, e
            # codificarlo due volte darebbe %2520 al posto dello spazio.
            image = unquote(image.rsplit('/', 1)[-1])

        record = {
            'name': name,
            'imo': (value(row, 'imo') or '').strip(),
            'mmsi': (value(row, 'mmsi') or '').strip(),
            'tonnage': number(row, 'tonnage') or 0,
            'length': number(row, 'length') or 0,
            'beam': number(row, 'beam') or 0,
            'year': year,
            'operator': (value(row, 'operatorLabel') or '').strip(),
            'flag': (value(row, 'flagLabel') or '').strip(),
            'image': image,
        }

        # Wikidata ha righe ripetute per via degli OPTIONAL: si fondono tenendo il
        # valore più informativo di ciascun campo invece del primo che capita.
        if key in ships:
            for field, current in ships[key].items():
                if not current and record.get(field):
                    ships[key][field] = record[field]
        else:
            ships[key] = record

    # Molti nomi su Wikidata portano il prefisso di registro — "MS Brilliance of
    # the Seas". Chi scrive in app scrive "Brilliance of the Seas", quindi la nave
    # va trovata anche senza. L'alias punta allo stesso record.
    PREFISSI = ('ms', 'mv', 'my', 'ss', 'ts', 'gts', 'rms', 'mts')
    for key in list(ships):
        parole = key.split(' ', 1)
        if len(parole) == 2 and parole[0] in PREFISSI and len(parole[1]) >= 3:
            ships.setdefault(parole[1], ships[key])

    def text(value):
        return value.encode('utf-8')[:255]

    buf = bytearray(b'CRSH' + struct.pack('<HHI', 1, 0, len(ships)))
    for key in sorted(ships):
        s = ships[key]
        buf += bytes([len(text(key))]) + text(key)
        # Numeri: stazza e lunghezza come float, anno come intero corto.
        buf += struct.pack('<fffH', s['tonnage'], s['length'], s['beam'], min(s['year'], 65535))
        for field in ('name', 'imo', 'mmsi', 'operator', 'flag', 'image'):
            blob = text(s[field])
            buf += bytes([len(blob)]) + blob

    open(out_path, 'wb').write(buf)
    withdata = sum(1 for s in ships.values() if s['tonnage'] or s['length'])
    print(f"{len(ships)} navi ({withdata} con misure), {len(buf)/1024:.0f} KB")


if __name__ == '__main__':
    main(*sys.argv[1:3])

# L'estrazione da Wikidata sta in `scripts/fetch-ships.py`, che produce il JSON che
# questo script impacchetta:
#
#     python3 scripts/fetch-ships.py            # scrive ships.json
#     python3 scripts/build-ships.py ships.json CruisyShared/Model/ships.bin
#
# Non è una query sola, e il perché è scritto in testa a quel file: la paginazione
# perde righe, i nomi propri vivono nella lingua `mul`, e risalire le sottoclassi di
# "nave" restituisce centinaia di megabyte troncati.
