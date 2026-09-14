// Preambolo comune a tutti gli script di costruzione delle schermate.
//
// Viene concatenato in testa a ogni corpo da `assembla.py`. Non è un modulo: lo
// script che arriva a `use_figma` dev'essere un blocco solo, autosufficiente.
//
// Regole che questo preambolo fa rispettare da sé, e che sono costate un errore
// ciascuna:
//   · `createAutoLayout` nasce con un riempimento bianco. Su un'app nera copre
//     tutto, quindi `col`/`row` lo tolgono sempre.
//   · L'opacità di un riempimento viene scartata da Figma quando al colore è
//     legata una variabile: dove serve l'alfa si usa `rgba()`, che legge il
//     valore letterale, e si dichiara nel nome del livello.
//   · I glifi si prendono per **nome** SF Symbol, mai per codepoint.

const PAGINA_SCHERMATE = "6:5";
const W = 402, H = 874;              // iPhone 17 Pro, in punti
const MARGINE = 16;                  // il margine orizzontale dell'app

const page = await figma.getNodeByIdAsync(PAGINA_SCHERMATE);
await figma.setCurrentPageAsync(page);

for (const f of [
  { family: "SF Pro", style: "Regular" },
  { family: "SF Pro", style: "Medium" },
  { family: "SF Pro", style: "Semibold" },
  { family: "SF Pro Rounded", style: "Semibold" },
  { family: "Roboto Mono", style: "Medium" }
]) await figma.loadFontAsync(f);

const vars = await figma.variables.getLocalVariablesAsync();
const V = Object.fromEntries(vars.map(v => [v.name, v]));
const TS = Object.fromEntries((await figma.getLocalTextStylesAsync()).map(s => [s.name, s]));
const ES = Object.fromEntries((await figma.getLocalEffectStylesAsync()).map(s => [s.name, s]));

/** Riempimento pieno legato a una variabile colore. */
const paint = (nome) => figma.variables.setBoundVariableForPaint(
  { type: "SOLID", color: { r: 0, g: 0, b: 0 } }, "color", V[nome]);

/** Il valore letterale di una variabile, per quando serve controllare l'alfa. */
const rgba = (nome, a) => {
  const v = V[nome];
  const c = v.valuesByMode[Object.keys(v.valuesByMode)[0]];
  return { r: c.r, g: c.g, b: c.b, a: a === undefined ? (c.a === undefined ? 1 : c.a) : a };
};
/** Riempimento con alfa esplicito: **non** legato, perché il legame lo scarterebbe. */
const wash = (nome, a) => ({ type: "SOLID", color: rgba(nome), opacity: a });

/** Testo con uno stile del sistema applicato. */
const txt = (stile, contenuto, coloreVar, opts) => {
  opts = opts || {};
  const t = figma.createText();
  t.fontName = TS[stile].fontName;
  t.characters = contenuto;
  t.textStyleId = TS[stile].id;
  if (coloreVar) t.fills = [paint(coloreVar)];
  if (opts.upper) t.textCase = "UPPER";
  t.name = opts.name || contenuto.slice(0, 24);
  return t;
};

/** Colonna e riga in auto-layout, senza il bianco predefinito. */
const col = (spacing, opts) => {
  const f = figma.createAutoLayout("VERTICAL", Object.assign({ itemSpacing: spacing }, opts || {}));
  f.fills = [];
  return f;
};
const row = (spacing, opts) => {
  const f = figma.createAutoLayout("HORIZONTAL", Object.assign({ itemSpacing: spacing }, opts || {}));
  f.fills = [];
  return f;
};
const pad = (f, o, v) => {
  f.paddingLeft = f.paddingRight = o;
  f.paddingTop = f.paddingBottom = (v === undefined ? o : v);
  return f;
};

