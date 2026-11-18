#!/bin/bash
# Tests the Gemini key check in lambda.sh: runs its exact lines (read -> strip -> curl) with each input on stdin.
# Usage: GEMINI_KEY=<your key> bash scripts/test-key-check.sh     (the key is never printed)
: "${GEMINI_KEY:?set GEMINI_KEY to a real key first}"
check=$(sed -n '/read -rsp .Gemini API key/,/Gemini key check failed/p' "$(dirname "$0")/lambda.sh")
[ -n "$check" ] || { echo "key check not found in lambda.sh"; exit 1; }

expect() {  # name, stdin, PASS|FAIL
  if printf '%s' "$2" | bash -c "set -euo pipefail; $check" >/dev/null 2>&1; then got=PASS; else got=FAIL; fi
  if [ "$got" = "$3" ]; then echo "ok    $1 -> $got"; else echo "WRONG $1 -> $got (expected $3)"; fails=1; fi
}
expect "real key"                "$GEMINI_KEY"$'\n'      PASS
expect "real key, spaces around" "  $GEMINI_KEY  "$'\n'  PASS
expect "real key, Windows CRLF"  "$GEMINI_KEY"$'\r\n'    PASS
expect "fake AIza key"           $'AIzaSyFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAK\n' FAIL
expect "fake AQ. key"            $'AQ.FAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKEFAKE\n' FAIL
expect "real key cut short"      "${GEMINI_KEY:0:20}"$'\n' FAIL
expect "empty"                   $'\n'                   FAIL
exit ${fails:-0}
