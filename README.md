# Cruisy

App iOS per chi è in crociera. Risponde a una domanda sola: **quanto manca?**
In giorno di porto, al rientro obbligatorio a bordo. In giorno di mare, all'arrivo
nel prossimo scalo.

Nasce dal brief Claude Design *"App di tracking crociere"*, riprogettata dopo un
audit con la skill `/apple-design` e con in testa i requisiti di pubblicazione
sull'App Store.

## Le tre idee che la reggono

**Il cuore funziona senza rete.** A bordo la connessione non c'è o si paga a peso d'oro.
Countdown, carta, itinerario, porti, navi e ora di bordo si calcolano sul telefono, con
dati che viaggiano dentro l'app.

La rete serve solo per cose **facoltative**, che degradano senza: il meteo (Open-Meteo,
direttamente o dal proxy), le foto di navi e porti (Wikimedia Commons e Wikipedia, mai
su rete a consumo senza permesso), la ricerca di una nave che manca (Wikidata, solo a
richiesta) e il livello satellitare della Carta (tessere di Apple, spento di default).
L'elenco completo, con cosa parte verso chi, è nell'informativa: `docs/index.html`.
La posizione non esce dal telefono in nessun caso.

## Come entra l'itinerario

Cruisy **non ha un archivio delle partenze**, e non può averlo: gli orari di una
compagnia sono roba sua, e scaricarli da qualche parte farebbe cadere il funzionamento
offline. Quindi l'itinerario lo porti tu — incollato, fotografato o importato da PDF —
e l'app fa il lavoro noioso.

**Un lettore solo**, deterministico (`ItineraryTextParser`): a parità di ingresso dà
sempre lo stesso risultato — quindi si collauda riga per riga — e funziona su qualunque
iPhone. C'era anche una strada con Apple Intelligence: è stata tolta, perché due strade
sviluppate a metà valgono meno di una fatta bene.

Lavora **a blocchi, non a righe**. Un blocco comincia dove compare una data e assorbe
quello che segue fino alla data successiva:

    Giorno 1 — Sabato 15 novembre
    San Juan, Porto Rico
    Imbarco dalle 14:00. La nave parte alle 20:00.

Riga per riga, qui la data non trovava un porto e il porto non trovava una data. A
blocchi, il contesto fra una tappa e l'altra finisce nella tappa a cui appartiene. Il
nome del porto è il residuo che si aggancia **meglio** all'elenco, così una riga come
«Cabina 11024 · ponte 11», assorbita nel blocco, non vince su quella che contiene
davvero il porto.

Sulle date, i casi che sbagliava e che ora sono coperti da test:

- **`Mar 17 nov` diventava il 17 marzo** invece di martedì 17. I giorni della settimana
  si cancellano prima di cercare il mese, perché le abbreviazioni collidono in entrambe
  le lingue (mar/marzo, mar/March, mag/may). Si sostituiscono con spazi della stessa
  lunghezza, così le posizioni trovate restano valide sulla riga originale.
