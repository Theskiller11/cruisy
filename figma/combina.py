#!/usr/bin/env python3
"""Fonde preambolo + cinque corpi in **un solo** script per `use_figma`.

Serve perché il piano Starter concede 20 chiamate al mese: cinque schermate in
cinque chiamate sono un quarto del budget mensile. `use_figma` è atomico, quindi
un blocco solo non rischia più di cinque blocchi separati — se fallisce, non
crea niente e si perde una chiamata invece di una.

Due accorgimenti necessari:
  · ogni corpo dichiara `const s`, `const contenuto`, `const testata`…
    Concatenarli darebbe «Identifier has already been declared», quindi ognuno
    viene racchiuso in un blocco `{ }` che ne limita lo scopo.
  · un `return` dentro un blocco uscirebbe da tutto lo script, quindi i return
    finali diventano `risultati.push(...)` e il return vero sta in coda.
"""
import pathlib, re, sys

qui = pathlib.Path(__file__).parent
preambolo = (qui / "_preambolo.js").read_text()

corpi = sorted(p for p in qui.glob("[0-9][0-9]-*.js") if not p.name.startswith("00-"))

pezzi = [preambolo, "\nconst risultati = [];\n"]
for corpo in corpi:
    testo = corpo.read_text()
    # L'ultimo `return { … };` diventa una spinta nell'elenco dei risultati.
    testo, n = re.subn(r"return (\{[^;]*\});\s*$", r"risultati.push(\1);", testo.rstrip() + "\n")
    if n != 1:
        sys.exit(f"{corpo.name}: atteso un solo return finale, trovati {n}")
    pezzi.append(f"\n// ==== {corpo.name} " + "=" * (58 - len(corpo.name)) + "\n{\n" + testo + "\n}\n")

pezzi.append("\nreturn { schermate: risultati, glifiMancanti };\n")
completo = "".join(pezzi)

fuori = qui / "out" / "tutte-le-schermate.js"
fuori.parent.mkdir(exist_ok=True)
fuori.write_text(completo)

print(f"{len(corpi)} corpi fusi · {len(completo)} caratteri", end="")
print("  ⚠ OLTRE IL LIMITE DI 50.000" if len(completo) > 50000 else "  ✓ sotto il limite")
