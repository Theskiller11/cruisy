#!/usr/bin/env python3
"""Aggiunge a ports.bin il fuso orario di ogni porto, passando da CRPG v2 a v3.

Perche' serve
-------------
L'ora di bordo segue il porto: alle 02:00 della notte che precede l'ultimo giorno
di mare la nave sposta l'orologio sull'ora del porto d'arrivo. Per farlo l'app deve
sapere in che fuso sta ogni scalo, **senza rete**, perche' in mezzo all'oceano non
c'e'.

Da dove viene il dato
--------------------
`/usr/share/zoneinfo/zone.tab` del database tz: dominio pubblico, gia' sul Mac, con
codice paese e coordinate della citta' di riferimento di ogni fuso. Si sceglie il
fuso **piu' vicino fra quelli dello stesso paese**.

Il filtro per paese non e' un dettaglio: misurato su 63 porti di crociera scelti fra
i casi difficili (isole vicine a un altro stato), il fuso piu' vicino *senza* filtro
sbaglia l'ora in **12 casi** — Palma finisce ad Algeri, Cagliari a Tunisi, Corfu a
Tirana — mentre col filtro ne sbaglia **uno**, Odessa contro Sinferopoli, che e' un
caso politico prima che geografico.

Uso:
    python3 scripts/build-port-timezones.py Cruisy/Resources/ports.bin
"""
import math
import re
import struct
import sys

ZONE_TAB = '/usr/share/zoneinfo/zone.tab'
ISO_TAB = '/usr/share/zoneinfo/iso3166.tab'

# I nomi che iso3166.tab non riconosce da se'. Vengono dal World Port Index, che
# scrive i paesi per esteso e con le sue convenzioni.
NOMI_A_CODICE = {
    'United Kingdom': 'GB', 'South Korea': 'KR', 'North Korea': 'KP',
    'Trinidad and Tobago': 'TT', 'Burma': 'MM', 'U.S. Virgin Islands': 'VI',
    "Cote D'Ivoire": 'CI', 'Congo (Brazzaville)': 'CG', 'Congo (Kinshasa)': 'CD',
    'Caribbean Netherlands': 'BQ', 'Federated States of Micronesia': 'FM',
    'Sint Maarten': 'SX', 'Curacao': 'CW', 'The Bahamas': 'BS',
    'Saint Helena, Ascension, and Tristan da Cunha': 'SH', 'Saint Lucia': 'LC',
    'Turks and Caicos Islands': 'TC', 'Reunion': 'RE',
    'South Georgia and South Sandwich Islands': 'GS',
    'Sao Tome and Principe': 'ST', 'Cabo Verde': 'CV',
    'Saint Pierre and Miquelon': 'PM', 'The Gambia': 'GM',
    'Saint Kitts and Nevis': 'KN', 'British Virgin Islands': 'VG',
    'Samoa': 'WS', 'Timor-Leste': 'TL', 'Bosnia and Herzegovina': 'BA',
    'American Samoa': 'AS', 'Antigua and Barbuda': 'AG',
    'Saint Vincent and the Grenadines (Windward Islands)': 'VC',
    'Wallis and Futuna': 'WF',
    # Atolli americani senza una riga propria in zone.tab: si prende il fuso a mano,
    # perche' il piu' vicino sarebbe dall'altra parte del Pacifico.
    'Johnson Atoll': 'UM', 'Midway Islands': 'UM', 'Wake Island': 'UM',
}

# Dove zone.tab non arriva.
FUSI_ESPLICITI = {'UM': 'Pacific/Wake'}


def leggi_iso6709(s):
    """zone.tab scrive '+4230+00131' oppure '+423045+0013115'."""
    m = re.fullmatch(r'([+-]\d{2})(\d{2})(\d{2})?([+-]\d{3})(\d{2})(\d{2})?', s)
    lat = abs(int(m.group(1))) + int(m.group(2)) / 60 + int(m.group(3) or 0) / 3600
    lon = abs(int(m.group(4))) + int(m.group(5)) / 60 + int(m.group(6) or 0) / 3600
    return (-lat if s[0] == '-' else lat), (-lon if m.group(4)[0] == '-' else lon)


