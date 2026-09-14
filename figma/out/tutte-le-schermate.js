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
  // Il vetro sotto, la tinta sopra: l'ordine conta, e la seconda assegnazione
  // che c'era prima cancellava la prima senza dirlo.
  f.fills = tinta ? [wash("fondo/vetro", 1), wash(tinta, 0.12)] : [paint("fondo/vetro")];
  f.strokes = [paint("bordo/sottile")];
  f.strokeWeight = 0.5;
  f.cornerRadius = raggio;
  if (ES["Vetro / Card"]) f.effectStyleId = ES["Vetro / Card"].id;
  return f;
};

/** Un glifo SF Symbol, per nome.
 *
 *  Se il convertitore non conosce il nome lancia `RangeError`. In uno script che
 *  costruisce cinque schermate, un solo nome ignoto le farebbe fallire tutte e
 *  cinque: qui si segna il buco e si prosegue, invece di perdere tutto per
 *  un'icona. I nomi mancanti tornano nel valore di ritorno, così si vedono. */
const glifiMancanti = [];
const glifo = (nome, size, coloreVar, peso) => {
  const t = figma.createText();
  t.fontName = { family: "SF Pro", style: peso || "Semibold" };
  t.fontSize = size;
  try {
    t.characters = figma.util.getSfSymbolCharacter(nome);
  } catch (e) {
    if (glifiMancanti.indexOf(nome) < 0) glifiMancanti.push(nome);
    t.characters = "\u25CF";
  }
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

const risultati = [];

// ==== 01-oggi-in-porto.js =======================================
{
// --- Oggi, giorno di porto -------------------------------------------------
// La schermata che conta: un numero solo, quello che manca al rientro a bordo.

const s = schermata("Oggi — in porto", 0,
  ["fondo/porto-alto", { r: 11/255, g: 23/255, b: 37/255, a: 1 }, "fondo/abisso"]);
page.appendChild(s);

const stato = await barraDiStato();
s.appendChild(stato);
stato.x = 0; stato.y = 0;

// Colonna del contenuto: margine 16, passo 12, come nell'app.
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
nomi.appendChild(txt("Sottotitolo schermata", "Giorno 5 di 9", "inchiostro/secondario"));
testata.appendChild(nomi);

const pastiglia = row(6, { name: "Pastiglia di stato" });
pastiglia.counterAxisAlignItems = "CENTER";
pad(pastiglia, 11, 6);
pastiglia.cornerRadius = 100;
pastiglia.fills = [wash("accento/porto", 0.16)];
pastiglia.strokes = [paint("bordo/sottile")];
pastiglia.strokeWeight = 0.5;
pastiglia.appendChild(glifo("ferry", 11, "accento/porto"));
pastiglia.appendChild(txt("Etichetta metrica", "In porto", "accento/porto"));
testata.appendChild(pastiglia);

contenuto.appendChild(testata);
testata.layoutSizingHorizontal = "FILL";
nomi.layoutSizingHorizontal = "FILL";

// --- avviso sull'ora di bordo ----------------------------------------------
// Sta qui perché è così che si perde la nave: il telefono si riallinea da solo,
// la nave no.
const avviso = card(20, "accento/porto");
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

// --- l'eroe: il countdown all'all aboard -----------------------------------
const eroe = card(24, "accento/porto");
pad(eroe, 16, 16);
eroe.itemSpacing = 14;
eroe.name = "Rientro a bordo";

const eroeTesta = row(8);
eroeTesta.counterAxisAlignItems = "CENTER";
eroeTesta.appendChild(txt("Eyebrow", "Puerto Plata", "accento/porto", { upper: true }));
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
eroeTesta.primaryAxisAlignItems = "SPACE_BETWEEN";

// L'anello si riempie da **attracco a all aboard**, lo stesso evento del numero
// che abbraccia. Il brief lo faceva misurare la sosta: un anello e un numero che
// contano cose diverse chiedono a chi guarda di scegliere.
const anello = figma.createFrame();
anello.name = "Anello";
anello.resize(232, 232);
anello.fills = [];
anello.clipsContent = false;

const SPESSORE = 10, RAGGIO = 116;
const traccia = figma.createEllipse();
traccia.resize(232, 232);
traccia.x = 0; traccia.y = 0;
traccia.fills = [wash("inchiostro/primario", 0.16)];
traccia.strokes = [];
traccia.arcData = { startingAngle: 0, endingAngle: 2 * Math.PI, innerRadius: (RAGGIO - SPESSORE) / RAGGIO };
traccia.name = "traccia";
anello.appendChild(traccia);

const arco = figma.createEllipse();
arco.resize(232, 232);
arco.x = 0; arco.y = 0;
arco.fills = [paint("accento/porto")];
arco.strokes = [];
arco.arcData = {
  startingAngle: -Math.PI / 2,
  endingAngle: -Math.PI / 2 + 2 * Math.PI * 0.68,
  innerRadius: (RAGGIO - SPESSORE) / RAGGIO
};
arco.name = "avanzamento";
anello.appendChild(arco);

const dentro = col(4, { name: "Dentro l'anello" });
dentro.counterAxisAlignItems = "CENTER";
dentro.appendChild(txt("Eyebrow", "Rientro a bordo", "inchiostro/secondario", { upper: true }));
const cifre = txt("Display / Countdown", "2:59:52", "inchiostro/primario");
dentro.appendChild(cifre);
dentro.appendChild(txt("Dettaglio riga", "entro le 17:30", "inchiostro/secondario"));
anello.appendChild(dentro);
dentro.x = (232 - dentro.width) / 2;
dentro.y = (232 - dentro.height) / 2;

const anelloBox = row(0, { name: "Anello (centrato)" });
anelloBox.primaryAxisAlignItems = "CENTER";
anelloBox.appendChild(anello);
eroe.appendChild(anelloBox);
anelloBox.layoutSizingHorizontal = "FILL";

const f1 = filo();
eroe.appendChild(f1);
f1.layoutSizingHorizontal = "FILL";

eroe.appendChild(grandezze([
  ["09:00", "Attracco"], ["18:00", "Partenza"], ["9h", "Sosta"]
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
const cartaPiede = row(8, { name: "Piede della carta" });
cartaPiede.counterAxisAlignItems = "CENTER";
cartaPiede.primaryAxisAlignItems = "SPACE_BETWEEN";
pad(cartaPiede, 14, 12);
cartaPiede.appendChild(txt("Titolo riga", "Puerto Plata", "inchiostro/primario"));
const bottoneCarta = row(0, { name: "Carta" });
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
mareTesta.appendChild(txt("Eyebrow", "In porto", "inchiostro/terziario", { upper: true }));
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
mareTesti.appendChild(txt("Titolo schermata", "Molto mosso", "inchiostro/primario"));
mareTesti.appendChild(txt("Dettaglio riga", "Beccheggio avvertibile", "inchiostro/secondario"));
mareRiga.appendChild(mareTesti);
const gradi = txt("Display / Totale", "30°", "inchiostro/primario");
mareRiga.appendChild(gradi);
mare.appendChild(mareRiga);
mareRiga.layoutSizingHorizontal = "FILL";
mareTesti.layoutSizingHorizontal = "FILL";

const f2 = filo();
mare.appendChild(f2);
f2.layoutSizingHorizontal = "FILL";
mare.appendChild(grandezze([["1,4 m", "Onda"], ["6 kn NE", "Vento"], ["30°", "Acqua"]]));
mare.children[mare.children.length - 1].layoutSizingHorizontal = "FILL";

contenuto.appendChild(mare);
mare.layoutSizingHorizontal = "FILL";

// --- la barra delle schede -------------------------------------------------
const barra = barraSchede("Oggi");
s.appendChild(barra);
barra.x = 14;
barra.y = H - barra.height - 26;

await s.screenshot({ scale: 0.75 });
risultati.push({ createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height });
}

// ==== 02-oggi-in-mare.js ========================================
{
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

// La parte percorsa è la **stessa** onda, ritagliata da un riquadro. Erano due
// onde con fasi diverse, e combaciavano solo ogni tanto. Un riquadro che
// ritaglia è più prevedibile di una maschera, che dipende dall'ordine dei livelli.
const ritaglio = figma.createFrame();
ritaglio.name = "percorso (ritagliato)";
ritaglio.resize(150, 14);
ritaglio.x = 0; ritaglio.y = 0;
ritaglio.fills = [];
ritaglio.clipsContent = true;
onda.appendChild(ritaglio);

const ondaFatta = figma.createVector();
ondaFatta.vectorPaths = [{ windingRule: "NONE", data: d }];
ondaFatta.strokes = [paint("accento/navigazione")];
ondaFatta.strokeWeight = 4;
ondaFatta.strokeCap = "ROUND";
ondaFatta.fills = [];
ondaFatta.name = "percorso";
ritaglio.appendChild(ondaFatta);
ondaFatta.x = 0; ondaFatta.y = 0;

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

await s.screenshot({ scale: 0.75 });
risultati.push({ createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height });
}

// ==== 03-itinerario.js ==========================================
{
// --- Itinerario ------------------------------------------------------------
// Nove righe: sette scali e due giorni di mare. Le righe si somigliano, quindi
// si costruisce **un componente** e si posano istanze — non nove riquadri quasi
// uguali.

const s = schermata("Itinerario", 920,
  ["fondo/mare-alto", "fondo/mare", "fondo/abisso"]);
page.appendChild(s);

const stato = await barraDiStato();
s.appendChild(stato);
stato.x = 0; stato.y = 0;

const contenuto = col(10, { name: "Contenuto" });
pad(contenuto, MARGINE, 0);
s.appendChild(contenuto);
contenuto.x = 0; contenuto.y = 59;
contenuto.resize(W, 100);
contenuto.layoutSizingHorizontal = "FIXED";

// --- testata ---------------------------------------------------------------
const testata = row(12, { name: "Testata" });
testata.counterAxisAlignItems = "CENTER";
const nomi = col(2);
nomi.counterAxisAlignItems = "CENTER";
nomi.appendChild(txt("Titolo schermata", "Stella Australe", "inchiostro/primario"));
nomi.appendChild(txt("Sottotitolo schermata", "8 notti · 5 scali", "inchiostro/secondario"));
testata.appendChild(nomi);
const modifica = row(0, { name: "Modifica" });
pad(modifica, 14, 8);
modifica.cornerRadius = 100;
modifica.fills = [wash("inchiostro/primario", 0.08)];
modifica.strokes = [paint("bordo/sottile")];
modifica.strokeWeight = 0.5;
modifica.appendChild(txt("Titolo riga", "Modifica", "accento/azione"));
testata.appendChild(modifica);
contenuto.appendChild(testata);
testata.layoutSizingHorizontal = "FILL";
nomi.layoutSizingHorizontal = "FILL";
testata.primaryAxisAlignItems = "SPACE_BETWEEN";

// --- il componente riga ----------------------------------------------------
// Una riga sola, con le proprietà di testo esposte: il resto sono istanze.
const modello = figma.createComponent();
modello.name = "Riga di scalo";
modello.description =
  "Una tappa dell'itinerario. Il giorno a sinistra, il porto e la finestra a destra. " +
  "Il filo verticale è continuo per uno scalo e tratteggiato per un giorno di mare: " +
  "la differenza non è affidata al solo colore.";
modello.layoutMode = "HORIZONTAL";
modello.itemSpacing = 12;
modello.counterAxisAlignItems = "CENTER";
modello.primaryAxisSizingMode = "AUTO";
modello.counterAxisSizingMode = "AUTO";
pad(modello, 14, 14);
modello.cornerRadius = 20;
modello.fills = [paint("fondo/vetro")];
modello.strokes = [paint("bordo/sottile")];
modello.strokeWeight = 0.5;
if (ES["Vetro / Card"]) modello.effectStyleId = ES["Vetro / Card"].id;
modello.resize(370, 76);
modello.layoutSizingHorizontal = "FIXED";

const giorno = col(0, { name: "Giorno" });
giorno.counterAxisAlignItems = "CENTER";
giorno.resize(52, 44);
const giornoSett = txt("Etichetta metrica", "GIO", "inchiostro/terziario", { name: "Settimana" });
const giornoNum = txt("Titolo schermata", "27", "inchiostro/primario", { name: "Numero" });
giorno.appendChild(giornoSett);
giorno.appendChild(giornoNum);
modello.appendChild(giorno);
giorno.layoutSizingHorizontal = "FIXED";

const separatore = figma.createRectangle();
separatore.name = "Filo";
separatore.resize(2, 40);
separatore.cornerRadius = 1;
separatore.fills = [wash("inchiostro/primario", 0.22)];
modello.appendChild(separatore);

const dettagli = col(3, { name: "Dettagli" });
const porto = txt("Titolo riga", "San Juan", "inchiostro/primario", { name: "Porto" });
const finestra = txt("Dettaglio riga", "14:00 → 20:00 · banchina", "inchiostro/secondario", { name: "Finestra" });
dettagli.appendChild(porto);
dettagli.appendChild(finestra);
modello.appendChild(dettagli);
dettagli.layoutSizingHorizontal = "FILL";

const freccia = glifo("chevron.right", 13, "inchiostro/terziario");
modello.appendChild(freccia);

modello.x = -600; modello.y = 0;   // il modello sta fuori dalla schermata
page.appendChild(modello);

// Proprietà di testo: è così che le istanze si riempiono senza staccarsi.
const pSett = modello.addComponentProperty("Settimana", "TEXT", "GIO");
const pNum = modello.addComponentProperty("Numero", "TEXT", "27");
const pPorto = modello.addComponentProperty("Porto", "TEXT", "San Juan");
const pFinestra = modello.addComponentProperty("Finestra", "TEXT", "14:00 → 20:00 · banchina");
giornoSett.componentPropertyReferences = { characters: pSett };
giornoNum.componentPropertyReferences = { characters: pNum };
porto.componentPropertyReferences = { characters: pPorto };
finestra.componentPropertyReferences = { characters: pFinestra };

// --- le nove righe ---------------------------------------------------------
const tappe = [
  ["GIO", "27", "San Juan", "14:00 → 20:00 · banchina", "scalo"],
  ["VEN", "28", "Charlotte Amalie", "07:00 → 16:00 · banchina", "scalo"],
  ["SAB", "29", "Gustavia", "08:00 → 18:00 · tender", "scalo"],
  ["DOM", "30", "Giorno di mare", "Verso Puerto Plata · 460 mn", "mare"],
  ["LUN", "31", "Puerto Plata", "09:00 → 18:00 · banchina", "oggi"],
  ["MAR", "1", "Grand Turk", "08:00 → 17:00 · banchina", "domani"],
  ["MER", "2", "Giorno di mare", "Verso Nassau · 405 mn", "mare"],
  ["GIO", "3", "Nassau", "07:00 → 14:00 · banchina", "scalo"],
  ["VEN", "4", "Miami", "07:00 · banchina", "scalo"]
];

const istanze = [];
for (const [sett, num, nome, finestraTesto, tipo] of tappe) {
  const i = modello.createInstance();
  i.setProperties({
    [pSett]: sett, [pNum]: num, [pPorto]: nome, [pFinestra]: finestraTesto
  });
  i.name = nome;

  // Oggi si distingue con colore **e** parola, mai col solo colore.
  if (tipo === "oggi" || tipo === "domani") {
    const accento = tipo === "oggi" ? "accento/porto" : "accento/porto";
    i.fills = [wash("fondo/vetro", 1), wash(accento, 0.14)];
    const filoVerticale = i.findOne(n => n.name === "Filo");
    if (filoVerticale) filoVerticale.fills = [paint(accento)];
    const etichetta = i.findOne(n => n.name === "Numero");
    if (etichetta) etichetta.fills = [paint(accento)];
  }
  if (tipo === "mare") {
    const filoVerticale = i.findOne(n => n.name === "Filo");
    if (filoVerticale) filoVerticale.fills = [wash("accento/navigazione", 0.45)];
  }

  contenuto.appendChild(i);
  i.layoutSizingHorizontal = "FILL";
  istanze.push(i.id);
}

const barra = barraSchede("Itinerario");
s.appendChild(barra);
barra.x = 14;
barra.y = H - barra.height - 26;

await s.screenshot({ scale: 0.75 });
risultati.push({
  createdNodeIds: [s.id, modello.id].concat(istanze),
  schermata: s.id,
  componenteRiga: modello.id,
  altezzaContenuto: contenuto.height
});
}

// ==== 04-diario.js ==============================================
{
// --- Diario ----------------------------------------------------------------
// Non è una schermata operativa: non serve a prendere la nave. Qui i numeri
// possono essere grandi e lenti.

const s = schermata("Diario", 1380,
  ["fondo/mare-alto", "fondo/mare", "fondo/abisso"]);
page.appendChild(s);

const stato = await barraDiStato();
s.appendChild(stato);
stato.x = 0; stato.y = 0;

const contenuto = col(16, { name: "Contenuto" });
pad(contenuto, MARGINE, 0);
s.appendChild(contenuto);
contenuto.x = 0; contenuto.y = 59;
contenuto.resize(W, 100);
contenuto.layoutSizingHorizontal = "FIXED";

const titolo = txt("Display / Totale", "Diario", "inchiostro/primario", { name: "Titolo" });
contenuto.appendChild(titolo);

// --- i totali --------------------------------------------------------------
const totali = card(28);
totali.name = "Totali";
pad(totali, 20, 20);
totali.itemSpacing = 14;
totali.counterAxisAlignItems = "CENTER";

const miglia = txt("Display / Totale", "1.216 mn", "inchiostro/primario");
totali.appendChild(miglia);
totali.appendChild(txt("Eyebrow", "Miglia percorse", "inchiostro/terziario", { upper: true }));

const f1 = filo();
totali.appendChild(f1);
f1.layoutSizingHorizontal = "FILL";

totali.appendChild(grandezze([
  ["8", "Giorni di mare"], ["4", "Porti"], ["4", "Crociere"]
]));
totali.children[totali.children.length - 1].layoutSizingHorizontal = "FILL";
contenuto.appendChild(totali);
totali.layoutSizingHorizontal = "FILL";

// --- i primati -------------------------------------------------------------
const primati = card(24);
primati.name = "Primati";
pad(primati, 16, 4);
const righe = [
  ["arrow.left.and.right", "Traversata più lunga", "Gustavia → Puerto Plata · 460 mn"],
  ["arrow.up", "Punto più a nord", "Puerto Plata · 19°48'N"],
  ["arrow.down", "Punto più a sud", "Gustavia · 17°54'N"],
  ["ferry.fill", "Nave", "Stella Australe"]
];
righe.forEach(([simbolo, etichetta, dettaglio], i) => {
  if (i > 0) {
    const f = filo();
    primati.appendChild(f);
    f.layoutSizingHorizontal = "FILL";
  }
  const r = row(12);
  r.counterAxisAlignItems = "MIN";
  pad(r, 0, 11);
  const g = glifo(simbolo, 12, "accento/navigazione");
  r.appendChild(g);
  const c = col(2);
  c.appendChild(txt("Eyebrow", etichetta, "inchiostro/terziario", { upper: true }));
  c.appendChild(txt("Titolo riga", dettaglio, "inchiostro/primario"));
  r.appendChild(c);
  primati.appendChild(r);
  r.layoutSizingHorizontal = "FILL";
  c.layoutSizingHorizontal = "FILL";
});
contenuto.appendChild(primati);
primati.layoutSizingHorizontal = "FILL";

// --- i timbri dei porti ----------------------------------------------------
const timbri = card(24);
timbri.name = "Porti toccati";
pad(timbri, 16, 16);
timbri.itemSpacing = 10;
timbri.appendChild(txt("Eyebrow", "Porti toccati", "inchiostro/terziario", { upper: true }));

// Le pastiglie vanno a capo: qui si impaginano su due righe a mano, perché
// l'auto-layout con ritorno a capo non ha un equivalente esatto dell'app.
const timbriDati = [["Puerto Plata", 0], ["Gustavia", 4], ["Charlotte Amalie", 4], ["San Juan", 4]];
let riga = row(7);
riga.layoutWrap = "WRAP";
riga.counterAxisSpacing = 7;
for (const [nome, volte] of timbriDati) {
  const p = row(5);
  p.counterAxisAlignItems = "CENTER";
  pad(p, 10, 6);
  p.cornerRadius = 100;
  p.fills = [wash("inchiostro/primario", 0.07)];
  p.strokes = [paint("bordo/sottile")];
  p.strokeWeight = 0.5;
  p.appendChild(txt("Dettaglio riga", nome, "inchiostro/primario"));
  if (volte > 1) p.appendChild(txt("Etichetta metrica", "×" + volte, "accento/navigazione"));
  riga.appendChild(p);
}
timbri.appendChild(riga);
riga.layoutSizingHorizontal = "FILL";
contenuto.appendChild(timbri);
timbri.layoutSizingHorizontal = "FILL";

// --- le crociere -----------------------------------------------------------
const elenco = col(10, { name: "Le tue crociere" });
elenco.appendChild(txt("Eyebrow", "Le tue crociere", "inchiostro/terziario", { upper: true }));

const crociera = card(22);
pad(crociera, 16, 16);
crociera.itemSpacing = 8;
crociera.name = "Stella Australe";
const cTesta = row(8);
cTesta.counterAxisAlignItems = "CENTER";
cTesta.appendChild(txt("Titolo riga", "Stella Australe", "inchiostro/primario"));
const inCorso = row(0);
pad(inCorso, 7, 2);
inCorso.cornerRadius = 100;
inCorso.fills = [wash("accento/navigazione", 0.14)];
inCorso.appendChild(txt("Etichetta metrica", "in corso", "accento/navigazione"));
cTesta.appendChild(inCorso);
crociera.appendChild(cTesta);
crociera.appendChild(txt("Dettaglio riga", "24 – 31 ago 2026", "inchiostro/secondario"));
crociera.appendChild(txt("Dettaglio riga",
  "San Juan · Charlotte Amalie · Gustavia · Puerto Plata", "inchiostro/terziario"));
const cPiede = row(14);
cPiede.counterAxisAlignItems = "CENTER";
const m1 = row(5); m1.counterAxisAlignItems = "CENTER";
m1.appendChild(glifo("point.topleft.down.to.point.bottomright.curvepath", 11, "inchiostro/secondario"));
m1.appendChild(txt("Etichetta metrica", "1.216 mn", "inchiostro/secondario"));
const m2 = row(5); m2.counterAxisAlignItems = "CENTER";
m2.appendChild(glifo("water.waves", 11, "inchiostro/secondario"));
m2.appendChild(txt("Etichetta metrica", "8 giorni in mare", "inchiostro/secondario"));
cPiede.appendChild(m1);
cPiede.appendChild(m2);
crociera.appendChild(cPiede);
elenco.appendChild(crociera);
crociera.layoutSizingHorizontal = "FILL";
contenuto.appendChild(elenco);
elenco.layoutSizingHorizontal = "FILL";

const barra = barraSchede("Diario");
s.appendChild(barra);
barra.x = 14;
barra.y = H - barra.height - 26;

await s.screenshot({ scale: 0.75 });
risultati.push({ createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height });
}

// ==== 05-nave.js ================================================
{
// --- Nave ------------------------------------------------------------------
// La foto sta in un **overlay**, non come figlia diretta: a `.fill` l'immagine è
// più larga del riquadro e da figlia imporrebbe quella larghezza a tutta la
// colonna. È il baco che mandava nome e crediti oltre il bordo dello schermo.

const s = schermata("Nave", 1840,
  ["fondo/mare-alto", "fondo/mare", "fondo/abisso"]);
page.appendChild(s);

const stato = await barraDiStato();
s.appendChild(stato);
stato.x = 0; stato.y = 0;

const titoloBarra = row(0, { name: "Titolo di navigazione" });
titoloBarra.primaryAxisAlignItems = "CENTER";
pad(titoloBarra, 16, 10);
titoloBarra.appendChild(txt("Titolo riga", "Nave", "inchiostro/primario"));
s.appendChild(titoloBarra);
titoloBarra.x = 0; titoloBarra.y = 59;
titoloBarra.resize(W, titoloBarra.height);
titoloBarra.layoutSizingHorizontal = "FIXED";

const contenuto = col(12, { name: "Contenuto" });
pad(contenuto, MARGINE, 0);
s.appendChild(contenuto);
contenuto.x = 0; contenuto.y = 108;
contenuto.resize(W, 100);
contenuto.layoutSizingHorizontal = "FIXED";

// --- la foto ---------------------------------------------------------------
const foto = figma.createFrame();
foto.name = "Foto della nave — sostituire con l'immagine da Commons";
foto.resize(370, 190);
foto.cornerRadius = 22;
foto.fills = [wash("fondo/mare-alto", 1)];
foto.strokes = [paint("bordo/sottile")];
foto.strokeWeight = 0.5;
foto.clipsContent = true;

// Il credito sta **sulla** foto: è la condizione con cui l'autore la mette a
// disposizione, non una nota a piè di pagina.
const credito = row(0, { name: "Credito" });
pad(credito, 7, 4);
credito.cornerRadius = 100;
credito.fills = [wash("fondo/abisso", 0.70)];
credito.appendChild(txt("Etichetta metrica", "Corey Seeman · CC BY-SA 4.0", "inchiostro/secondario"));
foto.appendChild(credito);
credito.x = 370 - credito.width - 8;
credito.y = 190 - credito.height - 8;

contenuto.appendChild(foto);
foto.layoutSizingHorizontal = "FILL";

// --- nome e armatore -------------------------------------------------------
const intestazione = col(3, { name: "Intestazione" });
intestazione.appendChild(txt("Display / Totale", "Icon of the Seas", "inchiostro/primario"));
intestazione.appendChild(txt("Sottotitolo schermata", "Royal Caribbean International", "inchiostro/secondario"));
contenuto.appendChild(intestazione);
intestazione.layoutSizingHorizontal = "FILL";

// --- le misure -------------------------------------------------------------
// Quattro grandezze su tre colonne: la quarta va a capo ma **tiene la colonna**,
// se no si allargherebbe per tutta la riga e uscirebbe di squadro.
const misure = card(24);
misure.name = "Misure";
pad(misure, 16, 16);
misure.itemSpacing = 14;
misure.appendChild(grandezze([["248.663 GT", "Stazza"], ["364 m", "Lunghezza"], ["48 m", "Larghezza"]]));
misure.children[0].layoutSizingHorizontal = "FILL";

const secondaRiga = row(12);
secondaRiga.counterAxisAlignItems = "MIN";
const cellaAnno = col(3);
cellaAnno.appendChild(txt("Valore metrica", "2024", "inchiostro/primario"));
cellaAnno.appendChild(txt("Etichetta metrica", "In servizio", "inchiostro/terziario", { upper: true }));
secondaRiga.appendChild(cellaAnno);
for (let i = 0; i < 2; i++) {
  const vuota = col(0, { name: "colonna vuota" });
  secondaRiga.appendChild(vuota);
  vuota.layoutSizingHorizontal = "FILL";
}
cellaAnno.layoutSizingHorizontal = "FILL";
misure.appendChild(secondaRiga);
secondaRiga.layoutSizingHorizontal = "FILL";
contenuto.appendChild(misure);
misure.layoutSizingHorizontal = "FILL";

// --- gli identificativi ----------------------------------------------------
const identificativi = card(20);
identificativi.name = "Identificativi";
pad(identificativi, 16, 16);
identificativi.itemSpacing = 10;
for (const [etichetta, valore] of [["IMO", "9829930"], ["MMSI", "311001178"]]) {
  const r = row(12);
  r.primaryAxisAlignItems = "SPACE_BETWEEN";
  r.counterAxisAlignItems = "CENTER";
  r.appendChild(txt("Eyebrow", etichetta, "inchiostro/terziario", { upper: true }));
  r.appendChild(txt("Tecnico", valore, "inchiostro/primario"));
  identificativi.appendChild(r);
  r.layoutSizingHorizontal = "FILL";
}
contenuto.appendChild(identificativi);
identificativi.layoutSizingHorizontal = "FILL";

// --- la nota sulle fonti ---------------------------------------------------
const fonti = txt("Etichetta metrica",
  "Dati da Wikidata, di pubblico dominio. Le fotografie vengono da Wikimedia Commons e restano dei rispettivi autori.",
  "inchiostro/terziario", { name: "Fonti" });
fonti.textAutoResize = "HEIGHT";
contenuto.appendChild(fonti);
fonti.layoutSizingHorizontal = "FILL";

const barra = barraSchede("Nave");
s.appendChild(barra);
barra.x = 14;
barra.y = H - barra.height - 26;

await s.screenshot({ scale: 0.75 });
risultati.push({ createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height });
}

return { schermate: risultati, glifiMancanti };
