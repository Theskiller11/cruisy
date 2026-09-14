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
return { createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height };
