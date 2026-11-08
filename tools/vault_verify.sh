#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANG_ROOT="${KRYPTON_LANG_ROOT:-$(cd "$ROOT/../krypton" && pwd)}"
PORT="${PORT:-19097}"
TOKEN="${KRYPTON_VAULT_TOKEN:-test-token}"
DATA_DIR="${KRYPTON_VAULT_DATA:-/tmp/krypton-vault-verify}"
SERVER_PID=""

cleanup() {
  if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$ROOT/tools/__pycache__"
}
trap cleanup EXIT

cd "$ROOT"

FE="$LANG_ROOT/compiler/macos_arm64/kcc-arm64"
HOST_BIN="$LANG_ROOT/compiler/macos_arm64/macho_host"
BACKEND="$LANG_ROOT/compiler/macos_arm64/macho_arm64_self.k"
if [[ ! -x "$HOST_BIN" || "$BACKEND" -nt "$HOST_BIN" ]]; then
  env KRYPTON_ROOT="$LANG_ROOT" "$FE" "$BACKEND" > /tmp/krypton-vault-macho-host.kir
  "$HOST_BIN" --ir /tmp/krypton-vault-macho-host.kir /tmp/krypton-vault-macho-host
  cp /tmp/krypton-vault-macho-host "$HOST_BIN"
  chmod +x "$HOST_BIN"
fi

OVERLAY="$(mktemp -d /tmp/krypton-vault-verify-root.XXXXXX)"
cleanup_overlay() { rm -rf "$OVERLAY"; }
cleanup_all() { cleanup; cleanup_overlay; }
trap cleanup_all EXIT
mkdir -p "$OVERLAY/stdlib" "$OVERLAY/headers"
for file in "$LANG_ROOT"/stdlib/*; do ln -s "$file" "$OVERLAY/stdlib/$(basename "$file")"; done
for file in "$LANG_ROOT"/headers/*; do ln -s "$file" "$OVERLAY/headers/$(basename "$file")"; done
for file in "$ROOT"/stdlib/*.k; do [ -e "$file" ] || continue; ln -sf "$file" "$OVERLAY/stdlib/$(basename "$file")"; done
for file in "$ROOT"/headers/*.krh; do [ -e "$file" ] || continue; ln -sf "$file" "$OVERLAY/headers/$(basename "$file")"; done

env KRYPTON_ROOT="$OVERLAY" "$FE" "$ROOT/tests/vault_format_smoke.ks" > /tmp/krypton-vault-format-smoke.kir
"$HOST_BIN" --ir /tmp/krypton-vault-format-smoke.kir /tmp/krypton-vault-format-smoke
chmod +x /tmp/krypton-vault-format-smoke
/tmp/krypton-vault-format-smoke
env KRYPTON_ROOT="$OVERLAY" "$FE" "$ROOT/tests/vault_model_smoke.ks" > /tmp/krypton-vault-model-smoke.kir
"$HOST_BIN" --ir /tmp/krypton-vault-model-smoke.kir /tmp/krypton-vault-model-smoke
chmod +x /tmp/krypton-vault-model-smoke
/tmp/krypton-vault-model-smoke
env KRYPTON_ROOT="$OVERLAY" "$FE" "$ROOT/tests/vault_crypto_smoke.ks" > /tmp/krypton-vault-crypto-smoke.kir
"$HOST_BIN" --ir /tmp/krypton-vault-crypto-smoke.kir /tmp/krypton-vault-crypto-smoke
chmod +x /tmp/krypton-vault-crypto-smoke
SMOKE_HOME="$(mktemp -d /tmp/krypton-vault-home.XXXXXX)"
HOME="$SMOKE_HOME" /tmp/krypton-vault-crypto-smoke
rm -rf "$SMOKE_HOME"
KRYPTON_LANG_ROOT="$LANG_ROOT" "$ROOT/scripts/build-macos.sh"
KRYPTON_LANG_ROOT="$LANG_ROOT" "$ROOT/scripts/build-objc-audit.sh"
APP_BIN="$ROOT/dist/krypton-vault.app/Contents/MacOS/krypton-vault"
ALLOW="objk_dispatch:,krTableClick:,krTableDoubleClick:,controlTextDidChange:,windowShouldClose:,windowWillClose:,application:openFile:,applicationShouldHandleReopen:hasVisibleWindows:"
"$ROOT/dist/objc-audit" scan "$APP_BIN" --strict --quiet --allow "$ALLOW"
KRYPTON_LANG_ROOT="$LANG_ROOT" "$ROOT/scripts/build-inspector.sh"
INSPECTOR_BIN="$ROOT/dist/krypton-inspector.app/Contents/MacOS/krypton-inspector"
"$ROOT/dist/objc-audit" scan "$INSPECTOR_BIN" --strict --quiet --allow "$ALLOW"
python3 -m py_compile tools/vault_sync_server.py

rm -rf "$DATA_DIR"
mkdir -p "$DATA_DIR"
HOST=127.0.0.1 PORT="$PORT" KRYPTON_VAULT_TOKEN="$TOKEN" KRYPTON_VAULT_DATA="$DATA_DIR" \
  python3 tools/vault_sync_server.py >/tmp/krypton-vault-verify-server.log 2>&1 &
SERVER_PID="$!"

ready=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl -fsS --max-time 1 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 0.2
done

if [[ "$ready" != "1" ]]; then
  cat /tmp/krypton-vault-verify-server.log >&2 || true
  echo "vault verify failed: sync server did not become ready" >&2
  exit 1
fi

BASE_URL="http://127.0.0.1:$PORT" KRYPTON_VAULT_TOKEN="$TOKEN" KRYPTON_VAULT_USER=verify \
  tools/vault_sync_smoke.sh

echo "vault verify ok"