/** Una superficie di vetro, con i numeri di GlassSurface.Prominence. */
const card = (raggio, tinta) => {
  const f = col(0);
  f.fills = tinta ? [wash(tinta, 0.10), wash("fondo/vetro", 1)] : [paint("fondo/vetro")];
  if (tinta) f.fills = [wash("fondo/vetro", 1), wash(tinta, 0.12)];
  f.strokes = [paint("bordo/sottile")];
  f.strokeWeight = 0.5;
  f.cornerRadius = raggio;
  if (ES["Vetro / Card"]) f.effectStyleId = ES["Vetro / Card"].id;
  return f;
};

/** Un glifo SF Symbol, per nome. */
const glifo = (nome, size, coloreVar, peso) => {
  const t = figma.createText();
  t.fontName = { family: "SF Pro", style: peso || "Semibold" };
  t.fontSize = size;
  t.characters = figma.util.getSfSymbolCharacter(nome);
  t.name = "icona/" + nome;
  if (coloreVar) t.fills = [paint(coloreVar)];
  return t;
};

/** La riga di grandezze: valore sopra, etichetta sotto, colonne uguali. */
const grandezze = (elenco) => {
  const r = row(12);
  r.counterAxisAlignItems = "MIN";
  for (const [valore, etichetta] of elenco) {
    const c = col(3);
    c.appendChild(txt("Valore metrica", valore, "inchiostro/primario"));
    c.appendChild(txt("Etichetta metrica", etichetta, "inchiostro/terziario", { upper: true }));
    r.appendChild(c);
    c.layoutSizingHorizontal = "FILL";
  }
  return r;
};

/** Un filo orizzontale: un tratto, non un rettangolo alto un punto. */
const filo = () => {
  const l = figma.createLine();
  l.strokes = [paint("bordo/sottile")];
  l.strokeWeight = 0.5;
  l.name = "filo";
  return l;
};

/** La cornice della schermata, col gradiente a tre fermate dell'app. */
const schermata = (nome, x, fermate) => {
  const s = figma.createFrame();
  s.name = nome;
  s.resize(W, H);
  s.x = x; s.y = 0;
  s.clipsContent = true;
  s.layoutMode = "NONE";
  s.fills = [{
    type: "GRADIENT_LINEAR",
    // Dall'alto verso il basso.
    gradientTransform: [[0, 1, 0], [-1, 0, 1]],
    gradientStops: fermate.map((f, i) => ({
      position: i / (fermate.length - 1),
      color: typeof f === "string" ? rgba(f) : f
    }))
  }];
  return s;
};

/** La barra di stato di Apple, con ripiego se la libreria non risponde. */
const barraDiStato = async () => {
  try {
    const c = await figma.importComponentByKeyAsync("e01a1714aeec1a5a0a6453485bf16e975008b282");
    const i = c.createInstance();
    i.name = "Barra di stato";
    return i;
  } catch (e) {
    const f = row(0, { name: "Barra di stato (ripiego)" });
    f.resize(W, 59);
    const t = txt("Titolo riga", "11:53", "inchiostro/primario");
    f.appendChild(t);
    pad(f, 28, 18);
    return f;
  }
};

/** La barra delle schede: cinque coppie glifo+parola su una pastiglia di vetro.
 *  Costruita a mano e non presa da Apple perché i cinque glifi e le cinque
 *  parole sono di Cruisy: il componente di sistema andrebbe comunque riscritto. */
const barraSchede = (attiva) => {
  const schede = [
    ["Oggi", "sun.horizon"],
    ["Carta", "location.north.line"],
    ["Itinerario", "list.bullet.indent"],
    ["Nave", "ferry"],
    ["Diario", "book.closed"]
  ];
  const barra = row(0, { name: "Barra delle schede" });
  barra.primaryAxisAlignItems = "SPACE_BETWEEN";
  barra.counterAxisAlignItems = "CENTER";
  pad(barra, 8, 8);
  barra.cornerRadius = 34;
  barra.fills = [wash("fondo/vetro", 0.92)];
  barra.strokes = [paint("bordo/sottile")];
  barra.strokeWeight = 0.5;
  if (ES["Vetro / Chrome"]) barra.effectStyleId = ES["Vetro / Chrome"].id;

  for (const [nome, simbolo] of schede) {
    const scelta = nome === attiva;
    const c = col(3, { name: nome });
    c.counterAxisAlignItems = "CENTER";
    pad(c, 14, 8);
    if (scelta) {
      c.cornerRadius = 26;
      c.fills = [wash("accento/navigazione", 0.14)];
    }
    c.appendChild(glifo(simbolo, 20, scelta ? "accento/navigazione" : "inchiostro/secondario"));
    c.appendChild(txt("Etichetta metrica", nome,
      scelta ? "accento/navigazione" : "inchiostro/secondario"));
    barra.appendChild(c);
  }
  return barra;
};

