#!/usr/bin/env bash
# Aggiorna il catalogo delle stringhe con quelle usate davvero nel codice.
#
# Perché esiste: `xcodebuild` non tocca `Localizable.xcstrings`. Le chiavi nuove
# entravano nel catalogo solo aprendo il progetto in Xcode, quindi chi lavora da riga
# di comando — una persona o un agente — scriveva testo che non arrivava mai alla
# traduzione, e l'inglese restava indietro senza che nessuno se ne accorgesse.
#
# Xcode, dietro le quinte, fa due passi: il compilatore scrive un file `.stringsdata`
# per ogni file Swift (serve `SWIFT_EMIT_LOC_STRINGS = YES`, già attivo per app e
# widget), poi `xcstringstool sync` li fonde nel catalogo. Questo script fa gli stessi
# due passi.
#
#   scripts/sync-strings.sh            # compila e sincronizza
#   scripts/sync-strings.sh --no-build # usa l'ultima build
#
# Dopo: `scripts/test.sh unit LocalizationTests` dice quali chiavi non hanno ancora
# l'inglese.

set -euo pipefail
cd "$(dirname "$0")/.."

CATALOG="CruisyShared/Localizable.xcstrings"
DEVICE="${SIMULATOR:-iPhone 17 Pro}"

if [[ "${1:-}" != "--no-build" ]]; then
  echo "compilo…"
  xcodebuild -scheme Cruisy -destination "platform=iOS Simulator,name=$DEVICE" build -quiet
fi

INTERMEDIATES=$(xcodebuild -scheme Cruisy -destination "platform=iOS Simulator,name=$DEVICE" \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ OBJROOT /{print $2; exit}')

# Solo app e widget: i test hanno le loro stringhe, che non si traducono. E solo
# l'architettura di questo Mac: una build vecchia per x86_64 lascia i suoi
# .stringsdata nella cartella accanto, e il 25 settembre 2026 riportavano nel
# catalogo ventiquattro stringhe cancellate da giorni — Xcode le segnava stantie,
# questo script le rimetteva.
ARCH=$(uname -m)
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(
  find "$INTERMEDIATES" -name '*.stringsdata' -path "*/Objects-normal/$ARCH/*" \
    \( -path '*Debug-iphonesimulator/Cruisy.build/*' -o -path '*Debug-iphonesimulator/CruisyWidgets.build/*' \)
)
if [[ ${#FILES[@]} -eq 0 ]]; then echo "nessun .stringsdata: compila prima" >&2; exit 1; fi

ARGS=()
for f in "${FILES[@]}"; do ARGS+=(--stringsdata "$f"); done
xcrun xcstringstool sync "$CATALOG" "${ARGS[@]}"

python3 - "$CATALOG" <<'PY'
import json, sys
strings = json.load(open(sys.argv[1]))["strings"]
missing = [k for k, v in strings.items()
           if v.get("shouldTranslate", True) and v.get("extractionState") != "stale"
           and "en" not in v.get("localizations", {})]
stale = [k for k, v in strings.items() if v.get("extractionState") == "stale"]
print(f"catalogo: {len(strings)} chiavi · {len(missing)} senza inglese · {len(stale)} stantie")
for k in missing[:40]:
    print("  manca en:", k[:100])
PY
