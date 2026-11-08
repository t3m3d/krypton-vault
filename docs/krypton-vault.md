# Krypton Vault

Krypton Vault is the password manager product track for this repo.

The platform order is:

1. macOS
2. Windows
3. Linux
4. BSD, only if there is real demand

The first shippable product should be a small native desktop app with optional
VPS sync. The desktop client owns encryption and decryption. The VPS should
only store opaque encrypted vault blobs, account records, device metadata, and
sync revisions.

## First macOS Build

The first macOS prototype lives at:

```text
app/krypton_vault.ks
```

Build it as an app bundle with:

```bash
scripts/build-macos.sh
```

This creates:

```text
dist/krypton-vault.app
```

The current prototype has encrypted local persistence through:

```text
stdlib/vault_crypto_macos.k
```

That module is a native macOS bridge over Security.framework and CommonCrypto.
KV3 derives keys with PBKDF2-HMAC-SHA256 (600,000 iterations by default), uses
a fresh OS-random IV, encrypts with AES-256-CBC/PKCS7, and authenticates the
canonical header plus ciphertext with HMAC-SHA256 (encrypt-then-MAC). Older KV2
private-alpha vaults remain readable for migration. The sealed file is written
to:

```text
~/.config/krypton-vault/vault.kv
```

The UI can unlock, add items, delete the first search match, filter the visible
vault list, copy the first matching saved password, copy the edited password,
save an encrypted local vault, upload the sealed vault blob to the VPS sync
service, and restore a sealed vault from the VPS on a fresh client.

This is a real hardening step over the KV2 prototype, but it is not the final
design. Before a public release, move the KDF to Argon2id (or scrypt) and the
cipher to a single AEAD primitive (XChaCha20-Poly1305 or AES-GCM), then get the
format reviewed. Both changes need native bindings that the current compiler
allowlist does not expose yet.

## Security Gates

Before a hardened public release, the macOS build needs:

- [ ] Argon2id or another reviewed memory-hard KDF for the master password.
      KV3 currently uses PBKDF2-HMAC-SHA256 at 600,000 iterations.
- [ ] Authenticated encryption for vault data, preferably XChaCha20-Poly1305 or
      AES-GCM through a reviewed platform/library binding. KV3 currently uses
      AES-256-CBC + HMAC-SHA256 encrypt-then-MAC.
- [x] Secure random bytes from the OS.
- [x] A vault file format with version, KDF parameters, salt, IV, ciphertext,
      and auth tag (KV3).
- [ ] Local auto-lock behavior.
- [x] No plaintext vault writes, logs, crash dumps, or sync payloads.

The Windows second build can reuse the OKUI product shell and wire the crypto
through CNG (`bcrypt.dll`). Linux should come after the sync and vault format
are stable.

## VPS Role

The VPS can stay deliberately boring:

- HTTPS API
- user account records
- device/session records
- encrypted vault blob revisions
- conflict metadata
- encrypted backup retention

The server must not receive the master password, derived vault key, plaintext
items, or decrypted metadata.

The deployable sync server lives at:

```text
tools/vault_sync_server.py
```

It uses only the Python standard library and stores opaque client-encrypted
vault blobs in SQLite. Uploads are capped by `KRYPTON_VAULT_MAX_BLOB_BYTES`,
which defaults to 10 MB.

Run it on the VPS behind nginx/Caddy/Apache TLS termination:

```bash
export HOST=127.0.0.1
export PORT=8080
export KRYPTON_VAULT_TOKEN='change-this-long-random-token'
export KRYPTON_VAULT_DATA="$HOME/.config/krypton-vault/server"
python3 tools/vault_sync_server.py
```

Deployable VPS files live in:

```text
deploy/
```

That folder includes a systemd unit, env-file example, Caddy reverse-proxy
stanza, and operator README.

The pure-Krypton server experiment lives at:

```text
tests/vault_sync_server.ks
```

Keep that as a language/runtime target for later. The tested VPS path for now is
the Python daemon.

Health check:

```bash
curl https://kry.li/health
```

Vault fetch:

```bash
curl 'https://kry.li/v1/vault?user=alice&token=TOKEN'
```

Raw sealed-vault fetch for desktop restore:

```bash
curl -G https://kry.li/v1/vault/blob \
  --data-urlencode 'user=alice' \
  --data-urlencode 'token=TOKEN'
```

Vault upload:

```bash
curl -X POST https://kry.li/v1/vault \
  -d 'user=alice' \
  -d 'token=TOKEN' \
  -d 'rev=1' \
  --data-urlencode 'blob=OPAQUE_CLIENT_ENCRYPTED_BLOB'
```

This server is not the security boundary. It is a dumb sync target. The desktop
client must encrypt before upload and authenticate/decrypt after download.

## Minimal Sync API

```text
GET  /v1/vault
GET  /v1/vault/blob
POST /v1/vault
GET  /health
```

For the first VPS, SQLite is enough. The hard part is the client crypto and the
update/conflict rules, not storage size.

## Local Vault Format

KV3 is text-shaped for easier debugging. The tag covers the canonical header
and ciphertext, so changing any field invalidates the vault:

```text
KV3
kdf=pbkdf2-hmac-sha256
iterations=600000
cipher=aes-256-cbc-hmac-sha256
salt=...
iv=...
ciphertext=...
tag=...
```

`vaultOpen` still reads the older KV2 format for migration, but KV2 is never
written. The next save after unlocking a legacy vault writes KV3. The format
modules are split so the envelope can be shared across platforms:

```text
stdlib/vault_format.k          portable KV3 envelope and MAC input
stdlib/vault_crypto_macos.k    macOS primitives and seal/open
```

The remaining public-release work is Argon2id (or scrypt) plus a single AEAD
primitive, which requires new native bindings.

The decrypted payload is currently structured JSON. Old `KVPLAIN1`
tab-delimited local payloads can still be rendered by the app, but new saves
use:

```text
KVJSON1
{"version":1,"items":[{"title":"...","username":"...","url":"...","password":"..."}]}
```

This JSON shape is still intentionally small. Sharing, attachments, item IDs,
timestamps, and conflict resolution should extend this payload before browser
extensions or mobile clients.

## Verification

Full local verification:

```bash
tools/vault_verify.sh
```

That builds the macOS app, checks the structured vault format, checks
seal/open crypto, syntax-checks the VPS daemon, starts a local sync server,
exercises health/upload/fetch/raw restore, and shuts the server down.

Individual local checks:

```bash
KRYPTON_LANG_ROOT=../krypton tools/vault_verify.sh
python3 -m py_compile tools/vault_sync_server.py
```

For the sync server:

```bash
export BASE_URL=http://127.0.0.1:8080
export KRYPTON_VAULT_TOKEN='change-this-long-random-token'
tools/vault_sync_smoke.sh
```

## Next Implementation Step

KV3 now carries the shared envelope, and macOS can seal/open it locally:

```text
version
kdf name and parameters
salt
iv
ciphertext
auth tag
```

The remaining hardening is native work:

- Add `CCCryptorCreateWithMode` to `headers/commoncrypto_macos.krh` and
  allowlist `CCKeyDerivationPBKDF` plus `CCCryptorCreateWithMode` in the
  Krypton backend, or vendor libsodium for `crypto_pwhash` and
  XChaCha20-Poly1305.
- Move the KDF to Argon2id (or scrypt) and the cipher to a single AEAD.
- Reuse `stdlib/vault_format.k` for the Windows CNG and Linux backends.

Once the macOS format is reviewed, Windows can implement the same envelope
through CNG and reuse the app flow.
