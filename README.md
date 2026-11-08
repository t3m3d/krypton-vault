# Krypton Vault

macOS-first password manager built with Krypton. The app encrypts vault data
locally; the VPS sync service stores only opaque encrypted blobs.

## Repository layout

```text
app/krypton_vault.ks                 macOS vault app
app/krypton_inspector.ks             macOS binary/ABI inspector
stdlib/vault_format.k                Portable KV3 envelope
stdlib/vault_model.k                 Portable typed payload model
stdlib/vault_crypto_macos.k          Native macOS crypto backend
tests/                               Vault and crypto smoke tests
tools/                               Sync server, smoke test, verifier, ObjC audit
deploy/                              systemd, env, and Caddy configuration
docs/krypton-vault.md                Product and deployment notes
```

The Krypton compiler/runtime and reusable macOS native bindings remain in the
sibling repository: `../krypton`. Set `KRYPTON_LANG_ROOT` if it is elsewhere.

## Build the macOS app

```bash
scripts/build-macos.sh
open dist/krypton-vault.app
```

The build wrapper overlays the Vault-specific module and headers on top of the
Krypton language installation, so the two repositories stay separate.

## Verify locally

```bash
tools/vault_verify.sh
```

The verifier checks the vault format, native macOS seal/open, app bundle build,
the Objective-C selector/ABI audit for both apps, sync service syntax, and live
upload/fetch/restore behavior.

## Inspector app

`app/krypton_inspector.ks` is a native macOS front end for `objc-audit`, usable
on any Krypton binary or `.app` bundle:

```bash
scripts/build-inspector.sh
open dist/krypton-inspector.app
```

Pick an app or binary, then use Overview, Selectors, Security, Strings, or
Bundle. The app bundles `objc-audit` as an auxiliary executable, so the GUI and
CLI produce identical reports. This first slice covers metadata, ABI, and
binary inspection; it is not a disassembler, decompiler, or debugger.

## Objective-C ABI audit

Krypton sends AppKit selectors as plain strings, so the compiler cannot catch a
typo or a receiver that does not implement a method. `tools/objc_audit.ks`
builds to `dist/objc-audit` and checks those strings against the real runtime:

```bash
scripts/build-objc-audit.sh

# Resolve every selector-like string in the app binary and print type encodings.
dist/objc-audit scan dist/krypton-vault.app/Contents/MacOS/krypton-vault

# Fail the build on unresolved argument selectors (callbacks are allowlisted).
dist/objc-audit scan dist/krypton-vault.app/Contents/MacOS/krypton-vault \
  --strict --quiet --allow 'windowShouldClose:,controlTextDidChange:'

# Inspect load commands, dylibs, signature, entitlements, and imports.
dist/objc-audit info dist/krypton-vault.app/Contents/MacOS/krypton-vault

# Query specific classes/selectors for their ABI encodings.
dist/objc-audit dump --class NSWindow --selectors setTitle:,title
```

`scan` reports `v@:@`-style encodings from `NSMethodSignature`, so it doubles as
a check that argument counts and struct layouts match the call sites. Use
`--all` to also probe bare no-argument identifiers. `--strict` exits non-zero
when an argument selector resolves to no class and is not in `--allow`.
Selectors added at runtime with `class_addMethod` are expected to be listed in
the allow list; the verifier keeps the app's callback selectors there.

## VPS

The first sync endpoint is `https://kry.li`. Install the files under
`deploy/`, run the service behind Caddy or nginx, and use the smoke test from a
trusted machine:

```bash
BASE_URL=https://kry.li \
KRYPTON_VAULT_TOKEN='same-token-as-the-server' \
tools/vault_sync_smoke.sh
```

KV3 derives keys with PBKDF2-HMAC-SHA256 (600,000 iterations by default) and
authenticates AES-256-CBC ciphertext with HMAC-SHA256 (encrypt-then-MAC). That
is a hardening step, not a finished design: it is not memory-hard and not a
single AEAD primitive. Treat this as a private alpha and do not store real
passwords until Argon2id (or scrypt) and an AEAD (XChaCha20-Poly1305 or
AES-GCM) land and the format receives a security review.
