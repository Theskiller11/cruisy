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

await s.screenshot({ scale: 1 });
return { createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height };
