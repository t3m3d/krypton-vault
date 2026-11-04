# Krypton Vault

macOS-first password manager built with Krypton. The app encrypts vault data
locally; the VPS sync service stores only opaque encrypted blobs.

## Repository layout

```text
app/krypton_vault.ks                 macOS app
stdlib/vault_crypto_macos.k          Vault crypto module
headers/{commoncrypto,security}.krh  Native macOS bindings
tests/                               Vault and crypto smoke tests
tools/                               Sync server, smoke test, verifier
deploy/                              systemd, env, and Caddy configuration
docs/krypton-vault.md                Product and deployment notes
```

The Krypton compiler/runtime remains in the sibling repository:
`../krypton`. Set `KRYPTON_LANG_ROOT` if it is elsewhere.

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
sync service syntax, and live upload/fetch/restore behavior.

## VPS

The first sync endpoint is `https://kry.li`. Install the files under
`deploy/`, run the service behind Caddy or nginx, and use the smoke test from a
trusted machine:

```bash
BASE_URL=https://kry.li \
KRYPTON_VAULT_TOKEN='same-token-as-the-server' \
tools/vault_sync_smoke.sh
```

The current crypto format is a private-alpha prototype. Do not store real
passwords in it until the master-key derivation is upgraded to a reviewed
memory-hard KDF and the vault format receives a security review.
