// --- Pre-crociera, l'attesa ------------------------------------------------
// Si accende oltre le 12 ore dall'imbarco. A crociera lontana non c'è niente da
// misurare al secondo, quindi non si mostrano strumenti: quanti giorni mancano,
// una frase, e due righe di contorno.
//
// NB: questo script **non usa il preambolo**: si porta i propri aiutanti, perché
// serve anche il peso Bold per il nome della nave e una `infoRow` che gli altri
// non hanno.

const W = 402, H = 874;
const page = await figma.getNodeByIdAsync("6:5");
await figma.setCurrentPageAsync(page);

for (const f of [
  { family: "SF Pro", style: "Regular" },
  { family: "SF Pro", style: "Medium" },
  { family: "SF Pro", style: "Semibold" },
  { family: "SF Pro", style: "Bold" },
  { family: "SF Pro Rounded", style: "Semibold" },
  { family: "Roboto Mono", style: "Medium" }
]) await figma.loadFontAsync(f);

const vars = await figma.variables.getLocalVariablesAsync();
const V = Object.fromEntries(vars.map(v => [v.name, v]));
const TS = Object.fromEntries((await figma.getLocalTextStylesAsync()).map(s => [s.name, s]));
const ES = Object.fromEntries((await figma.getLocalEffectStylesAsync()).map(s => [s.name, s]));

const paint = (n) => figma.variables.setBoundVariableForPaint(
  { type: "SOLID", color: { r: 0, g: 0, b: 0 } }, "color", V[n]);
const rgba = (n, a) => {
  const v = V[n], c = v.valuesByMode[Object.keys(v.valuesByMode)[0]];
  return { r: c.r, g: c.g, b: c.b, a: a === undefined ? (c.a === undefined ? 1 : c.a) : a };
};
const wash = (n, a) => ({ type: "SOLID", color: rgba(n), opacity: a });

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
const col = (s, o) => { const f = figma.createAutoLayout("VERTICAL", Object.assign({ itemSpacing: s }, o || {})); f.fills = []; return f; };
const row = (s, o) => { const f = figma.createAutoLayout("HORIZONTAL", Object.assign({ itemSpacing: s }, o || {})); f.fills = []; return f; };
const pad = (f, o, v) => { f.paddingLeft = f.paddingRight = o; f.paddingTop = f.paddingBottom = (v === undefined ? o : v); return f; };

const glifiMancanti = [];
const glifo = (nome, size, coloreVar, peso) => {
  const t = figma.createText();
  t.fontName = { family: "SF Pro", style: peso || "Semibold" };
  t.fontSize = size;
  try { t.characters = figma.util.getSfSymbolCharacter(nome); }
  catch (e) { if (glifiMancanti.indexOf(nome) < 0) glifiMancanti.push(nome); t.characters = "●"; }
  t.name = "icona/" + nome;
  if (coloreVar) t.fills = [paint(coloreVar)];
  return t;
};

const barraSchede = (attiva) => {
  const schede = [["Oggi","sun.horizon"],["Carta","location.north.line"],
    ["Itinerario","list.bullet.indent"],["Nave","ferry"],["Diario","book.closed"]];
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
    if (scelta) { c.cornerRadius = 26; c.fills = [wash("accento/navigazione", 0.14)]; }
    c.appendChild(glifo(simbolo, 20, scelta ? "accento/navigazione" : "inchiostro/secondario"));
    c.appendChild(txt("Etichetta metrica", nome, scelta ? "accento/navigazione" : "inchiostro/secondario"));
    barra.appendChild(c);
  }
  return barra;
};

/** Glifo in un quadratino tinto, titolo e sottotitolo.
 *  La freccia non c'è: compare solo se la riga porta davvero da qualche parte. */
const infoRow = (simbolo, tinta, titolo, sottotitolo) => {
  const r = row(12, { name: titolo });
  r.counterAxisAlignItems = "CENTER";
  pad(r, 15, 13);
  r.cornerRadius = 20;
  r.fills = [paint("fondo/vetro")];
  r.strokes = [paint("bordo/sottile")];
  r.strokeWeight = 0.5;
  if (ES["Vetro / Chip"]) r.effectStyleId = ES["Vetro / Chip"].id;
  const box = row(0, { name: "glifo" });
  box.primaryAxisAlignItems = "CENTER";
  box.counterAxisAlignItems = "CENTER";
  box.resize(34, 34);
  box.layoutSizingHorizontal = "FIXED";
  box.layoutSizingVertical = "FIXED";
  box.cornerRadius = 11;
  box.fills = [wash(tinta, 0.16)];
  box.appendChild(glifo(simbolo, 15, tinta));
  r.appendChild(box);
  const c = col(2);
  c.appendChild(txt("Titolo riga", titolo, "inchiostro/primario"));
  c.appendChild(txt("Dettaglio riga", sottotitolo, "inchiostro/secondario"));
  r.appendChild(c);
  c.layoutSizingHorizontal = "FILL";
  return r;
};

const s = figma.createFrame();
s.name = "Pre-crociera — attesa";
s.resize(W, H);
s.x = 2300; s.y = 0;
s.clipsContent = true;
s.fills = [{
  type: "GRADIENT_LINEAR",
  gradientTransform: [[0, 1, 0], [-1, 0, 1]],
  gradientStops: [
    { position: 0, color: rgba("fondo/mare-alto") },
    { position: 0.5, color: rgba("fondo/mare") },
    { position: 1, color: rgba("fondo/abisso") }
  ]
}];
page.appendChild(s);

