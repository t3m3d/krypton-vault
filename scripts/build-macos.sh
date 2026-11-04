#!/usr/bin/env bash
set -euo pipefail

VAULT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LANG_ROOT="${KRYPTON_LANG_ROOT:-$(cd "$VAULT_ROOT/../krypton" && pwd)}"
FE="$LANG_ROOT/compiler/macos_arm64/kcc-arm64"
HOST="$LANG_ROOT/compiler/macos_arm64/macho_host"
APP_NAME="krypton-vault"
IR_FILE="/tmp/krypton-vault.kir"
BIN_FILE="/tmp/krypton-vault.bin"
OVERLAY="$(mktemp -d /tmp/krypton-vault-root.XXXXXX)"

cleanup() {
  rm -rf "$OVERLAY"
}
trap cleanup EXIT

if [[ ! -x "$FE" || ! -x "$HOST" ]]; then
  echo "Krypton macOS compiler/host not found under: $LANG_ROOT" >&2
  echo "Set KRYPTON_LANG_ROOT to the Krypton language repository." >&2
  exit 1
fi

mkdir -p "$OVERLAY/stdlib" "$OVERLAY/headers"
for file in "$LANG_ROOT"/stdlib/*; do
  ln -s "$file" "$OVERLAY/stdlib/$(basename "$file")"
done
for file in "$LANG_ROOT"/headers/*; do
  ln -s "$file" "$OVERLAY/headers/$(basename "$file")"
done
ln -sf "$VAULT_ROOT/stdlib/vault_crypto_macos.k" "$OVERLAY/stdlib/vault_crypto_macos.k"

env KRYPTON_ROOT="$OVERLAY" "$FE" "$VAULT_ROOT/app/krypton_vault.ks" > "$IR_FILE"
"$HOST" --ir "$IR_FILE" "$BIN_FILE" >/dev/null

APP="$VAULT_ROOT/dist/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_FILE" "$APP/Contents/MacOS/$APP_NAME"
chmod +x "$APP/Contents/MacOS/$APP_NAME"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Krypton Vault</string>
  <key>CFBundleExecutable</key><string>krypton-vault</string>
  <key>CFBundleIdentifier</key><string>org.krypton-lang.macos.krypton-vault</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign -s - -f "$APP/Contents/MacOS/$APP_NAME" >/dev/null 2>&1
echo "built $APP"
