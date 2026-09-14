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
return { createdNodeIds: [s.id], schermata: s.id, altezzaContenuto: contenuto.height };
