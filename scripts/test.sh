#!/usr/bin/env bash
# I test di Cruisy, con le opzioni giuste già messe.
#
#   scripts/test.sh unit    # test unitari (Swift Testing), meno di un minuto
#   scripts/test.sh ui      # test di interfaccia (XCUITest): gesti e navigazione
#   scripts/test.sh all     # tutti (predefinito)
#   scripts/test.sh ui NavigationSmokeUITests/testAllPortsOpens   # uno solo
#
# Due cose che senza questo script si pagano:
#
# - `-collect-test-diagnostics never`: quando un test di interfaccia fallisce,
#   xcodebuild fa partire un `simctl diagnose` che dura **dieci minuti**.
# - quando un test di interfaccia fallisce, il suo messaggio può mentire. Il perché
#   vero sta nell'albero dell'interfaccia salvato al momento del fallimento:
#
#     xcrun xcresulttool export attachments --path <risultato>.xcresult --output-path <cartella>
#
#   Il percorso del risultato lo stampa questo script alla fine.

set -euo pipefail
cd "$(dirname "$0")/.."

WHAT="${1:-all}"
ONLY="${2:-}"
DEVICE="${SIMULATOR:-iPhone 17 Pro}"
RESULT="${TMPDIR:-/tmp}/cruisy-test-$(date +%Y%m%d-%H%M%S).xcresult"

case "$WHAT" in
  unit) SELECT=(-only-testing:"CruisyTests${ONLY:+/$ONLY}") ;;
  ui)   SELECT=(-only-testing:"CruisyUITests${ONLY:+/$ONLY}") ;;
  all)  SELECT=() ;;
  *) echo "uso: scripts/test.sh unit|ui|all [suite/test]" >&2; exit 2 ;;
esac

set +e
xcodebuild test -scheme Cruisy \
  -destination "platform=iOS Simulator,name=$DEVICE" \
  -collect-test-diagnostics never \
  -resultBundlePath "$RESULT" \
  ${SELECT[@]+"${SELECT[@]}"} 2>&1 \
  | grep -E "error:|Test run with|Test Case .*failed|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)|BUILD FAILED" \
  | awk '!seen[$0]++'
STATUS=${PIPESTATUS[0]}
set -e

echo "risultato: $RESULT"
exit "$STATUS"
