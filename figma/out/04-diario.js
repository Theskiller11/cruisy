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

await s.screenshot({ scale: 1 });
return { createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height };