// --- Oggi, giorno di mare --------------------------------------------------
// Stessa struttura della schermata in porto, ma l'evento cambia: si conta
// all'arrivo, e l'avanzamento è un'onda invece di un anello.

const s = schermata("Oggi — in mare", 460,
  ["fondo/mare-alto", "fondo/mare", "fondo/abisso"]);
page.appendChild(s);

const stato = await barraDiStato();
s.appendChild(stato);
stato.x = 0; stato.y = 0;

const contenuto = col(12, { name: "Contenuto" });
pad(contenuto, MARGINE, 0);
s.appendChild(contenuto);
contenuto.x = 0; contenuto.y = 59;
contenuto.resize(W, 100);
contenuto.layoutSizingHorizontal = "FIXED";

// --- testata ---------------------------------------------------------------
const testata = row(12, { name: "Testata" });
testata.counterAxisAlignItems = "CENTER";
const nomi = col(2);
nomi.appendChild(txt("Titolo schermata", "Stella Australe", "inchiostro/primario"));
nomi.appendChild(txt("Sottotitolo schermata", "Giorno 4 di 9", "inchiostro/secondario"));
testata.appendChild(nomi);

const pastiglia = row(6, { name: "Pastiglia di stato" });
pastiglia.counterAxisAlignItems = "CENTER";
pad(pastiglia, 11, 6);
pastiglia.cornerRadius = 100;
pastiglia.fills = [wash("accento/navigazione", 0.16)];
pastiglia.strokes = [paint("bordo/sottile")];
pastiglia.strokeWeight = 0.5;
pastiglia.appendChild(glifo("water.waves", 11, "accento/navigazione"));
pastiglia.appendChild(txt("Etichetta metrica", "Giorno di mare", "accento/navigazione"));
testata.appendChild(pastiglia);

contenuto.appendChild(testata);
testata.layoutSizingHorizontal = "FILL";
nomi.layoutSizingHorizontal = "FILL";

// --- avviso sull'ora di bordo ----------------------------------------------
const avviso = card(20);
pad(avviso, 14, 12);
const avvisoRiga = row(10);
avvisoRiga.counterAxisAlignItems = "CENTER";
avvisoRiga.appendChild(glifo("exclamationmark.triangle.fill", 13, "accento/porto"));
const avvisoTesto = txt("Dettaglio riga",
  "Il telefono è 6 ore avanti rispetto all'ora di bordo. Gli orari qui sono in ora di bordo.",
  "inchiostro/secondario");
avvisoTesto.textAutoResize = "HEIGHT";
avvisoRiga.appendChild(avvisoTesto);
avviso.appendChild(avvisoRiga);
contenuto.appendChild(avviso);
avviso.layoutSizingHorizontal = "FILL";
avvisoRiga.layoutSizingHorizontal = "FILL";
avvisoTesto.layoutSizingHorizontal = "FILL";

// --- l'eroe: la traversata -------------------------------------------------
const eroe = card(24, "accento/navigazione");
pad(eroe, 16, 16);
eroe.itemSpacing = 10;
eroe.name = "Traversata";

