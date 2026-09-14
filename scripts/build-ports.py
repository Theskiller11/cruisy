#!/usr/bin/env python3
"""Costruisce Cruisy/Resources/ports.bin, l'elenco dei porti con le coordinate.

Fonti, entrambe aperte e nessuna delle due di una compagnia di crociera:
  - World Port Index (NGA, opera del governo USA -> pubblico dominio)
  - UN/LOCODE, limitato alle localita' con funzione portuale

Uso:
    curl -sSLo wpi.csv 'https://msi.nga.mil/api/publications/download?type=view&key=16920959/SFH00000/UpdatedPub150.csv'
    curl -sSLo unlocode.csv https://raw.githubusercontent.com/datasets/un-locode/main/data/code-list.csv
    python3 scripts/build-ports.py wpi.csv unlocode.csv Cruisy/Resources/ports.bin
"""
import csv, struct, sys, unicodedata, re
from collections import defaultdict

# Due voci con lo stesso nome entro questo raggio sono lo stesso porto.
# Generoso di proposito: le due fonti danno San Juan a quattro chilometri di
# distanza l'una dall'altra, e trattarle come porti diversi creava un'ambiguita'
# inventata che mandava al riesame righe perfettamente pulite.
SAME_PORT_DEGREES = 0.15


def fold(s):
    """Deve restare identica a PortGazetteer.fold in Swift."""
    s = unicodedata.normalize('NFKD', s)
    s = ''.join(c for c in s if not unicodedata.combining(c))
    s = s.lower().replace('&', ' and ')
    # Gli apostrofi spariscono invece di diventare spazi, altrimenti "St John's"
    # e "St Johns" finiscono in due chiavi diverse per due porti diversi.
    for ch in ("'", '’', 'ʼ'):
        s = s.replace(ch, '')
    return ' '.join(re.sub(r"[^a-z0-9]+", ' ', s).split())


def dms(token):
    """UN/LOCODE scrive '4230N' o '00131E'."""
    m = re.fullmatch(r'(\d{2,3})(\d{2})([NSEW])', token)
    if not m:
        return None
    value = int(m.group(1)) + int(m.group(2)) / 60
    return -value if m.group(3) in 'SW' else value


ALIAS = {
    "santorini": "thira", "fira": "thira",
    "st thomas": "charlotte amalie", "saint thomas": "charlotte amalie",
    "st maarten": "philipsburg", "sint maarten": "philipsburg",
    "saint martin": "philipsburg", "st martin": "philipsburg",
    "st barts": "gustavia", "st barth": "gustavia", "saint barth": "gustavia",
    "saint barthelemy": "gustavia", "st barthelemy": "gustavia",
    "ephesus": "kusadasi", "efeso": "kusadasi",
    "costa maya": "majahual", "amber cove": "puerto plata",
    "roma": "civitavecchia", "rome": "civitavecchia",
    "athens": "piraeus", "atene": "piraeus", "pireo": "piraeus",
    "lisbona": "lisboa", "lisbon": "lisboa", "genoa": "genova",
    "tenerife": "santa cruz de tenerife", "madeira": "funchal",
    "palma": "palma de mallorca", "maiorca": "palma de mallorca", "mallorca": "palma de mallorca",
    "pisa": "livorno", "firenze": "livorno", "florence": "livorno",
    "provence": "marseille", "provenza": "marseille",
    "napoli": "naples", "nizza": "nice", "marsiglia": "marseille", "siviglia": "seville",
    "copenaghen": "copenhagen", "amburgo": "hamburg", "stoccolma": "stockholm",
    "anversa": "antwerpen", "la valletta": "valletta", "cadice": "cadiz",
}

