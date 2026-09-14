import json, sys, time, urllib.parse, urllib.request

# Come si estrae l'elenco delle navi da crociera da Wikidata senza perderne per strada.
#
# Tre trappole, tutte pagate:
#
# 1. `ORDER BY ?ship` con LIMIT/OFFSET **non è un ordinamento totale**: una nave con
#    due armatori o due immagini occupa più righe con la stessa chiave, e ai confini
#    di pagina il motore rimescola — righe duplicate e righe perdute, in silenzio.
#    Qui non si pagina: l'elenco arriva in una richiesta, le proprietà a blocchi
#    con VALUES.
#
# 2. I nomi propri su Wikidata sono passati alla lingua **`mul`**. Chiedendo solo
#    `it|en` un centinaio di navi torna con l'etichetta vuota — Icon of the Seas
#    fra quelle. Vale sia per l'API delle entità sia per `rdfs:label` in SPARQL.
#
# 3. Risalire le sottoclassi di "nave" (`P279*`) per pescare le navi classificate
#    genericamente restituisce risposte da centinaia di megabyte, troncate. I due
#    supplementi qui sotto sono delimitati e verificati per dimensione.

AGENT = "CruisyShipDB/1.0 (matteopapini20@gmail.com)"

def get(url, tries=5):
    req = urllib.request.Request(url, headers={
        "Accept": "application/sparql-results+json", "User-Agent": AGENT})
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(req, timeout=240) as r:
                return json.load(r)
        except Exception as e:
            if attempt == tries - 1: raise
            print("  riprovo:", e, file=sys.stderr); time.sleep(8)

def sparql(query):
    return get("https://query.wikidata.org/sparql?" +
               urllib.parse.urlencode({"query": query}))["results"]["bindings"]

def qid(uri):
    return uri.rsplit("/", 1)[-1] if uri else None

def value(row, key):
    return row.get(key, {}).get("value")

PROPS = """
SELECT ?ship ?imo ?mmsi ?tonnage ?length ?beam ?built ?operator ?flag ?image WHERE {
  VALUES ?ship { %s }
  OPTIONAL { ?ship wdt:P458 ?imo }
  OPTIONAL { ?ship wdt:P587 ?mmsi }
  OPTIONAL { ?ship wdt:P1093 ?tonnage }
  OPTIONAL { ?ship wdt:P2043 ?length }
  OPTIONAL { ?ship wdt:P2261 ?beam }
  OPTIONAL { ?ship wdt:P729 ?built }
  OPTIONAL { ?ship wdt:P137 ?operator }
  OPTIONAL { ?ship wdt:P17 ?flag }
  OPTIONAL { ?ship wdt:P18 ?image }
}
"""

def properties(qids):
    rows = []
    for i in range(0, len(qids), 150):
        rows += sparql(PROPS % " ".join("wd:" + q for q in qids[i:i + 150]))
        print(f"  proprietà {min(i + 150, len(qids))}/{len(qids)}", file=sys.stderr)
        time.sleep(1)
    return rows

# --- 1. le navi classificate come tali ---------------------------------------
core = sorted({qid(value(r, "ship")) for r in
               sparql("SELECT ?ship WHERE { ?ship wdt:P31/wdt:P279* wd:Q39804 }")})
print(f"  navi per classe: {len(core)}", file=sys.stderr)
rows = properties(core)

# --- 2. i due supplementi ----------------------------------------------------
# Gli armatori escono dalla passata appena fatta: chiederli a WDQS con un altro
# giro di VALUES faceva esplodere la risposta.
fleet = {qid(value(r, "operator")) for r in rows if value(r, "operator")}
print(f"  compagnie di crociera: {len(fleet)}", file=sys.stderr)

# a) navi di classe generica "nave", con la stazza di una nave da crociera e un
#    armatore che gestisce già navi da crociera certe. Così sono classificate
#    MSC World Europa e Sun Princess.
candidates = sparql("""
    SELECT DISTINCT ?ship ?op WHERE {
      ?ship wdt:P31 wd:Q11446 ; wdt:P1093 ?gt ; wdt:P137 ?op .
      FILTER(?gt > 20000)
    } LIMIT 3000""")
extra = {qid(value(r, "ship")) for r in candidates if qid(value(r, "op")) in fleet}
print(f"  per stazza e armatore: {len(extra)}", file=sys.stderr)

# b) navi la cui descrizione dice che sono da crociera: prende quelle senza stazza.
extra |= {qid(value(r, "ship")) for r in sparql("""
    SELECT DISTINCT ?ship WHERE {
      ?ship wdt:P31 wd:Q11446 ; schema:description ?d .
      FILTER((lang(?d)="en" && CONTAINS(LCASE(?d),"cruise"))
          || (lang(?d)="it" && CONTAINS(LCASE(?d),"crociera")))
    } LIMIT 3000""")}

nuove = sorted(e for e in extra if e and e not in set(core))
print(f"  navi oltre la classe: {len(nuove)}", file=sys.stderr)
rows += properties(nuove)

# --- 3. i nomi ---------------------------------------------------------------
needed = sorted({q for r in rows for k in ("ship", "operator", "flag")
                 if (q := qid(value(r, k)))})
labels = {}
for i in range(0, len(needed), 50):
    data = get("https://www.wikidata.org/w/api.php?" + urllib.parse.urlencode({
        "action": "wbgetentities", "ids": "|".join(needed[i:i + 50]),
        "props": "labels", "languages": "mul|en|it", "format": "json"}))
    for q, ent in data.get("entities", {}).items():
        lab = ent.get("labels", {})
        labels[q] = (lab.get("mul", {}).get("value") or lab.get("en", {}).get("value"),
                     lab.get("it", {}).get("value") or lab.get("mul", {}).get("value"))
    time.sleep(0.2)
print(f"  nomi risolti: {sum(1 for v in labels.values() if v[0] or v[1])}/{len(needed)}",
      file=sys.stderr)

out = []
for r in rows:
    entry = {}
    en, it = labels.get(qid(value(r, "ship")), (None, None))
    # Il nome della nave è quello scritto sullo scafo: `mul`/inglese per primo.
    # Armatore e bandiera invece si traducono, e l'app è in italiano.
    if en or it: entry["shipLabel"] = {"value": en or it}
    for key, field in (("operator", "operatorLabel"), ("flag", "flagLabel")):
        if (q := qid(value(r, key))):
            len_, lit = labels.get(q, (None, None))
            if lit or len_: entry[field] = {"value": lit or len_}
    for k in ("imo", "mmsi", "tonnage", "length", "beam", "built", "image"):
        if value(r, k) is not None: entry[k] = {"value": value(r, k)}
    out.append(entry)

json.dump({"results": {"bindings": out}}, open("ships.json", "w"))
senza = sum(1 for r in out if "shipLabel" not in r)
print(f"{len(out)} righe · {senza} senza nome")
