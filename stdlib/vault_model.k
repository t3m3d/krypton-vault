// vault_model.k -- portable vault payload model.
//
// No native calls and no UI live here. The macOS app, the iOS app, and the
// tests all share this module so items behave identically on every platform.
// The encrypted envelope is handled by vault_format.k plus a per-platform
// crypto backend; this module only deals with the decrypted payload.
//
// Payload shape:
//
//   KVJSON1
//   {"version":1,"items":[ ... ]}
//
// Item kinds:
//
//   {"type":"login","title":..,"username":..,"url":..,"password":..}
//   {"type":"note","title":..,"notes":..}
//
// Items written before the type field existed are treated as logins.

module vault_model

import "k:json_emit"
import "k:json_parse"

func vmEmptyJson() {
    emit jeObj2("version", jeNum(1), "items", jeArr0())
}

func vmEmptyPlain() {
    emit "KVJSON1\n" + vmEmptyJson()
}

func vmIsJson(plain) {
    if startsWith(plain, "KVJSON1\n") { emit "1" }
    emit "0"
}

func vmPlainJson(plain) {
    if startsWith(plain, "KVJSON1\n") { emit substring(plain, 8, len(plain)) }
    emit ""
}

func vmLoginItem(title, user, url, pass) {
    emit "{" +
        jeStr("type") + ":" + jeStr("login") + "," +
        jeStr("title") + ":" + jeStr(title) + "," +
        jeStr("username") + ":" + jeStr(user) + "," +
        jeStr("url") + ":" + jeStr(url) + "," +
        jeStr("password") + ":" + jeStr(pass) + "}"
}

func vmNoteItem(title, notes) {
    emit jeObj("type", jeStr("note"),
        "title", jeStr(title),
        "notes", jeStr(notes))
}

// Missing type means a login, so pre-type items keep working.
func vmTypeAt(parsed, base) {
    let t = jpGet(parsed, base + ".type")
    if t == "" { emit "login" }
    emit t
}

func vmTitleAt(parsed, base)    { emit jpGet(parsed, base + ".title") }
func vmUserAt(parsed, base)     { emit jpGet(parsed, base + ".username") }
func vmUrlAt(parsed, base)      { emit jpGet(parsed, base + ".url") }
func vmPasswordAt(parsed, base) { emit jpGet(parsed, base + ".password") }
func vmNotesAt(parsed, base)    { emit jpGet(parsed, base + ".notes") }

func vmCount(plain) {
    if vmIsJson(plain) != "1" { emit 0 }
    emit jpArrLen(jpParse(vmPlainJson(plain)), "items")
}

func vmHasItems(plain) {
    if vmCount(plain) > 0 { emit "1" }
    emit "0"
}

// Text a list row is matched against. Passwords are deliberately excluded.
func vmSearchHayAt(parsed, base) {
    emit vmTitleAt(parsed, base) + " " + vmUserAt(parsed, base) + " " +
        vmUrlAt(parsed, base) + " " + vmNotesAt(parsed, base)
}

// One-line display label for a vault row (no tabs, no password).
func vmEntryLineAt(parsed, base) {
    if vmTypeAt(parsed, base) == "note" {
        emit "[note] " + vmTitleAt(parsed, base)
    }
    let line = vmTitleAt(parsed, base)
    let user = vmUserAt(parsed, base)
    let url = vmUrlAt(parsed, base)
    if user != "" { line = line + "    " + user }
    if url != "" { line = line + "    " + url }
    emit line
}

func vmAppend(plain, item) {
    if vmIsJson(plain) != "1" { emit vmEmptyPlain() }
    let js = vmPlainJson(plain)
    if contains(js, "\"items\":[]") {
        emit "KVJSON1\n" + replace(js, "\"items\":[]", "\"items\":[" + item + "]")
    }
    let arrStart = indexOf(js, "\"items\":[")
    if arrStart < 0 { emit vmEmptyPlain() }
    let close = len(js) - 2
    let prefix = substring(js, 0, close)
    let suffix = substring(js, close, len(js))
    emit "KVJSON1\n" + prefix + "," + item + suffix
}

func vmEmitItem(parsed, base) {
    if vmTypeAt(parsed, base) == "note" {
        emit vmNoteItem(vmTitleAt(parsed, base), vmNotesAt(parsed, base))
    }
    emit vmLoginItem(vmTitleAt(parsed, base), vmUserAt(parsed, base),
        vmUrlAt(parsed, base), vmPasswordAt(parsed, base))
}

func vmPasswordForQuery(plain, query) {
    let q = trim(query)
    if q == "" { emit "" }
    if vmIsJson(plain) != "1" { emit "" }
    let parsed = jpParse(vmPlainJson(plain))
    let count = jpArrLen(parsed, "items")
    let j = 0
    while j < count {
        let base = "items." + j
        if vmTypeAt(parsed, base) == "login" && contains(vmSearchHayAt(parsed, base), q) {
            emit vmPasswordAt(parsed, base)
        }
        j += 1
    }
    emit ""
}

// Remove the first item whose title/user/url/notes match; keep the rest intact.
func vmRemoveMatch(plain, query) {
    let q = trim(query)
    if q == "" { emit plain }
    if vmIsJson(plain) != "1" { emit plain }
    let parsed = jpParse(vmPlainJson(plain))
    let count = jpArrLen(parsed, "items")
    let items = ""
    let removed = 0
    let j = 0
    while j < count {
        let base = "items." + j
        if removed == 0 && contains(vmSearchHayAt(parsed, base), q) {
            removed = 1
        } else {
            let item = vmEmitItem(parsed, base)
            if items == "" { items = item } else { items = items + "\t" + item }
        }
        j += 1
    }
    if removed == 0 { emit plain }
    emit "KVJSON1\n" + jeObj2("version", jeNum(1), "items", jeArrFrom(items))
}

// Old tab-delimited payloads: title<TAB>user<TAB>url<TAB>password.
// Convert on unlock so the first save cannot drop legacy items.
func vmMigrate(plain) {
    if !startsWith(plain, "KVPLAIN1\n") { emit plain }
    let out = vmEmptyPlain()
    let n = lineCount(plain)
    let i = 1
    while i < n {
        let line = getLine(plain, i)
        let title = vmNthField(line, 0)
        if len(line) > 0 && title != "" {
            out = vmAppend(out, vmLoginItem(title, vmNthField(line, 1),
                vmNthField(line, 2), vmNthField(line, 3)))
        }
        i += 1
    }
    emit out
}

func vmNthField(line, want) {
    let start = 0
    let idx = 0
    let i = 0
    while i < len(line) {
        if line[i] == "\t" {
            if idx == want { emit substring(line, start, i) }
            idx += 1
            start = i + 1
        }
        i += 1
    }
    if idx == want { emit substring(line, start, len(line)) }
    emit ""
}