# Scali che nessun elenco di porti conosce: isole private e ancoraggi panoramici.
EXPLICIT = {
    "cococay": (25.8180, -77.9350, "CocoCay", "Bahamas"),
    "coco cay": (25.8180, -77.9350, "CocoCay", "Bahamas"),
    "perfect day at cococay": (25.8180, -77.9350, "CocoCay", "Bahamas"),
    "half moon cay": (24.5800, -75.9400, "Half Moon Cay", "Bahamas"),
    "great stirrup cay": (25.8200, -77.9200, "Great Stirrup Cay", "Bahamas"),
    "castaway cay": (26.0870, -77.5330, "Castaway Cay", "Bahamas"),
    "ocean cay": (25.4180, -79.2350, "Ocean Cay", "Bahamas"),
    "harvest caye": (16.1000, -88.6500, "Harvest Caye", "Belize"),
    "glacier bay": (58.6650, -136.9000, "Glacier Bay", "United States"),
    "geiranger": (62.1000, 7.2050, "Geiranger", "Norway"),
    "hubbard glacier": (60.0200, -139.4700, "Hubbard Glacier", "United States"),
    "tracy arm": (57.8300, -133.5500, "Tracy Arm", "United States"),
}


def main(wpi_path, unlocode_path, out_path):
    groups = defaultdict(list)

    def add(key, lat, lon, name, country):
        k = fold(key)
        if len(k) < 3:
            return
        for existing in groups[k]:
            if (abs(existing[0] - lat) < SAME_PORT_DEGREES
                    and abs(existing[1] - lon) < SAME_PORT_DEGREES):
                return          # stesso porto, gia' presente
        groups[k].append((lat, lon, name, country))

    with open(wpi_path, newline='', encoding='utf-8-sig') as f:
        for row in csv.DictReader(f):
            try:
                lat, lon = float(row['Latitude']), float(row['Longitude'])
            except (TypeError, ValueError):
                continue
            main_name = (row.get('Main Port Name') or '').strip()
            if not main_name:
                continue
            country = (row.get('Country Code') or '').strip()   # nome intero
            for key in (main_name, (row.get('Alternate Port Name') or '').strip()):
                if key:
                    add(key, lat, lon, main_name, country)

    with open(unlocode_path, newline='', encoding='utf-8-sig') as f:
        for row in csv.DictReader(f):
            if '1' not in (row.get('Function') or ''):
                continue
            coords = (row.get('Coordinates') or '').strip()
            if not coords or ' ' not in coords:
                continue
            a, b = coords.split()
            lat, lon = dms(a), dms(b)
            if lat is None or lon is None:
                continue
            name = (row.get('NameWoDiacritics') or row.get('Name') or '').strip()
            if name:
                add(name, lat, lon, name, (row.get('Country') or '').strip())

    # Un alias e' una scelta gia' fatta: sostituisce i candidati, non si aggiunge.
    for alias, target in ALIAS.items():
        if fold(target) in groups:
            groups[fold(alias)] = list(groups[fold(target)])
        else:
            print(f"  attenzione: alias non risolto {alias} -> {target}", file=sys.stderr)
    for key, value in EXPLICIT.items():
        groups[fold(key)] = [value]

    buf = bytearray(b'CRPG' + struct.pack('<HHI', 2, 0, len(groups)))
    for key in sorted(groups):
        kb = key.encode()[:255]
        # Oltre otto omonimi non si disambigua piu': si tirerebbe a indovinare.
        chosen = groups[key][:8]
        buf += bytes([len(kb)]) + kb + bytes([len(chosen)])
        for lat, lon, name, country in chosen:
            nb, cb = name.encode()[:255], country.encode()[:255]
            buf += struct.pack('<ff', lat, lon) + bytes([len(nb)]) + nb + bytes([len(cb)]) + cb

    with open(out_path, 'wb') as f:
        f.write(buf)

    ambiguous = sum(1 for v in groups.values() if len(v) > 1)
    print(f"{len(groups)} chiavi ({ambiguous} con piu' di un candidato), {len(buf)/1024:.0f} KB")


if __name__ == '__main__':
    main(*sys.argv[1:4])