// L'eroe non è un rettangolo in attesa di una foto: la propria rotta disegnata
// dice già qualcosa di vero, e un segnaposto in produzione non passa la revisione.
const eroe = figma.createFrame();
eroe.name = "Testata — rotta della crociera";
eroe.resize(W, 300);
eroe.x = 0; eroe.y = 0;
eroe.clipsContent = true;
eroe.fills = [wash("fondo/mare-alto", 1)];
s.appendChild(eroe);

const rotta = figma.createFrame();
rotta.name = "Carta della rotta — sostituire con lo screenshot";
rotta.resize(W, 300);
rotta.x = 0; rotta.y = 0;
rotta.fills = [wash("fondo/mare-alto", 1)];
eroe.appendChild(rotta);

const velo = figma.createRectangle();
velo.name = "Velo";
velo.resize(W, 300);
velo.x = 0; velo.y = 0;
velo.fills = [{
  type: "GRADIENT_LINEAR",
  gradientTransform: [[0, 1, 0], [-1, 0, 1]],
  gradientStops: [
    { position: 0, color: { r: 0, g: 0, b: 0, a: 0 } },
    { position: 0.55, color: rgba("fondo/abisso", 0.55) },
    { position: 1, color: rgba("fondo/abisso", 1) }
  ]
}];
eroe.appendChild(velo);

const nomi = col(4, { name: "Nome e rotta" });
const nomeNave = figma.createText();
nomeNave.fontName = { family: "SF Pro", style: "Bold" };
nomeNave.fontSize = 34;
nomeNave.lineHeight = { unit: "PIXELS", value: 41 };
nomeNave.letterSpacing = { unit: "PIXELS", value: -0.3 };
nomeNave.characters = "Stella Australe";
nomeNave.fills = [paint("inchiostro/primario")];
nomeNave.name = "Nome della nave";
nomi.appendChild(nomeNave);
nomi.appendChild(txt("Sottotitolo schermata", "San Juan → Miami", "inchiostro/secondario"));
eroe.appendChild(nomi);
nomi.x = 24;
nomi.y = 300 - nomi.height - 18;

try {
  const c = await figma.importComponentByKeyAsync("e01a1714aeec1a5a0a6453485bf16e975008b282");
  const i = c.createInstance();
  i.name = "Barra di stato";
  s.appendChild(i);
  i.x = 0; i.y = 0;
} catch (e) { /* senza la libreria Apple si prosegue: la barra è cosmetica */ }

const contenuto = col(22, { name: "Contenuto" });
pad(contenuto, 24, 0);
contenuto.paddingTop = 28;
s.appendChild(contenuto);
contenuto.x = 0; contenuto.y = 300;
contenuto.resize(W, 100);
contenuto.layoutSizingHorizontal = "FIXED";

const contatore = col(6, { name: "Contatore" });
contatore.counterAxisAlignItems = "CENTER";
const cifreRiga = row(12);
cifreRiga.counterAxisAlignItems = "BASELINE";
const giorni = figma.createText();
giorni.fontName = { family: "SF Pro", style: "Semibold" };
giorni.fontSize = 108;
giorni.letterSpacing = { unit: "PIXELS", value: -1.4 };
giorni.characters = "23";
giorni.fills = [paint("inchiostro/primario")];
giorni.name = "Giorni";
cifreRiga.appendChild(giorni);
const parola = figma.createText();
parola.fontName = { family: "SF Pro", style: "Medium" };
parola.fontSize = 28;
parola.lineHeight = { unit: "PIXELS", value: 34 };
parola.characters = "giorni";
parola.fills = [paint("inchiostro/secondario")];
parola.name = "giorni (parola)";
cifreRiga.appendChild(parola);
contatore.appendChild(cifreRiga);

// Il tono si stringe man mano che la data si avvicina: oltre la settimana è
// «Preparati a salpare», il giorno prima diventa «Domani si parte».
const incoraggiamento = txt("Titolo schermata", "Preparati a salpare.", "accento/azione",
  { name: "Incoraggiamento" });
incoraggiamento.textAlignHorizontal = "CENTER";
contatore.appendChild(incoraggiamento);
contenuto.appendChild(contatore);
contatore.layoutSizingHorizontal = "FILL";

const dettagli = col(12, { name: "Dettagli" });
dettagli.appendChild(infoRow("mappin.and.ellipse", "accento/azione",
  "Imbarco a San Juan", "lun 24 ago · 19:00 · ora di bordo"));
dettagli.appendChild(infoRow("list.bullet.indent", "accento/navigazione",
  "5 scali · 8 notti", "L'itinerario è già pronto nella scheda Itinerario."));

const chipRiga = row(0, { name: "Provenienza" });
chipRiga.paddingTop = 2;
const chip = row(5, { name: "Chip di provenienza" });
chip.counterAxisAlignItems = "CENTER";
pad(chip, 9, 5);
chip.cornerRadius = 100;
chip.fills = [wash("inchiostro/primario", 0.06)];
chip.strokes = [paint("bordo/sottile")];
chip.strokeWeight = 0.5;
chip.appendChild(glifo("calendar", 9, "inchiostro/secondario"));
chip.appendChild(txt("Tecnico", "orario pubblicato", "inchiostro/secondario"));
chipRiga.appendChild(chip);
dettagli.appendChild(chipRiga);

contenuto.appendChild(dettagli);
dettagli.layoutSizingHorizontal = "FILL";
for (const r of dettagli.children) r.layoutSizingHorizontal = "FILL";

const barra = barraSchede("Oggi");
s.appendChild(barra);
barra.x = 14;
barra.y = H - barra.height - 26;

await s.screenshot({ scale: 0.85 });
return { createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height, glifiMancanti };