const eroeTesta = row(8);
eroeTesta.primaryAxisAlignItems = "SPACE_BETWEEN";
eroeTesta.counterAxisAlignItems = "CENTER";
const statoRiga = row(6);
statoRiga.counterAxisAlignItems = "CENTER";
statoRiga.appendChild(glifo("water.waves", 12, "accento/navigazione"));
statoRiga.appendChild(txt("Titolo riga", "In navigazione", "accento/navigazione"));
eroeTesta.appendChild(statoRiga);
const chip = row(5, { name: "Chip di provenienza" });
chip.counterAxisAlignItems = "CENTER";
pad(chip, 9, 5);
chip.cornerRadius = 100;
chip.fills = [wash("inchiostro/primario", 0.06)];
chip.strokes = [paint("bordo/sottile")];
chip.strokeWeight = 0.5;
chip.appendChild(glifo("calendar", 9, "inchiostro/secondario"));
chip.appendChild(txt("Tecnico", "orario pubblicato", "inchiostro/secondario"));
eroeTesta.appendChild(chip);
eroe.appendChild(eroeTesta);
eroeTesta.layoutSizingHorizontal = "FILL";

eroe.appendChild(txt("Dettaglio riga", "All'arrivo a Puerto Plata", "inchiostro/secondario"));

const cifreRiga = row(8);
cifreRiga.counterAxisAlignItems = "BASELINE";
cifreRiga.appendChild(txt("Display / Countdown", "19:29:52", "inchiostro/primario"));
cifreRiga.appendChild(txt("Etichetta metrica", "h · m · s", "inchiostro/terziario"));
eroe.appendChild(cifreRiga);

eroe.appendChild(txt("Dettaglio riga", "previsto lun 31 ago · 09:00", "inchiostro/secondario"));

// L'onda: traccia e parte percorsa disegnate dalla **stessa** forma. Erano due
// onde con fasi diverse, e combaciavano solo ogni tanto.
const onda = figma.createFrame();
onda.name = "Avanzamento — onda";
onda.resize(340, 14);
onda.fills = [];
onda.clipsContent = true;
const d = (() => {
  let p = "M 0 7";
  for (let x = 0; x <= 340; x += 10) {
    p += " Q " + (x + 5) + " " + (7 + (x / 10 % 2 === 0 ? -5 : 5)) + " " + (x + 10) + " 7";
  }
  return p;
})();
const ondaTraccia = figma.createVector();
ondaTraccia.vectorPaths = [{ windingRule: "NONE", data: d }];
ondaTraccia.strokes = [wash("inchiostro/primario", 0.18)];
ondaTraccia.strokeWeight = 4;
ondaTraccia.strokeCap = "ROUND";
ondaTraccia.fills = [];
ondaTraccia.name = "traccia";
onda.appendChild(ondaTraccia);
ondaTraccia.x = 0; ondaTraccia.y = 0;

const ondaFatta = figma.createVector();
ondaFatta.vectorPaths = [{ windingRule: "NONE", data: d }];
ondaFatta.strokes = [paint("accento/navigazione")];
ondaFatta.strokeWeight = 4;
ondaFatta.strokeCap = "ROUND";
ondaFatta.fills = [];
ondaFatta.name = "percorso";
onda.appendChild(ondaFatta);
ondaFatta.x = 0; ondaFatta.y = 0;
// La parte percorsa è la stessa onda, mascherata: mai una seconda onda.
const maschera = figma.createRectangle();
maschera.resize(150, 14);
maschera.x = 0; maschera.y = 0;
maschera.name = "maschera del percorso";
onda.appendChild(maschera);
maschera.isMask = true;
onda.insertChild(1, maschera);

const ondaBox = row(0);
ondaBox.appendChild(onda);
eroe.appendChild(ondaBox);
ondaBox.layoutSizingHorizontal = "FILL";

const porti = row(8);
porti.primaryAxisAlignItems = "SPACE_BETWEEN";
porti.appendChild(txt("Dettaglio riga", "Gustavia", "inchiostro/secondario"));
porti.appendChild(txt("Dettaglio riga", "Puerto Plata", "inchiostro/secondario"));
eroe.appendChild(porti);
porti.layoutSizingHorizontal = "FILL";

