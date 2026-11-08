// vault_crypto_macos.k -- native macOS crypto for Krypton Vault.
//
// KV3 hardened format:
// - SecRandomCopyBytes for salt/IV
// - PBKDF2-HMAC-SHA256, default 600000 iterations, derives 64 bytes:
//   bytes 0..31 encrypt key, bytes 32..63 MAC key
// - AES-256-CBC/PKCS7 with a fresh random IV
// - HMAC-SHA256 over the canonical KV3 header + ciphertext (encrypt-then-MAC)
//
// KV2 (private alpha) is still readable for migration but is never written.
//
// Residual gap before a public release: PBKDF2 is not memory-hard and this is
// CBC+HMAC, not a single AEAD primitive. Argon2id (or scrypt) and
// XChaCha20-Poly1305/AES-GCM require new native bindings; see README.

module vault_crypto_macos

import "head:commoncrypto_macos"
import "head:security_macos"
import "k:bitwise"
import "k:vault_format"

func _hexNib(c) {
    if c >= "0" && c <= "9" {
        emit charCode(c) - charCode("0")
    } else if c >= "a" && c <= "f" {
        emit charCode(c) - charCode("a") + 10
    } else if c >= "A" && c <= "F" {
        emit charCode(c) - charCode("A") + 10
    } else {
        emit 0
    }
}

func _hexByte(b) {
    let chars = "0123456789abcdef"
    emit chars[(b / 16) % 16] + chars[b % 16]
}

func _bytesToHex(buf, n) {
    let out = sbNew()
    let i = 0
    while i < n {
        out = sbAppend(out, _hexByte(toInt(bufGetByte(buf, i))))
        i += 1
    }
    emit sbToString(out)
}

func _hexToBuf(hex) {
    let n = len(hex) / 2
    let buf = bufNew(n)
    let i = 0
    while i < n {
        let b = _hexNib(hex[i * 2]) * 16 + _hexNib(hex[i * 2 + 1])
        bufSetByte(buf, i, b)
        i += 1
    }
    emit buf
}

func _copyBuf(src, n) {
    let out = bufNew(n)
    let i = 0
    while i < n {
        bufSetByte(out, i, bufGetByte(src, i))
        i += 1
    }
    emit out
}

func _bufRange(src, start, n) {
    let out = bufNew(n)
    let i = 0
    while i < n {
        bufSetByte(out, i, bufGetByte(src, start + i))
        i += 1
    }
    emit out
}

func _joinBuf(a, an, b, bn) {
    let out = bufNew(an + bn)
    let i = 0
    while i < an {
        bufSetByte(out, i, bufGetByte(a, i))
        i += 1
    }
    let j = 0
    while j < bn {
        bufSetByte(out, an + j, bufGetByte(b, j))
        j += 1
    }
    emit out
}

func _xorInto(dst, src, n) {
    let i = 0
    while i < n {
        bufSetByte(dst, i, bitXor(toInt(bufGetByte(dst, i)), toInt(bufGetByte(src, i))))
        i += 1
    }
    emit "1"
}

func _bufToString(buf, n) {
    let out = sbNew()
    let i = 0
    while i < n {
        out = sbAppend(out, fromCharCode(bufGetByte(buf, i)))
        i += 1
    }
    emit sbToString(out)
}

func _stringToBuf(s) {
    let buf = bufNew(len(s))
    let i = 0
    while i < len(s) {
        bufSetByte(buf, i, charCode(s[i]))
        i += 1
    }
    emit buf
}

func _randHex(nBytes) {
    let buf = bufNew(nBytes)
    let st = SecRandomCopyBytes(0, nBytes, buf)
    if st != 0 { emit "" }
    emit _bytesToHex(buf, nBytes)
}

func _constantEq(a, b) {
    if len(a) != len(b) { emit 0 }
    let diff = 0
    let i = 0
    while i < len(a) {
        if a[i] != b[i] { diff = 1 }
        i += 1
    }
    if diff == 0 {
        emit 1
    } else {
        emit 0
    }
}

// PBKDF2-HMAC-SHA256, one 32-byte output block.
func _pbkdf2Block(pw, pwLen, salt, saltLen, rounds, blockIndex) {
    let msg = bufNew(saltLen + 4)
    let i = 0
    while i < saltLen {
        bufSetByte(msg, i, bufGetByte(salt, i))
        i += 1
    }
    bufSetByte(msg, saltLen, 0)
    bufSetByte(msg, saltLen + 1, 0)
    bufSetByte(msg, saltLen + 2, (blockIndex / 256) % 256)
    bufSetByte(msg, saltLen + 3, blockIndex % 256)

    let u = bufNew(32)
    CCHmac(2, pw, pwLen, msg, saltLen + 4, u)
    let t = _copyBuf(u, 32)
    let scratch = bufNew(32)
    let r = 2
    while r <= rounds {
        CCHmac(2, pw, pwLen, u, 32, scratch)
        _xorInto(t, scratch, 32)
        let tmp = u
        u = scratch
        scratch = tmp
        r += 1
    }
    emit t
}

