#!/usr/bin/env kr
// vault_crypto_smoke.ks -- KV3 seal/open, tamper, and KV2 migration checks.

import "k:vault_crypto_macos"
import "k:vault_format"
import "k:json_emit"

func fail(msg) {
    printErr(msg)
    exit(1)
}

// Flip one hex digit of a named field without changing its length.
func tamperField(sealed, key) {
    let needle = key + "="
    let pos = toInt(indexOf(sealed, needle))
    if pos < 0 { emit sealed }
    let at = pos + len(needle)
    let c = sealed[at]
    let repl = "0"
    if c == "0" { repl = "1" }
    emit substring(sealed, 0, at) + repl + substring(sealed, at + 1, len(sealed))
}

just run {
    let master = "correct horse battery staple"
    let item = jeObj4("title", jeStr("GitHub"), "username", jeStr("me"), "url", jeStr("https://github.com"), "password", jeStr("secret"))
    let plain = "KVJSON1\n" + jeObj2("version", jeNum(1), "items", jeArr1(item))

    let sealed = vaultSeal(master, plain)
    if sealed == "" { fail("seal failed") }
    if !startsWith(sealed, "KV3\n") { fail("seal is not KV3") }
    if kvLineVal(sealed, "kdf") != "pbkdf2-hmac-sha256" { fail("kdf field missing") }
    if kvLineVal(sealed, "cipher") != "aes-256-cbc-hmac-sha256" { fail("cipher field missing") }
    if kvLineVal(sealed, "iterations") != "600000" { fail("iteration count wrong") }
    if vaultIsSealed(sealed) != "1" { fail("sealed detection failed") }

    if vaultOpen(master, sealed) != plain { fail("round trip failed") }
    if vaultOpen("wrong password!!", sealed) != "" { fail("wrong password accepted") }
    if vaultSeal("short", plain) != "" { fail("short master accepted") }

    if vaultOpen(master, tamperField(sealed, "ciphertext")) != "" { fail("ciphertext tamper accepted") }
    if vaultOpen(master, tamperField(sealed, "tag")) != "" { fail("tag tamper accepted") }
    if vaultOpen(master, tamperField(sealed, "iv")) != "" { fail("iv tamper accepted") }
    if vaultOpen(master, tamperField(sealed, "salt")) != "" { fail("salt tamper accepted") }

    let rounds = kvLineVal(sealed, "iterations")
    let downgraded = replace(sealed, "iterations=" + rounds, "iterations=1")
    if vaultOpen(master, downgraded) != "" { fail("iteration downgrade accepted") }

    if vaultOpen(master, substring(sealed, 0, len(sealed) - 1)) != "" { fail("truncated vault accepted") }
    if vaultIsSealed("not a vault") != "0" { fail("plaintext detected as sealed") }

    // Legacy private-alpha KV2 vault, master "correct horse battery staple".
    let legacy = "KV2\n" +
        "kdf=hmac-sha256-2block\n" +
        "iterations=1\n" +
        "cipher=aes-256-cbc-hmac-sha256\n" +
        "salt=5fe2ff04262df1395635ac8334081937\n" +
        "iv=30de1ff739b66833fb4ee88ed7232f56\n" +
        "tag=eee45dc3d81718529249bc92d1b11f06be7ad80330413b1ec0e173ce460d7cac\n" +
        "ciphertext=6346862fe64df7245b87381d2a3b68d4479853fc37a4e9aad493c9257459ffb5fc22fe67f0e607e384a5bc89c9a41eaf\n"
    let legacyPlain = "KVJSON1\n" + jeObj2("version", jeNum(1), "items", jeArr0())
    if vaultIsSealed(legacy) != "1" { fail("legacy detection failed") }
    if vaultOpen(master, legacy) != legacyPlain { fail("legacy KV2 open failed") }
    if vaultOpen("wrong password!!", legacy) != "" { fail("legacy wrong password accepted") }

    // Local file handling: permissions, atomic save, and KV2 -> KV3 upgrade.
    if sealLocalVault(master, plain) != "1" { fail("local seal failed") }
    if openLocalVault(master) != plain { fail("local open failed") }
    if openLocalVault("wrong password!!") != "" { fail("local wrong password accepted") }

    let fileMode = trim(exec("stat -f %Lp \"" + localVaultPath() + "\""))
    if fileMode != "600" { fail("vault file mode is " + fileMode) }
    let dirMode = trim(exec("stat -f %Lp \"" + environ("HOME") + "/.config/krypton-vault\""))
    if dirMode != "700" { fail("vault dir mode is " + dirMode) }

    // Drop a legacy blob in place and confirm unlock rewrites it as KV3.
    writeFile(localVaultPath(), legacy)
    exec("chmod 600 \"" + localVaultPath() + "\"")
    if openLocalVault(master) != legacyPlain { fail("local legacy open failed") }
    let upgraded = readFile(localVaultPath())
    if startsWith(upgraded, "KV3\n") == 0 { fail("legacy vault did not upgrade to KV3") }
    if vaultOpen(master, upgraded) != legacyPlain { fail("upgraded vault does not open") }

    kp("vault crypto smoke ok")
}