def carica_fusi():
    zone = []
    for line in open(ZONE_TAB):
        if line.startswith('#') or not line.strip():
            continue
        parts = line.split('\t')
        lat, lon = leggi_iso6709(parts[1])
        zone.append((parts[2].strip(), lat, lon, parts[0]))
    return zone


def carica_iso():
    table = {}
    for line in open(ISO_TAB):
        if line.startswith('#') or not line.strip():
            continue
        code, name = line.rstrip('\n').split('\t')
        table[name.lower()] = code
    return table


def distanza(lat1, lon1, lat2, lon2):
    p = math.pi / 180
    coseno = (math.sin(lat1 * p) * math.sin(lat2 * p)
              + math.cos(lat1 * p) * math.cos(lat2 * p) * math.cos((lon1 - lon2) * p))
    return math.acos(min(1, max(-1, coseno)))


class Risolutore:
    def __init__(self):
        self.zone = carica_fusi()
        self.iso = carica_iso()
        self.memoria = {}
        self.senza_paese = 0

    def codice(self, paese):
        if re.fullmatch(r'[A-Z]{2}', paese):
            return paese
        if paese in NOMI_A_CODICE:
            return NOMI_A_CODICE[paese]
        k = paese.lower()
        if k in self.iso:
            return self.iso[k]
        candidati = {c for nome, c in self.iso.items()
                     if nome.startswith(k) or k.startswith(nome)}
        return candidati.pop() if len(candidati) == 1 else None

    def fuso(self, lat, lon, paese):
        cc = self.codice(paese)
        if cc in FUSI_ESPLICITI:
            return FUSI_ESPLICITI[cc]
        if cc is None:
            self.senza_paese += 1
        chiave = (round(lat, 2), round(lon, 2), cc)
        if chiave in self.memoria:
            return self.memoria[chiave]
        candidati = [z for z in self.zone if cc is None or z[3] == cc] or self.zone
        scelto = min(candidati, key=lambda z: distanza(lat, lon, z[1], z[2]))[0]
        self.memoria[chiave] = scelto
        return scelto


def main(path):
    data = open(path, 'rb').read()
    assert data[:4] == b'CRPG', 'non e\' un ports.bin'
    versione, _, chiavi = struct.unpack_from('<HHI', data, 4)
    assert versione == 2, f'attesa la versione 2, trovata {versione}'

    risolutore = Risolutore()
    fusi, indice_di = [], {}

    def indice(nome):
        if nome not in indice_di:
            indice_di[nome] = len(fusi)
            fusi.append(nome)
        return indice_di[nome]

    # Corpo nuovo: identico al vecchio, con due byte di indice in coda a ogni porto.
    corpo = bytearray()
    offset, porti = 12, 0
    for _ in range(chiavi):
        kl = data[offset]; offset += 1
        key = data[offset:offset + kl]; offset += kl
        gc = data[offset]; offset += 1
        corpo += bytes([kl]) + key + bytes([gc])
        for _ in range(gc):
            lat, lon = struct.unpack_from('<ff', data, offset)
            grezzo = data[offset:offset + 8]; offset += 8
            nl = data[offset]; offset += 1
            nome = data[offset:offset + nl]; offset += nl
            cl = data[offset]; offset += 1
            paese = data[offset:offset + cl]; offset += cl
            fuso = risolutore.fuso(lat, lon, paese.decode())
            corpo += grezzo + bytes([nl]) + nome + bytes([cl]) + paese
            corpo += struct.pack('<H', indice(fuso))
            porti += 1
    assert offset == len(data), 'il file non e\' stato consumato per intero'

    tabella = bytearray(struct.pack('<H', len(fusi)))
    for nome in fusi:
        b = nome.encode()
        tabella += bytes([len(b)]) + b

    out = bytearray(b'CRPG' + struct.pack('<HHI', 3, 0, chiavi)) + tabella + corpo
    open(path, 'wb').write(out)

    print(f'{chiavi} chiavi, {porti} porti, {len(fusi)} fusi distinti')
    print(f'{len(data) / 1024:.0f} KB -> {len(out) / 1024:.0f} KB')
    if risolutore.senza_paese:
        print(f'attenzione: {risolutore.senza_paese} porti senza codice paese '
              f'riconoscibile, risolti col fuso piu\' vicino al mondo')


if __name__ == '__main__':
    main(sys.argv[1])