// 64-byte derived key block: first half encrypt, second half MAC.
func _pbkdf2Keys(master, saltHex, rounds) {
    let salt = _hexToBuf(saltHex)
    let pw = _stringToBuf(master)
    let k1 = _pbkdf2Block(pw, len(master), salt, 16, rounds, 1)
    let k2 = _pbkdf2Block(pw, len(master), salt, 16, rounds, 2)
    emit _joinBuf(k1, 32, k2, 32)
}

func _hmacHex(macKey, dataBuf, dataLen) {
    let out = bufNew(32)
    CCHmac(2, macKey, 32, dataBuf, dataLen, out)
    emit _bytesToHex(out, 32)
}

func _hmacHexStr(macKey, text) {
    let out = bufNew(32)
    CCHmac(2, macKey, 32, text, len(text), out)
    emit _bytesToHex(out, 32)
}

func _aesEncrypt(encKey, iv, plain) {
    let cref = bufNew(8)
    let create = CCCryptorCreate(0, 0, 1, encKey, 32, iv, cref)
    if create != 0 { emit "" }
    let cryptor = bufGetQwordAt(cref, 0)
    let out = bufNew(len(plain) + 16)
    let moved = bufNew(8)
    let st = CCCryptorUpdate(cryptor, plain, len(plain), out, len(plain) + 16, moved)
    if st != 0 { CCCryptorRelease(cryptor)  emit "" }
    let n1 = toInt(bufGetQwordAt(moved, 0))
    let finalOut = bufNew(16)
    let finalMoved = bufNew(8)
    let finalSt = CCCryptorFinal(cryptor, finalOut, 16, finalMoved)
    CCCryptorRelease(cryptor)
    if finalSt != 0 { emit "" }
    let n2 = toInt(bufGetQwordAt(finalMoved, 0))
    let joined = _joinBuf(out, n1, finalOut, n2)
    emit _bytesToHex(joined, n1 + n2)
}

func _aesDecrypt(encKey, iv, cipherBuf, cipherLen) {
    let cref = bufNew(8)
    let create = CCCryptorCreate(1, 0, 1, encKey, 32, iv, cref)
    if create != 0 { emit "" }
    let cryptor = bufGetQwordAt(cref, 0)
    let out = bufNew(cipherLen + 16)
    let moved = bufNew(8)
    let st = CCCryptorUpdate(cryptor, cipherBuf, cipherLen, out, cipherLen + 16, moved)
    if st != 0 { CCCryptorRelease(cryptor)  emit "" }
    let n1 = toInt(bufGetQwordAt(moved, 0))
    let finalOut = bufNew(16)
    let finalMoved = bufNew(8)
    let finalSt = CCCryptorFinal(cryptor, finalOut, 16, finalMoved)
    CCCryptorRelease(cryptor)
    if finalSt != 0 { emit "" }
    let n2 = toInt(bufGetQwordAt(finalMoved, 0))
    let joined = _joinBuf(out, n1, finalOut, n2)
    emit _bufToString(joined, n1 + n2)
}

func _validKv3(sealed) {
    if !startsWith(sealed, "KV3\n") { emit "0" }
    if kvLineVal(sealed, "kdf") != kv3Kdf() { emit "0" }
    if kvLineVal(sealed, "cipher") != kv3Cipher() { emit "0" }
    let iterText = kvLineVal(sealed, "iterations")
    if kvIsDigits(iterText) != "1" { emit "0" }
    if toInt(iterText) < toInt(kv3MinIterations()) { emit "0" }
    let salt = kvLineVal(sealed, "salt")
    if len(salt) != 32 || kvIsHex(salt) != "1" { emit "0" }
    let iv = kvLineVal(sealed, "iv")
    if len(iv) != 32 || kvIsHex(iv) != "1" { emit "0" }
    let tag = kvLineVal(sealed, "tag")
    if len(tag) != 64 || kvIsHex(tag) != "1" { emit "0" }
    let ct = kvLineVal(sealed, "ciphertext")
    if len(ct) == 0 || len(ct) % 32 != 0 || kvIsHex(ct) != "1" { emit "0" }
    emit "1"
}

func vaultSeal(master, plain) {
    if len(master) < 12 { emit "" }
    let roundsText = kv3DefaultIterations()
    let rounds = toInt(roundsText)
    let salt = _randHex(16)
    let ivHex = _randHex(16)
    if salt == "" || ivHex == "" { emit "" }

    let keys = _pbkdf2Keys(master, salt, rounds)
    let encKey = _bufRange(keys, 0, 32)
    let macKey = _bufRange(keys, 32, 32)
    let iv = _hexToBuf(ivHex)

    let cipherHex = _aesEncrypt(encKey, iv, plain)
    if cipherHex == "" { emit "" }

    let macInput = kv3MacInput(kv3Kdf(), roundsText, kv3Cipher(), salt, ivHex, cipherHex)
    let tag = _hmacHexStr(macKey, macInput)
    emit kv3Serialize(macInput, tag)
}

