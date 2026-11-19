#!/usr/bin/env bash
set -euo pipefail

VAULT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Resolve the Krypton toolchain. The local repo checkout at ../krypton is a
# development tree whose macOS backend is currently broken (crashes on
# non-trivial apps), so prefer the released toolchain installed via
# Homebrew; fall back to the local checkout only with a warning. Set
# KRYPTON_LANG_ROOT to override.
if [[ -z "${KRYPTON_LANG_ROOT:-}" ]]; then
  if [[ -x /opt/homebrew/opt/krypton/libexec/compiler/macos_arm64/kcc-arm64 ]]; then
    LANG_ROOT="/opt/homebrew/opt/krypton/libexec"
  elif [[ -d "$VAULT_ROOT/../krypton" ]]; then
    echo "WARNING: using ../krypton development-tree toolchain; it miscompiles apps and produces crashing binaries. Install krypton via Homebrew or set KRYPTON_LANG_ROOT to a known-good toolchain." >&2
    LANG_ROOT="$(cd "$VAULT_ROOT/../krypton" && pwd)"
  else
    echo "Krypton macOS toolchain not found." >&2
    echo "Install it with: brew install krypton   (or set KRYPTON_LANG_ROOT)" >&2
    exit 1
  fi
else
  LANG_ROOT="$KRYPTON_LANG_ROOT"
fi
FE="$LANG_ROOT/compiler/macos_arm64/kcc-arm64"
HOST="$LANG_ROOT/compiler/macos_arm64/macho_host"
OUT="$VAULT_ROOT/dist/objc-audit"
IR_FILE="/tmp/objc-audit.kir"
OVERLAY="$(mktemp -d /tmp/objc-audit-root.XXXXXX)"

cleanup() {
  rm -rf "$OVERLAY"
}
trap cleanup EXIT

if [[ ! -x "$FE" || ! -x "$HOST" ]]; then
  echo "Krypton macOS compiler/host not found under: $LANG_ROOT" >&2
  echo "Set KRYPTON_LANG_ROOT to the Krypton language repository." >&2
  exit 1
fi

mkdir -p "$OVERLAY/stdlib" "$OVERLAY/headers" "$VAULT_ROOT/dist"
for file in "$LANG_ROOT"/stdlib/*; do
  ln -s "$file" "$OVERLAY/stdlib/$(basename "$file")"
done
for file in "$LANG_ROOT"/headers/*; do
  ln -s "$file" "$OVERLAY/headers/$(basename "$file")"
done
for file in "$VAULT_ROOT"/stdlib/*.k; do
  [ -e "$file" ] || continue
  ln -sf "$file" "$OVERLAY/stdlib/$(basename "$file")"
done
for file in "$VAULT_ROOT"/headers/*.krh; do
  [ -e "$file" ] || continue
  ln -sf "$file" "$OVERLAY/headers/$(basename "$file")"
done

env KRYPTON_ROOT="$OVERLAY" "$FE" "$VAULT_ROOT/tools/objc_audit.ks" > "$IR_FILE"
"$HOST" --ir "$IR_FILE" "$OUT" >/dev/null
chmod +x "$OUT"
codesign -s - -f "$OUT" >/dev/null 2>&1 || true
echo "built $OUT"
