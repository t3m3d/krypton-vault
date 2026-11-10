#!/usr/bin/env kr
// vault_model_smoke.ks -- typed item model: logins, notes, removal, migration.

import "k:vault_model"
import "k:json_parse"

func fail(msg) {
    printErr(msg)
    exit(1)
}

just run {
    if vmCount(vmEmptyPlain()) != 0 { fail("empty vault has items") }
    if vmHasItems(vmEmptyPlain()) != "0" { fail("empty vault reported as non-empty") }

    let plain = vmEmptyPlain()
    plain = vmAppend(plain, vmLoginItem("GitHub", "me@example.com", "https://github.com", "s3cret"))
    plain = vmAppend(plain, vmNoteItem("Recovery codes", "1111-2222\n3333-4444"))
    if vmCount(plain) != 2 { fail("wrong item count") }
    if vmHasItems(plain) != "1" { fail("non-empty vault reported as empty") }

    let parsed = jpParse(vmPlainJson(plain))
    if vmTypeAt(parsed, "items.0") != "login" { fail("login type wrong") }
    if vmTypeAt(parsed, "items.1") != "note" { fail("note type wrong") }
    if vmNotesAt(parsed, "items.1") != "1111-2222\n3333-4444" { fail("note text lost") }
    if vmPasswordAt(parsed, "items.0") != "s3cret" { fail("login password lost") }

    if vmPasswordForQuery(plain, "GitHub") != "s3cret" { fail("login password lookup failed") }
    if vmPasswordForQuery(plain, "Recovery") != "" { fail("note returned a password") }
    if vmPasswordForQuery(plain, "3333") != "" { fail("note body matched a password") }

    // Notes are searchable by body, but listing shows a note marker.
    if contains(vmSearchHayAt(parsed, "items.1"), "3333") == 0 { fail("note body not searchable") }
    if vmEntryLineAt(parsed, "items.1") != "[note] Recovery codes" { fail("note row label wrong") }
    if vmEntryLineAt(parsed, "items.0") != "GitHub    me@example.com    https://github.com" {
        fail("login row label wrong")
    }

    // Removing the login must preserve the note and its body.
    let after = vmRemoveMatch(plain, "GitHub")
    if vmCount(after) != 1 { fail("remove count wrong") }
    let afterParsed = jpParse(vmPlainJson(after))
    if vmTypeAt(afterParsed, "items.0") != "note" { fail("note lost after remove") }
    if vmNotesAt(afterParsed, "items.0") != "1111-2222\n3333-4444" { fail("note body lost after remove") }

    // Pre-type items are logins.
    let legacyJson = "KVJSON1\n" +
        "{\"version\":1,\"items\":[{\"title\":\"Old\",\"username\":\"u\",\"url\":\"x\",\"password\":\"p\"}]}"
    let legacyParsed = jpParse(vmPlainJson(legacyJson))
    if vmTypeAt(legacyParsed, "items.0") != "login" { fail("missing type was not a login") }
    if vmPasswordForQuery(legacyJson, "Old") != "p" { fail("pre-type login password lost") }

    // Old tab-delimited payloads migrate to typed JSON without dropping items.
    let legacyPlain = "KVPLAIN1\n" +
        "GitHub\tme@example.com\thttps://github.com\ts3cret\n" +
        "Bank\tacct-42\thttps://bank.example\tp@ss\n"
    let migrated = vmMigrate(legacyPlain)
    if vmIsJson(migrated) != "1" { fail("legacy payload did not migrate") }
    if vmCount(migrated) != 2 { fail("legacy migration lost items") }
    let migratedParsed = jpParse(vmPlainJson(migrated))
    if vmTitleAt(migratedParsed, "items.1") != "Bank" { fail("legacy title lost") }
    if vmUserAt(migratedParsed, "items.1") != "acct-42" { fail("legacy username lost") }
    if vmPasswordAt(migratedParsed, "items.1") != "p@ss" { fail("legacy password lost") }

    print("vault model smoke ok")
}