func _openKv3(master, sealed) {
    if _validKv3(sealed) != "1" { emit "" }
    let iterText = kvLineVal(sealed, "iterations")
    let salt = kvLineVal(sealed, "salt")
    let ivHex = kvLineVal(sealed, "iv")
    let tag = kvLineVal(sealed, "tag")
    let cipherHex = kvLineVal(sealed, "ciphertext")

    let keys = _pbkdf2Keys(master, salt, toInt(iterText))
    let encKey = _bufRange(keys, 0, 32)
    let macKey = _bufRange(keys, 32, 32)

    let macInput = kv3MacInput(kv3Kdf(), iterText, kv3Cipher(), salt, ivHex, cipherHex)
    let actual = _hmacHexStr(macKey, macInput)
    if _constantEq(actual, tag) == 0 { emit "" }
    if sealed != kv3Serialize(macInput, tag) { emit "" }

    let cipher = _hexToBuf(cipherHex)
    let cipherLen = len(cipherHex) / 2
    let iv = _hexToBuf(ivHex)
    emit _aesDecrypt(encKey, iv, cipher, cipherLen)
}

// Legacy KV2 derivation, read-only. Kept only so private-alpha vaults migrate.
func _legacyDeriveBlock(master, saltHex, blockIndex) {
    let salt = _hexToBuf(saltHex)
    let masterBuf = _stringToBuf(master)
    let msg = bufNew(20)
    let i = 0
    while i < 16 {
        bufSetByte(msg, i, bufGetByte(salt, i))
        i += 1
    }
    bufSetByte(msg, 16, 0)
    bufSetByte(msg, 17, 0)
    bufSetByte(msg, 18, 0)
    bufSetByte(msg, 19, blockIndex)
    let out = bufNew(32)
    CCHmac(2, masterBuf, len(master), msg, 20, out)
    emit _bytesToHex(out, 32)
}

func _openKv2Legacy(master, sealed) {
    let salt = kvLineVal(sealed, "salt")
    let ivHex = kvLineVal(sealed, "iv")
    let tag = kvLineVal(sealed, "tag")
    let cipherHex = kvLineVal(sealed, "ciphertext")
    if len(salt) != 32 || kvIsHex(salt) != "1" { emit "" }
    if len(ivHex) != 32 || kvIsHex(ivHex) != "1" { emit "" }
    if len(tag) != 64 || kvIsHex(tag) != "1" { emit "" }
    if len(cipherHex) == 0 || len(cipherHex) % 32 != 0 || kvIsHex(cipherHex) != "1" { emit "" }
    let encKey = _hexToBuf(_legacyDeriveBlock(master, salt, 1))
    let macKey = _hexToBuf(_legacyDeriveBlock(master, salt, 2))
    let cipher = _hexToBuf(cipherHex)
    let cipherLen = len(cipherHex) / 2
    let actual = _hmacHex(macKey, cipher, cipherLen)
    if _constantEq(actual, tag) == 0 { emit "" }
    let iv = _hexToBuf(ivHex)
    emit _aesDecrypt(encKey, iv, cipher, cipherLen)
}

func vaultOpen(master, sealed) {
    if startsWith(sealed, "KV3\n") { emit _openKv3(master, sealed) }
    if startsWith(sealed, "KV2\n") { emit _openKv2Legacy(master, sealed) }
    emit ""
}

func vaultIsSealed(sealed) {
    if startsWith(sealed, "KV3\n") { emit "1" }
    if startsWith(sealed, "KV2\n") { emit "1" }
    emit "0"
}

func localVaultPath() {
    emit environ("HOME") + "/.config/krypton-vault/vault.kv"
}

func sealLocalVault(master, plain) {
    let sealed = vaultSeal(master, plain)
    if sealed == "" { emit "0" }
    let dir = environ("HOME") + "/.config/krypton-vault"
    let path = localVaultPath()
    let tmp = path + ".tmp"
    exec("mkdir -p \"" + dir + "\" && chmod 700 \"" + dir + "\"")
    // writeFile has no useful return value; confirm the bytes landed on disk.
    writeFile(tmp, sealed)
    if readFile(tmp) != sealed { emit "0" }
    exec("chmod 600 \"" + tmp + "\"")
    exec("mv -f \"" + tmp + "\" \"" + path + "\"")
    exec("chmod 600 \"" + path + "\"")
    emit "1"
}

func openLocalVault(master) {
    let sealed = readFile(localVaultPath())
    let plain = vaultOpen(master, sealed)
    if plain != "" && startsWith(sealed, "KV2\n") {
        sealLocalVault(master, plain)
    }
    emit plain
}