- **`GIO 20`**, il giorno da solo: eredita il mese dalla tappa precedente, e se il
  numero torna indietro (dal 30 all'1) il mese avanza. Si accetta un numero nudo solo
  dopo un giorno della settimana, altrimenti ogni numero di cabina diventerebbe una data.
- **`05/11` è ambiguo**: l'ordine giorno/mese si decide **una volta per documento**. Se
  altrove compare `15/11`, il primo numero è il giorno in tutto il testo; senza prove
  interne decide la lingua.
- ISO (`2026-11-15`) e ordinali (`15th November`, `November 16th`).
- Un numero di ponte non diventa un orario.

Un blocco con una data ma senza porto **e** senza orari — un numero di prenotazione, un
ringraziamento — viene scartato in silenzio: un avviso falso toglie peso a quelli veri.

Si passa **sempre** dal riesame: è un'ipotesi su un documento, e un orario sbagliato qui
è una persona che resta a terra. I porti non riconosciuti bloccano la conferma; gli all
aboard dedotti (mezz'ora prima della partenza in banchina, un'ora col tender) restano
marchiati finché non li confermi.

**I nomi di porto ambigui non si risolvono a caso.** Su 15.000 nomi 350 ne indicano più
di uno — St John's sta ad Antigua e a Terranova, Georgetown in cinque posti. Il
gazetteer restituisce *tutti* i candidati e `PortDisambiguator` sceglie con due indizi:
il paese scritto accanto nel documento, e dove sono gli altri scali (un itinerario è
geograficamente compatto). Se nessuno dei due decide, la riga va al riesame.

I porti si agganciano a `ports.bin`: **World Port Index** della NGA statunitense
(pubblico dominio) più le località portuali di **UN/LOCODE**, 15.000 voci con
coordinate, rigenerabile con `scripts/build-ports.py`. La parte che vale davvero è la
tabella di alias scritta a mano: le compagnie scrivono «Santorini» dove il porto è
Thira, «St. Thomas» dove è Charlotte Amalie, «Roma» dove ci si imbarca a Civitavecchia.

## Niente account, e nemmeno iCloud

La crociera si porta altrove come **file** (`.cruisy`, JSON): la mandi a chi viaggia
con te o al tuo iPad, chi la riceve la apre e ce l'ha.

Non è un ripiego per l'account: in crociera funziona **meglio** della sincronizzazione
automatica. AirDrop fra due telefoni sullo stesso ponte non ha bisogno di rete, mentre
iCloud in mezzo all'oceano non sincronizzerebbe niente. E non richiede nessuna
capability da chiedere ad Apple, nessun back end, nessuna password — quindi nemmeno
l'obbligo di cancellazione dell'account previsto dalla regola 5.1.1(v).

Un file che arriva **non sovrascrive mai in silenzio**: l'itinerario che c'è può
contenere correzioni fatte a bordo che non stanno da nessun'altra parte, quindi si
chiede conferma.

## La carta

Due livelli, con la stessa inquadratura condivisa: passando dall'uno all'altro si
resta dove si stava guardando.

- **Carta** (default) — vettoriale, disegnata da `coastline.bin` con `Canvas`.
  Funziona in modalità aereo.
- **Satellite** — `MapKit` con `.imagery`. Richiede rete. L'attribuzione Apple è
  tenuta sopra la scheda di stato con un inset misurato: usando MapKit deve restare
  visibile, e finiva sotto la barra delle schede.

Rotta, porti e nave vengono dagli stessi `Voyage.routeSegments`, così i due
disegnatori non possono raccontare due storie diverse.

`ChartCamera` è il tipo che il gesto muove, separato dal disegno per poterne provare
il comportamento senza far girare l'interfaccia: la carta sta incollata al dito per
tutto il trascinamento, al rilascio prosegue alla velocità che aveva
(`predictedEndTranslation`, che è già la proiezione dello slancio), ai limiti di zoom
resiste con l'elastico invece di bloccarsi, e il punto sotto le dita resta fermo
mentre si pizzica.

## Struttura

```
Cruisy/           app: viste, servizi, risorse
CruisyShared/     modello, carta e design — condivisi con i widget
CruisyWidgets/    widget di schermata Home + Live Activity
CruisyTests/      test unitari (Swift Testing)
CruisyUITests/    test di interfaccia (XCUITest): gesti della carta, apertura di ogni schermata
scripts/          dati (porti, navi, fusi), screenshot, test
docs/             informativa privacy; handoff-fable.md per chi riprende il lavoro
store/            testi per App Store Connect e note per la revisione
```

Per chi lavora sul codice — persona o agente — le regole e i comandi stanno in
`CLAUDE.md`.

`CruisyShared` compare in `fileSystemSynchronizedGroups` di entrambi i target, così
i file nuovi entrano da soli in app **e** widget senza toccare il `.pbxproj`.

## Cose non ovvie

- **Un countdown è una coppia di date, mai un contatore.** È l'unico modo perché
  resti giusto dopo il background, e l'unico che widget e Live Activity possano
  rendere: lì non si può far girare un timer, si passa un intervallo a
  `Text(timerInterval:)` e conta il sistema.
- **Tutti gli istanti sono UTC; l'ora di bordo è resa.** Le navi tengono la propria
  ora e non sempre la allineano al porto, mentre il telefono si riallinea da solo.
  `ShipClock` è l'unico posto che decide come si scrive un orario, e i `DatePicker`
  degli editor girano in ora di bordo via `\.timeZone`.
- **La carta è disegnata a mano su geometria Natural Earth 1:50m** (pubblico dominio),
  impacchettata in `coastline.bin`: un formato binario con i riquadri di ingombro per
  anello, così scartare ciò che è fuori vista costa quattro confronti. Niente MapKit,
  che senza rete resterebbe bianco.
- **I giorni di mare non sono salvati**, si ricavano dai buchi fra gli scali.
- **Le notifiche sono a orario fisso, non geografiche**: niente permesso di posizione
  permanente, niente background location, niente recinti. Solo "quando in uso".
  Restano al livello di interruzione normale: il livello *time sensitive* richiede una
  capability sull'App ID che un profilo di sviluppo personale non ha. Con un Full
  Immersion attivo l'avviso non suona, e la difesa per quel caso è la Live Activity
  sulla schermata di blocco.
- **`GlassSurface` è l'unico posto che sa cos'è il vetro**, e da lì gestisce "Riduci
  trasparenza" e "Aumenta contrasto". Provabili con `-riduciTrasparenza` e
  `-aumentaContrasto`.
- **I livelli di contrasto sono verificati da un test**, non dall'occhio
  (`PaletteContrastTests`): il brief aveva etichette a 1,6:1.

## Provare

```bash
scripts/test.sh unit        # test unitari
scripts/test.sh ui          # test di interfaccia
scripts/screenshots.sh      # fotografa tutte le schermate, anche --lang en e --size AX5
```

Scenari di collaudo (solo DEBUG), che spostano il punto di osservazione tenendo gli
orari di bordo realistici:

```bash
xcrun simctl launch <udid> it.matteopapini.Cruisy -sample inPort
```

`inPort` · `atSea` · `beforeBoarding` · `farFromBoarding` · `imminent`.

Per aprire una scheda o una schermata senza toccare lo schermo: `-tab oggi|itinerario|nave|diario`
e `-open carta|scalo|porti|editor|importazione|impostazioni|onboarding`.

Per l'importazione: `-importDemo` riempie la casella con un itinerario di esempio,
`-importLeggi` tira dritto fino al riesame.

Per provare **widget e Live Activity sul telefono** serve `-sample deviceTest`, da
mettere fra gli argomenti dello schema in Xcode. A differenza degli altri scenari
scrive la crociera nell'archivio condiviso — widget e Live Activity girano in un altro
processo e uno scenario tenuto in memoria lo vedrebbero vuoto. La crociera vera viene
messa da parte prima; `-sampleRestore` la rimette.

## Da fare prima della pubblicazione

- Iscrizione all'Apple Developer Program (possibile dal 23 novembre 2026).
- Licenza del meteo: Open-Meteo è gratuito solo per uso non commerciale.
- Pubblicare l'informativa privacy (`docs/index.html`): App Store Connect vuole l'URL.
- Note per la revisione sul permesso «Sempre»: `store/app-review-notes.md`.
- Verifica su dispositivo di widget, Live Activity, rotta registrata e collegamento a Meteo.