const f1 = filo();
eroe.appendChild(f1);
f1.layoutSizingHorizontal = "FILL";
eroe.appendChild(grandezze([
  ["11,8 kt", "Velocità"], ["284°", "Rotta"], ["230 mn", "Alla meta"]
]));
eroe.children[eroe.children.length - 1].layoutSizingHorizontal = "FILL";

contenuto.appendChild(eroe);
eroe.layoutSizingHorizontal = "FILL";

// --- la carta --------------------------------------------------------------
const carta = card(24);
carta.name = "Carta";
carta.clipsContent = true;
const cartaBox = figma.createFrame();
cartaBox.name = "Disegno della carta — sostituire con lo screenshot";
cartaBox.resize(370, 200);
cartaBox.fills = [wash("fondo/mare-alto", 1)];
carta.appendChild(cartaBox);
const cartaPiede = row(8);
cartaPiede.counterAxisAlignItems = "CENTER";
cartaPiede.primaryAxisAlignItems = "SPACE_BETWEEN";
pad(cartaPiede, 14, 12);
cartaPiede.appendChild(txt("Titolo riga", "Verso Puerto Plata", "inchiostro/primario"));
const bottoneCarta = row(0);
pad(bottoneCarta, 12, 7);
bottoneCarta.cornerRadius = 100;
bottoneCarta.fills = [wash("inchiostro/primario", 0.10)];
bottoneCarta.appendChild(txt("Dettaglio riga", "Carta", "inchiostro/primario"));
cartaPiede.appendChild(bottoneCarta);
carta.appendChild(cartaPiede);
contenuto.appendChild(carta);
carta.layoutSizingHorizontal = "FILL";
cartaBox.layoutSizingHorizontal = "FILL";
cartaPiede.layoutSizingHorizontal = "FILL";

// --- lo stato del mare -----------------------------------------------------
const mare = card(24);
mare.name = "Stato del mare";
pad(mare, 16, 16);
mare.itemSpacing = 12;
const mareTesta = row(8);
mareTesta.primaryAxisAlignItems = "SPACE_BETWEEN";
mareTesta.counterAxisAlignItems = "CENTER";
mareTesta.appendChild(txt("Eyebrow", "Mare", "inchiostro/terziario", { upper: true }));
const fresco = row(5);
fresco.counterAxisAlignItems = "CENTER";
fresco.appendChild(glifo("checkmark.circle", 11, "inchiostro/terziario"));
fresco.appendChild(txt("Etichetta metrica", "aggiornato", "inchiostro/terziario"));
mareTesta.appendChild(fresco);
mare.appendChild(mareTesta);
mareTesta.layoutSizingHorizontal = "FILL";

const mareRiga = row(12);
mareRiga.counterAxisAlignItems = "CENTER";
mareRiga.appendChild(glifo("cloud.sun.fill", 26, "inchiostro/primario", "Regular"));
const mareTesti = col(2);
mareTesti.appendChild(txt("Titolo schermata", "Mosso", "inchiostro/primario"));
mareTesti.appendChild(txt("Dettaglio riga", "Movimento appena percettibile", "inchiostro/secondario"));
mareRiga.appendChild(mareTesti);
mareRiga.appendChild(txt("Display / Totale", "24°", "inchiostro/primario"));
mare.appendChild(mareRiga);
mareRiga.layoutSizingHorizontal = "FILL";
mareTesti.layoutSizingHorizontal = "FILL";

const f2 = filo();
mare.appendChild(f2);
f2.layoutSizingHorizontal = "FILL";
mare.appendChild(grandezze([["1,0 m", "Onda"], ["8 kn SE", "Vento"], ["29°", "Acqua"]]));
mare.children[mare.children.length - 1].layoutSizingHorizontal = "FILL";
contenuto.appendChild(mare);
mare.layoutSizingHorizontal = "FILL";

const barra = barraSchede("Oggi");
s.appendChild(barra);
barra.x = 14;
barra.y = H - barra.height - 26;

await s.screenshot({ scale: 1 });
return { createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height };
