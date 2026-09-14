# Costruzione delle schermate Cruisy in Figma

Script pronti da incollare in `use_figma`. Ognuno costruisce **una schermata in
una chiamata sola**, perché il piano Starter di Figma concede **20 chiamate al
mese** e ogni tentativo sbagliato ne brucia una.

## Il budget, per come funziona davvero

Dal documento dei limiti del server MCP di Figma:

- **Starter: 20 chiamate al mese.** Non al giorno. Si azzera col mese nuovo.
- **Esenti sono soltanto tre strumenti**: `whoami`, `create_new_file`,
  `add_code_connect_map`. **`use_figma` non è fra questi**, nonostante il README
  generale dica che «le scritture sono esenti»: verificato sul campo, una
  chiamata di sola scrittura senza screenshot viene comunque respinta.
- **Lo screenshot in coda a uno script non costa nulla.** `node.screenshot()`
  sta *dentro* la stessa chiamata `use_figma`: una chiamata resta una chiamata.
  Per questo ogni script finisce con uno screenshot — è verifica visiva gratis.
  Un `get_screenshot` separato invece costa.

File: `EFHsnIqbC0vt1T5Ij0uPUm` · <https://www.figma.com/design/EFHsnIqbC0vt1T5Ij0uPUm>

## Come si usa

```bash
python3 figma/assembla.py      # concatena preambolo + corpi in figma/out/
```

Poi si incolla il contenuto di `figma/out/NN-....js` nel parametro `code` di
`use_figma`, con `fileKey` uguale a quello sopra. Ogni script termina con uno
screenshot inline, quindi **non serve una seconda chiamata** per vedere il
risultato: è metà del budget risparmiata.

## Ordine

| # | Script | Cosa fa | Pagina |
|---|---|---|---|
| 00 | `00-fix-pastiglie.js` | Porta al 16% l'opacità delle Pastiglie di stato | Componenti |
| 01 | `01-oggi-in-porto.js` | Oggi, giorno di porto: anello e all aboard | Schermate |
| 02 | `02-oggi-in-mare.js` | Oggi, giorno di mare: onda e arrivo | Schermate |
| 03 | `03-itinerario.js` | Itinerario: componente riga + 9 istanze | Schermate |
| 04 | `04-diario.js` | Diario: totali, primati, timbri, crociere | Schermate |
| 05 | `05-nave.js` | Nave: foto, misure, identificativi | Schermate |

Le schermate si posano affiancate sulla pagina Schermate a x = 0, 460, 920,
1380, 1840.

## Cosa resta da fare a mano

- **La carta nautica** in 01 e 02 è un riquadro pieno con scritto cosa sostituire.
  È disegnata a runtime dai dati Natural Earth e a vettori verrebbe una bugia:
  ci va lo screenshot vero, caricato con `upload_assets`.
- **La foto della nave** in 05, stessa ragione: viene da Wikimedia Commons e il
  credito è già al suo posto sopra il riquadro.

## Tre errori già pagati, che il preambolo evita da sé

1. **`createAutoLayout` nasce bianco.** Su un'app nera copre tutto. `col()` e
   `row()` tolgono sempre il riempimento.
2. **L'opacità di un riempimento viene scartata se al colore è legata una
   variabile.** Dove serve l'alfa si usa `wash()`, che prende il valore letterale
   — e si perde il legame, quindi va detto invece che nascosto.
3. **I glifi si prendono per nome SF Symbol**, con `figma.util.getSfSymbolCharacter`,
   mai per codepoint e mai ricostruiti da primitive ruotate.

## Verifica prima di spendere una chiamata

```bash
for f in figma/out/*.js; do
  { echo "async function w(figma) {"; cat "$f"; echo "}"; } > /tmp/c.js
  node --check /tmp/c.js && echo "ok $(basename $f)"
done
```
