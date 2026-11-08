// vault_format.k -- portable KV3 vault envelope.
//
// No native calls live here: this module is the part that should be identical
// on macOS, Windows, and Linux. The platform crypto backend supplies
// ciphertext, salt, IV, and tag; this module defines and validates the text
// envelope and the exact bytes covered by the authentication tag.

module vault_format

func kv3Version() { emit "KV3" }
func kv3Kdf() { emit "pbkdf2-hmac-sha256" }
func kv3Cipher() { emit "aes-256-cbc-hmac-sha256" }
func kv3DefaultIterations() { emit "600000" }
func kv3MinIterations() { emit "210000" }

// Return the value of "key=..." in a newline-delimited envelope, or "".
func kvLineVal(blob, key) {
    let needle = key + "="
    let n = lineCount(blob)
    let i = 0
    while i < n {
        let line = getLine(blob, i)
        if startsWith(line, needle) { emit substring(line, len(needle), len(line)) }
        i += 1
    }
    emit ""
}

func kvIsHex(s) {
    if len(s) == 0 { emit "0" }
    let i = 0
    while i < len(s) {
        let c = s[i]
        let ok = (c >= "0" && c <= "9") || (c >= "a" && c <= "f") || (c >= "A" && c <= "F")
        if !ok { emit "0" }
        i += 1
    }
    emit "1"
}

func kvIsDigits(s) {
    if len(s) == 0 || len(s) > 12 { emit "0" }
    let i = 0
    while i < len(s) {
        let c = s[i]
        if c < "0" || c > "9" { emit "0" }
        i += 1
    }
    emit "1"
}

// Canonical bytes authenticated by the tag. Field order is fixed and the tag
// itself is excluded. Changing any parameter invalidates the tag.
func kv3MacInput(kdf, iterations, cipherName, saltHex, ivHex, cipherHex) {
    emit "KV3\n" +
        "kdf=" + kdf + "\n" +
        "iterations=" + iterations + "\n" +
        "cipher=" + cipherName + "\n" +
        "salt=" + saltHex + "\n" +
        "iv=" + ivHex + "\n" +
        "ciphertext=" + cipherHex + "\n"
}

func kv3Serialize(macInput, tag) {
    emit macInput + "tag=" + tag + "\n"
}
