#!/usr/bin/env kr
// krypton_vault.ks -- Krypton Vault: local, encrypted password manager.
//
// NordPass-inspired dark UI. Three columns: a category sidebar, a searchable
// item list, and a detail pane with per-field copy buttons, an inline
// password generator, and typed items (login / note / card / identity).
// Local encryption only; no network access of any kind.
//
// Harden the prototype KDF before a public release.

import "k:okui"
import "k:objc"
import "k:json_emit"
import "k:vault_crypto_macos"
import "k:vault_model"
import "k:json_parse"

// --------------------------------------------------------------- palette
func cBg()        { emit rgb(17, 20, 27) }
func cSidebar()   { emit rgb(11, 14, 20) }
func cListPane()  { emit rgb(19, 23, 31) }
func cPanel()     { emit rgb(28, 33, 44) }
func cLime()      { emit rgb(201, 247, 58) }
func cTeal()      { emit rgb(0, 214, 178) }
func cText()      { emit rgb(238, 240, 245) }
func cMuted()     { emit rgb(139, 148, 163) }
func cDanger()    { emit rgb(255, 107, 107) }
func cNearBlack() { emit rgb(14, 17, 22) }

func appH() { emit sharedApp() }
func setTextState(key, value) { doSet(appH(), key, nsString(value)); emit "1" }
func textState(key) {
    let boxed = get(appH(), key)
    if boxed == 0 { emit "" }
    emit msg(boxed, "UTF8String")
}
func setNS(key, obj) { doSet(appH(), key, obj); emit "1" }
func getNS(key) { emit get(appH(), key) }
func setInt(key, n) { setNS(key, okNumber(n)) }
func getInt(key) {
    let boxed = getNS(key)
    if boxed == 0 { emit 0 }
    emit okNumberValue(boxed)
}
func vw(key) { emit getNS(key) }
func fieldText(key) { emit okText(vw(key)) }
func setFieldText(key, value) { doText(vw(key), value); emit "1" }
func notesValue(key) { emit textBoxValue(vw(key)) }
func setNotesValue(key, value) { doTextBox(vw(key), value); emit "1" }

// ---------------------------------------------------------- primitives
func monoFont(size) { emit okMonoFont(size) }
func styleLabel(lbl, color, size, bold) {
    doTextColor(lbl, color)
    if bold == 1 { okSetFont(lbl, boldFont(size)) } else { okSetFont(lbl, textFont(size)) }
    emit lbl
}
func wire(btn, key, handler) {
    doClick(btn, key, handler)
    emit "1"
}

func textFont(size) { emit msg_d1(cls("NSFont"), "systemFontOfSize:", size) }
func boldFont(size) { emit msg_d1(cls("NSFont"), "boldSystemFontOfSize:", size) }
func labelAt(win, text, x, y, w, color, size, bold) {
    let lbl = label(win, text, area(x, y, w, size + 8))
    doTextColor(lbl, color)
    if bold == 1 { okSetFont(lbl, boldFont(size)) } else { okSetFont(lbl, textFont(size)) }
    emit lbl
}
func flatButton(win, title, x, y, w, h, fg) {
    let btn = button(win, title, area(x, y, w, h))
    okBordered(btn, 0)
    okSetButtonTextColor(btn, fg)
    emit btn
}
func limeTextButton(win, title, x, y, w, h) {
    let btn = flatButton(win, title, x, y, w, h, cLime())
    okSetFont(btn, boldFont(13))
    emit btn
}
func darkCell(fld) {
    msg_1(msg(fld, "cell"), "setBackgroundColor:", cPanel())
    msg_1(msg(fld, "cell"), "setDrawsBackground:", 1)
    emit fld
}
func fieldAt(win, x, y, w, h, placeholder) {
    let fld = field(win, area(x, y, w, h))
    doPlaceholder(fld, placeholder)
    okBordered(fld, 0)
    okBezeled(fld, 0)
    doTextColor(fld, cText())
    darkCell(fld)
    emit fld
}
func passwordAt(win, x, y, w, h, placeholder) {
    let fld = password(win, area(x, y, w, h))
    doPlaceholder(fld, placeholder)
    okBordered(fld, 0)
    okBezeled(fld, 0)
    doTextColor(fld, cText())
    darkCell(fld)
    emit fld
}
func trackField(win, key, x, y, w, h, placeholder, isPassword) {
    let fld
    if isPassword == 1 { fld = passwordAt(win, x, y, w, h, placeholder) } else { fld = fieldAt(win, x, y, w, h, placeholder) }
    doSet(appH(), key, fld)
    emit fld
}
func trackLabel(win, key, text, x, y, w, color, size, bold) {
    let lbl = labelAt(win, text, x, y, w, color, size, bold)
    doSet(appH(), key, lbl)
    emit lbl
}
func trackButton(win, key, title, x, y, w, h, fg) {
    let btn = flatButton(win, title, x, y, w, h, fg)
    doSet(appH(), key, btn)
    emit btn
}

// ---------------------------------------------------- random password
func _hexNib(c) {
    if c >= "0" && c <= "9" { emit charCode(c) - charCode("0") }
    if c >= "a" && c <= "f" { emit charCode(c) - charCode("a") + 10 }
    if c >= "A" && c <= "F" { emit charCode(c) - charCode("A") + 10 }
    emit 0
}
func randomChar() {
    let alphabet = "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%&*"
    let want = len(alphabet)
    let tries = 0
    while 1 == 1 {
        let hx = _randHex(1)
        let v = _hexNib(substring(hx, 0, 1)) * 16 + _hexNib(substring(hx, 1, 2))
        if v < 248 { emit substring(alphabet, v % want, v % want + 1) }
        tries += 1
        if tries >= 64 { emit "x" }
    }
}
func genPassword(length) {
    let out = ""
    while len(out) < length { out = out + randomChar() }
    emit out
}

// --------------------------------------------------------- state helpers
func currentPlain() {
    let p = textState("vault.plain")
    if p == "" || vmIsJson(p) != "1" {
        p = vmEmptyPlain()
        setTextState("vault.plain", p)
    }
    emit p
}
func currentParsed() { emit jpParse(vmPlainJson(currentPlain())) }
func master() { emit textState("vault.master") }
func sel() { emit getInt("vault.sel") }
func cat() { emit getInt("vault.cat") }

// --------------------------------------------------------- table sources
func tableRows(self, cmd, table) {
    let mode = msg(get(table, "mode"), "UTF8String")
    if mode == "cats" { emit 5 }
    let vis = get(table, "vis")
    if vis == 0 { emit 0 }
    emit okArrayCount(vis)
}
func itemSubtitle(parsed, base) {
    let t = vmTypeAt(parsed, base)
    if t == "note" { emit "Secure note" }
    if t == "card" {
        let n = vmCardNumberAt(parsed, base)
        if len(n) >= 4 { emit "Card ending in " + substring(n, len(n) - 4, len(n)) }
        emit "Credit card"
    }
    if t == "identity" {
        let e = vmEmailAt(parsed, base)
        if e != "" { emit e }
        let nm = vmFullNameAt(parsed, base)
        if nm != "" { emit nm }
        emit "Identity"
    }
    let user = vmUserAt(parsed, base)
    if user != "" { emit user }
    let url = vmUrlAt(parsed, base)
    if url != "" { emit url }
    emit "Login"
}
func itemLine(parsed, base) {
    let title = vmTitleAt(parsed, base)
    if title == "" { title = "Untitled" }
    emit title + "   •   " + itemSubtitle(parsed, base)
}
func tableCell(self, cmd, table, col, row) {
    let mode = msg(get(table, "mode"), "UTF8String")
    if mode == "cats" {
        let lines = get(table, "catlines")
        if lines == 0 { emit nsString("") }
        emit okArrayGet(lines, row)
    }
    let vis = get(table, "vis")
    if vis == 0 || row >= okArrayCount(vis) { emit nsString("") }
    let idx = toInt(nsToStr(okArrayGet(vis, row)))
    emit nsString(itemLine(currentParsed(), "items." + idx))
}
func selectedVisibleRow(table) {
    let s = sel()
    if s < 0 { emit 0 - 1 }
    let vis = get(table, "vis")
    if vis == 0 { emit 0 - 1 }
    let j = 0
    let n = okArrayCount(vis)
    while j < n {
        if toInt(nsToStr(okArrayGet(vis, j))) == s { emit j }
        j += 1
    }
    emit 0 - 1
}
func setStatus(msg) {
    doText(vw("statusRight"), msg)
    emit "1"
}

// --------------------------------------------------------- refresh cycle
func refreshAll() {
    let plain = currentPlain()
    let parsed = jpParse(vmPlainJson(plain))
    setTextState("vault.parsed", parsed)
    let count = jpArrLen(parsed, "items")
    let itemsTable = vw("itemsTable")
    let catsTable = vw("catsTable")
    if itemsTable == 0 || catsTable == 0 { emit "1" }
    let q = trim(msg(vw("search"), "UTF8String"))
    let c = cat()

    let cLogin = 0
    let cNote = 0
    let cCard = 0
    let cIdentity = 0
    let j = 0
    while j < count {
        let base = "items." + j
        let t = vmTypeAt(parsed, base)
        if t == "note" { cNote += 1 }
        if t == "card" { cCard += 1 }
        if t == "identity" { cIdentity += 1 }
        if t == "login" { cLogin += 1 }
        j += 1
    }
    let catlines = okArray()
    okArrayAdd(catlines, nsString("All Items  " + count))
    okArrayAdd(catlines, nsString("Logins  " + cLogin))
    okArrayAdd(catlines, nsString("Secure Notes  " + cNote))
    okArrayAdd(catlines, nsString("Credit Cards  " + cCard))
    okArrayAdd(catlines, nsString("Identities  " + cIdentity))

    let vis = okArray()
    j = 0
    while j < count {
        let base = "items." + j
        let t = vmTypeAt(parsed, base)
        let show = 1
        if c == 1 && t != "login" { show = 0 }
        if c == 2 && t != "note" { show = 0 }
        if c == 3 && t != "card" { show = 0 }
        if c == 4 && t != "identity" { show = 0 }
        if show == 1 && q != "" {
            if contains(vmSearchHayAt(parsed, base), q) == 0 { show = 0 }
        }
        if show == 1 { okArrayAdd(vis, nsString("" + j)) }
        j += 1
    }

    doSet(itemsTable, "vis", vis)
    doSet(itemsTable, "mode", nsString("items"))
    doSet(catsTable, "catlines", catlines)
    doSet(catsTable, "mode", nsString("cats"))
    okReload(itemsTable)
    okReload(catsTable)

    let selRow = selectedVisibleRow(itemsTable)
    if selRow >= 0 { okSelectRow(itemsTable, selRow, 0) }

    doText(vw("statusLeft"), "Local vault  ·  " + count + " items")
    doText(vw("visibleCount"), "" + okArrayCount(vis) + " shown")
    emit "1"
}

// ------------------------------------------------------ detail pane
func detailViewKeys() {
    emit "titleField usernameField passwordField urlField holderField numberField expiryField cvvField fullNameField emailField phoneField addressField notesBox btnCopyUser btnCopyPass btnCopyUrl btnCopyHolder btnCopyNumber btnCopyExpiry btnCopyCvv btnCopyFullName btnCopyEmail btnCopyPhone btnCopyAddress btnCopyNotes btnGen btnSave btnDelete"
}
func groupKeys(t) {
    if t == "card" { emit "holderField numberField expiryField cvvField btnCopyHolder btnCopyNumber btnCopyExpiry btnCopyCvv" }
    if t == "identity" { emit "fullNameField emailField phoneField addressField btnCopyFullName btnCopyEmail btnCopyPhone btnCopyAddress" }
    if t == "login" { emit "usernameField passwordField urlField btnCopyUser btnCopyPass btnCopyUrl btnGen" }
    emit ""
}
func setGroupHidden(keys, hidden) {
    let rest = keys
    while len(rest) > 0 {
        let sp = indexOf(rest, " ")
        if sp < 0 { sp = len(rest) }
        let key = substring(rest, 0, sp)
        okHidden(vw(key), hidden)
        if sp >= len(rest) { rest = "" } else { rest = substring(rest, sp + 1, len(rest)) }
    }
    emit "1"
}
func applyTypeRows(t) {
    setGroupHidden("usernameField passwordField urlField btnCopyUser btnCopyPass btnCopyUrl btnGen", 1)
    setGroupHidden("holderField numberField expiryField cvvField btnCopyHolder btnCopyNumber btnCopyExpiry btnCopyCvv", 1)
    setGroupHidden("fullNameField emailField phoneField addressField btnCopyFullName btnCopyEmail btnCopyPhone btnCopyAddress", 1)
    if t == "login" { setGroupHidden("usernameField passwordField urlField btnCopyUser btnCopyPass btnCopyUrl btnGen", 0) }
    if t == "card" { setGroupHidden("holderField numberField expiryField cvvField btnCopyHolder btnCopyNumber btnCopyExpiry btnCopyCvv", 0) }
    if t == "identity" { setGroupHidden("fullNameField emailField phoneField addressField btnCopyFullName btnCopyEmail btnCopyPhone btnCopyAddress", 0) }
    emit "1"
}
func enableDetail(on) {
    let rest = detailViewKeys()
    while len(rest) > 0 {
        let sp = indexOf(rest, " ")
        if sp < 0 { sp = len(rest) }
        let key = substring(rest, 0, sp)
        let v = vw(key)
        if on == 1 { doEnable(v) } else { doDisable(v) }
        if sp >= len(rest) { rest = "" } else { rest = substring(rest, sp + 1, len(rest)) }
    }
    emit "1"
}
func setEmptyState(on) {
    okHidden(vw("emptyTitle"), 1 - on)
    okHidden(vw("emptySub"), 1 - on)
    emit "1"
}
func loadDetail() {
    let plain = currentPlain()
    let parsed = jpParse(vmPlainJson(plain))
    let s = sel()
    let count = jpArrLen(parsed, "items")
    if s < 0 || s >= count {
        enableDetail(0)
        setEmptyState(1)
        setFieldText("titleField", "")
        setNotesValue("notesBox", "")
        setGroupHidden("usernameField passwordField urlField btnCopyUser btnCopyPass btnCopyUrl btnGen", 1)
        setGroupHidden("holderField numberField expiryField cvvField btnCopyHolder btnCopyNumber btnCopyExpiry btnCopyCvv", 1)
        setGroupHidden("fullNameField emailField phoneField addressField btnCopyFullName btnCopyEmail btnCopyPhone btnCopyAddress", 1)
        emit "1"
    }
    setEmptyState(0)
    enableDetail(1)
    doEnable(vw("btnSave"))
    doEnable(vw("btnDelete"))

    let base = "items." + s
    let t = vmTypeAt(parsed, base)
    setFieldText("titleField", vmTitleAt(parsed, base))
    setNotesValue("notesBox", vmNotesAt(parsed, base))
    if t == "card" {
        setFieldText("holderField", vmCardHolderAt(parsed, base))
        setFieldText("numberField", vmCardNumberAt(parsed, base))
        setFieldText("expiryField", vmCardExpiryAt(parsed, base))
        setFieldText("cvvField", vmCardCvvAt(parsed, base))
    }
    if t == "identity" {
        setFieldText("fullNameField", vmFullNameAt(parsed, base))
        setFieldText("emailField", vmEmailAt(parsed, base))
        setFieldText("phoneField", vmPhoneAt(parsed, base))
        setFieldText("addressField", vmAddressAt(parsed, base))
    }
    if t == "login" {
        setFieldText("usernameField", vmUserAt(parsed, base))
        setFieldText("passwordField", vmPasswordAt(parsed, base))
        setFieldText("urlField", vmUrlAt(parsed, base))
    }
    applyTypeRows(t)
    emit "1"
}

func jeStrq(s) { emit jeStr(s) }
func saveSelected() {
    let plain = currentPlain()
    let parsed = jpParse(vmPlainJson(plain))
    let s = sel()
    let count = jpArrLen(parsed, "items")
    if s < 0 || s >= count { emit "0" }
    let base = "items." + s
    let t = vmTypeAt(parsed, base)
    let title = trim(fieldText("titleField"))
    if title == "" { title = "Untitled" }
    let notes = notesValue("notesBox")
    let item = ""
    if t == "note" {
        item = vmNoteItem(title, notes)
    }
    if t == "card" {
        item = vmCardItem(title, fieldText("holderField"), fieldText("numberField"),
            fieldText("expiryField"), fieldText("cvvField"), notes)
    }
    if t == "identity" {
        item = vmIdentityItem(title, fieldText("fullNameField"), fieldText("emailField"),
            fieldText("phoneField"), fieldText("addressField"), notes)
    }
    if t == "login" {
        if trim(notes) != "" {
            item = "{\"type\":\"login\",\"title\":" + jeStrq(title) +
                ",\"username\":" + jeStrq(fieldText("usernameField")) +
                ",\"url\":" + jeStrq(fieldText("urlField")) +
                ",\"password\":" + jeStrq(fieldText("passwordField")) +
                ",\"notes\":" + jeStrq(notes) + "}"
        } else {
            item = vmLoginItem(title, fieldText("usernameField"), fieldText("urlField"),
                fieldText("passwordField"))
        }
    }
    let next = vmReplaceAt(plain, s, item)
    setTextState("vault.plain", next)
    if sealLocalVault(master(), next) != "1" {
        alert("Krypton Vault", "The encrypted vault could not be saved.")
        emit "0"
    }
    setStatus("Saved & encrypted")
    refreshAll()
    emit "1"
}

// ------------------------------------------------------------ handlers
func onSearchChange(field) {
    refreshAll()
    emit "1"
}
func onItemClick(self, cmd, table) {
    let selection = okSelection(table)
    if okSelectionCount(selection) == 0 { emit "1" }
    let row = okSelectionAt(selection, 0)
    let vis = get(table, "vis")
    if vis == 0 || row >= okArrayCount(vis) { emit "1" }
    let idx = toInt(nsToStr(okArrayGet(vis, row)))
    setInt("vault.sel", idx)
    loadDetail()
    emit "1"
}
func onCatClick(self, cmd, table) {
    let selection = okSelection(table)
    if okSelectionCount(selection) == 0 { emit "1" }
    let row = okSelectionAt(selection, 0)
    setInt("vault.cat", row)
    okSelectRow(table, row, 0)
    refreshAll()
    emit "1"
}
func kindForCategory() {
    let c = cat()
    if c == 2 { emit "note" }
    if c == 3 { emit "card" }
    if c == 4 { emit "identity" }
    emit "login"
}
func blankItemFor(kind) {
    if kind == "note" { emit vmNoteItem("", "") }
    if kind == "card" { emit vmCardItem("", "", "", "", "", "") }
    if kind == "identity" { emit vmIdentityItem("", "", "", "", "", "") }
    emit vmLoginItem("", "", "", "")
}
func onNewItem(self, cmd, sender) {
    let plain = currentPlain()
    let kind = kindForCategory()
    let next = vmAppend(plain, blankItemFor(kind))
    setTextState("vault.plain", next)
    let count = vmCount(next)
    setInt("vault.sel", count - 1)
    if sealLocalVault(master(), next) != "1" {
        alert("Krypton Vault", "The new item could not be encrypted and saved.")
        emit "1"
    }
    refreshAll()
    loadDetail()
    let win = vw("mainWin")
    okMakeFirstResponder(win, vw("titleField"))
    setStatus("New " + kind + " created")
    emit "1"
}
func onCopyField(self, cmd, sender) {
    let tag = toInt(msg(sender, "tag"))
    if tag == 1 { doCopyText(fieldText("usernameField")); setStatus("Copied username") }
    if tag == 2 { doCopyText(fieldText("passwordField")); setStatus("Copied password") }
    if tag == 3 { doCopyText(fieldText("urlField")); setStatus("Copied website") }
    if tag == 4 { doCopyText(fieldText("holderField")); setStatus("Copied cardholder") }
    if tag == 5 { doCopyText(fieldText("numberField")); setStatus("Copied card number") }
    if tag == 6 { doCopyText(fieldText("expiryField")); setStatus("Copied expiry") }
    if tag == 7 { doCopyText(fieldText("cvvField")); setStatus("Copied CVV") }
    if tag == 8 { doCopyText(fieldText("fullNameField")); setStatus("Copied name") }
    if tag == 9 { doCopyText(fieldText("emailField")); setStatus("Copied email") }
    if tag == 10 { doCopyText(fieldText("phoneField")); setStatus("Copied phone") }
    if tag == 11 { doCopyText(fieldText("addressField")); setStatus("Copied address") }
    if tag == 12 { doCopyText(notesValue("notesBox")); setStatus("Copied notes") }
    emit "1"
}
func onGenerate(self, cmd, sender) {
    doText(vw("passwordField"), genPassword(20))
    setStatus("Generated a strong password")
    emit "1"
}
func confirmDelete() {
    let a = msg(cls("NSAlert"), "alloc")
    a = msg(a, "init")
    msg_1(a, "setMessageText:", nsString("Delete this item?"))
    msg_1(a, "setInformativeText:", nsString("It will be removed from the encrypted vault permanently."))
    msg_1(a, "setAlertStyle:", 0)
    msg_1(a, "addButtonWithTitle:", nsString("Delete"))
    msg_1(a, "addButtonWithTitle:", nsString("Cancel"))
    emit msg(a, "runModal")
}
func onDelete(self, cmd, sender) {
    let plain = currentPlain()
    let s = sel()
    if s < 0 { emit "1" }
    if confirmDelete() != 1000 { emit "1" }
    let next = vmRemoveAt(plain, s)
    setTextState("vault.plain", next)
    if sealLocalVault(master(), next) != "1" {
        alert("Krypton Vault", "The item could not be removed from the vault.")
        emit "1"
    }
    setInt("vault.sel", 0 - 1)
    refreshAll()
    loadDetail()
    setStatus("Deleted")
    emit "1"
}
func onSave(self, cmd, sender) { emit saveSelected() }
func onFocusSearch(self, cmd, sender) {
    let win = vw("mainWin")
    okMakeFirstResponder(win, vw("search"))
    emit "1"
}

// ------------------------------------------------------ lock / unlock
func refreshLockScreen() {
    let mode = textState("vault.mode")
    let setup = mode == "setup"
    if setup {
        okHidden(vw("setupConfirm"), 0)
        okHidden(vw("unlockBtn"), 1)
        okHidden(vw("createBtn"), 0)
        doText(vw("lockTitle"), "Set up Krypton Vault")
        doText(vw("lockSub"), "Pick one master password to protect your vault.")
        doText(vw("lockFoot"), "Krypton Vault can't recover this password for you.")
    } else {
        okHidden(vw("setupConfirm"), 1)
        okHidden(vw("unlockBtn"), 0)
        okHidden(vw("createBtn"), 1)
        doText(vw("lockTitle"), "Krypton Vault")
        doText(vw("lockSub"), "Your passwords, encrypted on this Mac.")
        doText(vw("lockFoot"), "Krypton Vault can't recover this password for you.")
    }
    // Master field label footer in setup mode: hint at the confirm step
    if setup {
        doText(vw("lockHint"), "MATCH THE TWO PASSWORDS TO CONTINUE")
    } else {
        doText(vw("lockHint"), "LOCAL ENCRYPTION ONLY · NO NETWORK")
    }
    okMakeFirstResponder(vw("lockWin"), vw("unlockMaster"))
    emit "1"
}
func enterVault() {
    let opened = openLocalVault(textState("vault.master"))
    let migrated = ""
    if opened != "" { migrated = vmMigrate(opened) } else { migrated = vmEmptyPlain() }
    setTextState("vault.plain", migrated)
    let lockWin = vw("lockWin")
    let mainWin = vw("mainWin")
    msg(lockWin, "close")
    doShow(mainWin)
    refreshAll()
    loadDetail()
    okMakeFirstResponder(mainWin, vw("search"))
    setStatus("Unlocked")
    emit "1"
}
func onUnlock(self, cmd, sender) {
    let masterField = vw("unlockMaster")
    let mode = textState("vault.mode")
    if mode == "setup" { emit "1" }
    let m = msg(masterField, "UTF8String")
    if len(m) < 12 {
        alert("Krypton Vault", "Use a longer master password before opening the vault.")
        emit "1"
    }
    setTextState("vault.master", m)
    doText(masterField, "")
    emit enterVault()
}
func onCreate(self, cmd, sender) {
    let masterField = vw("unlockMaster")
    let confirmField = vw("setupConfirm")
    let m = msg(masterField, "UTF8String")
    let c = msg(confirmField, "UTF8String")
    if len(m) < 12 {
        alert("Krypton Vault", "Use at least 12 characters for your master password.")
        emit "1"
    }
    if m != c {
        alert("Krypton Vault", "The master passwords do not match.")
        emit "1"
    }
    if sealLocalVault(m, vmEmptyPlain()) != "1" {
        alert("Krypton Vault", "The encrypted vault could not be created.")
        emit "1"
    }
    setTextState("vault.master", m)
    doText(masterField, "")
    doText(confirmField, "")
    emit enterVault()
}
func onLock(self, cmd, sender) {
    let mainWin = vw("mainWin")
    setInt("vault.sel", 0 - 1)
    setTextState("vault.plain", "")
    setTextState("vault.master", "")
    let lockWin = vw("lockWin")
    doShow(lockWin)
    msg(mainWin, "close")
    okMakeFirstResponder(lockWin, vw("unlockMaster"))
    emit "1"
}

// --------------------------------------------------------- bootstrap
func navCellLines() {
    let lines = okArray()
    okArrayAdd(lines, nsString("All Items"))
    okArrayAdd(lines, nsString("Logins"))
    okArrayAdd(lines, nsString("Secure Notes"))
    okArrayAdd(lines, nsString("Credit Cards"))
    okArrayAdd(lines, nsString("Identities"))
    emit lines
}

just run {
    let application = app("Krypton Vault")

    // ---------- lock / setup window
    let lockWin = window("Krypton Vault", 460, 580)
    minSize(lockWin, 400, 520)
    doWindowBackground(lockWin, cBg())
    doTransparentTitlebar(lockWin)
    okAppearance(lockWin, nsString("NSAppearanceNameDarkAqua"))

    let lockKey = label(lockWin, "🔑", area(66, 434, 88, 84))
    okSetFont(lockKey, textFont(46))
    doTextColor(lockKey, cLime())

    trackLabel(lockWin, "lockTitle", "Krypton Vault", 70, 360, 320, cText(), 25, 1)
    trackLabel(lockWin, "lockSub", "Your passwords, encrypted on this Mac.", 70, 326, 320, cMuted(), 13, 0)
    trackLabel(lockWin, "lockFoot", "Krypton Vault can't recover this password for you.", 70, 60, 340, cMuted(), 11, 0)

    // Shared master password field (used in both modes)
    trackField(lockWin, "unlockMaster", 70, 244, 320, 38, "Master password", 1)
    // Setup-only confirm field (same slot as unlock mode, mutually exclusive)
    trackField(lockWin, "setupConfirm", 70, 184, 320, 38, "Confirm password", 1)

    let unlockBtn = limeTextButton(lockWin, "Unlock", 70, 140, 320, 42)
    wire(unlockBtn, "vault.unlock", funcptr(onUnlock))
    doSet(appH(), "unlockBtn", unlockBtn)

    let createBtn = limeTextButton(lockWin, "Create Vault", 70, 140, 320, 42)
    wire(createBtn, "vault.create", funcptr(onCreate))
    doSet(appH(), "createBtn", createBtn)

    // Hints around the fields
    trackLabel(lockWin, "lockHint", "LOCAL ENCRYPTION ONLY · NO NETWORK", 70, 110, 340, cMuted(), 10, 0)
    okSetFont(getNS("lockHint"), boldFont(9))

    // ---------- main window
    let win = window("Krypton Vault", 1100, 640)
    minSize(win, 1000, 560)
    doWindowBackground(win, cBg())
    doTransparentTitlebar(win)
    okAppearance(win, nsString("NSAppearanceNameDarkAqua"))

    // Sidebar
    let sidebarBg = textBox(win, area(0, 0, 200, 640))
    doBackground(sidebarBg, cSidebar())
    doEditable(sidebarBg, 0)
    doNoWrap(sidebarBg)

    let logoKey = label(win, "🔑", area(18, 570, 44, 44))
    okSetFont(logoKey, textFont(24))
    doTextColor(logoKey, cLime())
    let appName = label(win, "Krypton Vault", area(18, 534, 166, 22))
    styleLabel(appName, cText(), 16, 1)
    let appCaption = label(win, "LOCAL · ENCRYPTED", area(18, 514, 166, 14))
    styleLabel(appCaption, cMuted(), 9, 0)

    trackLabel(win, "navHeader", "VAULT", 22, 472, 160, cLime(), 11, 1)

    let catsTable = okTable(win, 8, 236, 184, 224)
    okColumn(catsTable, "c0", "", 184)
    okRowHeight(catsTable, 44)
    okMultiSelect(catsTable, 0)
    msg_1(catsTable, "setHeaderView:", 0)
    okSet(catsTable, "mode", nsString("cats"))
    doSet(appH(), "catsTable", catsTable)
    okOnClick(catsTable, funcptr(onCatClick))

    let newItemBtn = limeTextButton(win, "+ New Item", 18, 16, 164, 38)
    wire(newItemBtn, "vault.new", funcptr(onNewItem))

    // List pane
    let listBg = textBox(win, area(200, 0, 280, 640))
    doBackground(listBg, cListPane())
    doEditable(listBg, 0)
    doNoWrap(listBg)

    trackField(win, "search", 212, 596, 256, 30, "Search vault", 0)
    okFieldOnChange(getNS("search"), funcptr(onSearchChange))

    let itemsTable = okTable(win, 200, 46, 280, 540)
    okColumn(itemsTable, "c0", "", 280)
    okRowHeight(itemsTable, 52)
    okMultiSelect(itemsTable, 0)
    msg_1(itemsTable, "setHeaderView:", 0)
    okSet(itemsTable, "mode", nsString("items"))
    doSet(appH(), "itemsTable", itemsTable)
    okOnClick(itemsTable, funcptr(onItemClick))

    trackLabel(win, "visibleCount", "0 shown", 212, 24, 256, cMuted(), 10, 0)

    // Detail pane
    trackField(win, "titleField", 500, 564, 420, 30, "Title", 0)
    okSetFont(getNS("titleField"), boldFont(19))

    trackButton(win, "btnSave", "Save", 940, 562, 62, 30, cLime())
    wire(getNS("btnSave"), "vault.save", funcptr(onSave))
    trackButton(win, "btnDelete", "Delete", 1010, 562, 72, 30, cDanger())
    wire(getNS("btnDelete"), "vault.delete", funcptr(onDelete))

    // Login rows
    trackLabel(win, "lblUsername", "USERNAME", 500, 484, 110, cMuted(), 10, 1)
    trackField(win, "usernameField", 624, 478, 250, 30, "username", 0)
    trackButton(win, "btnCopyUser", "Copy", 902, 478, 80, 30, cLime())
    wire(getNS("btnCopyUser"), "vault.copyUser", funcptr(onCopyField))
    msg_1(getNS("btnCopyUser"), "setTag:", 1)

    trackLabel(win, "lblPassword", "PASSWORD", 500, 434, 110, cMuted(), 10, 1)
    trackField(win, "passwordField", 624, 428, 158, 30, "••••••••", 1)
    let btnGen = limeTextButton(win, "Generate", 790, 428, 92, 30)
    wire(btnGen, "vault.gen", funcptr(onGenerate))
    doSet(appH(), "btnGen", btnGen)
    trackButton(win, "btnCopyPass", "Copy", 902, 428, 80, 30, cLime())
    wire(getNS("btnCopyPass"), "vault.copyPass", funcptr(onCopyField))
    msg_1(getNS("btnCopyPass"), "setTag:", 2)

    trackLabel(win, "lblUrl", "WEBSITE", 500, 384, 110, cMuted(), 10, 1)
    trackField(win, "urlField", 624, 378, 250, 30, "https://", 0)
    trackButton(win, "btnCopyUrl", "Copy", 902, 378, 80, 30, cLime())
    wire(getNS("btnCopyUrl"), "vault.copyUrl", funcptr(onCopyField))
    msg_1(getNS("btnCopyUrl"), "setTag:", 3)

    // Card rows
    trackLabel(win, "lblHolder", "CARDHOLDER", 500, 484, 110, cMuted(), 10, 1)
    trackField(win, "holderField", 624, 478, 250, 30, "Name on card", 0)
    trackButton(win, "btnCopyHolder", "Copy", 902, 478, 80, 30, cLime())
    wire(getNS("btnCopyHolder"), "vault.copyHolder", funcptr(onCopyField))
    msg_1(getNS("btnCopyHolder"), "setTag:", 4)

    trackLabel(win, "lblNumber", "CARD NUMBER", 500, 434, 110, cMuted(), 10, 1)
    trackField(win, "numberField", 624, 428, 250, 30, "4242 4242 4242 4242", 0)
    okSetFont(getNS("numberField"), monoFont(13))
    trackButton(win, "btnCopyNumber", "Copy", 902, 428, 80, 30, cLime())
    wire(getNS("btnCopyNumber"), "vault.copyNumber", funcptr(onCopyField))
    msg_1(getNS("btnCopyNumber"), "setTag:", 5)

    trackLabel(win, "lblExpiry", "EXPIRY", 500, 384, 110, cMuted(), 10, 1)
    trackField(win, "expiryField", 624, 378, 130, 30, "12/29", 0)
    trackButton(win, "btnCopyExpiry", "Copy", 902, 378, 80, 30, cLime())
    wire(getNS("btnCopyExpiry"), "vault.copyExpiry", funcptr(onCopyField))
    msg_1(getNS("btnCopyExpiry"), "setTag:", 6)

    trackLabel(win, "lblCvv", "CVV", 500, 334, 110, cMuted(), 10, 1)
    trackField(win, "cvvField", 624, 328, 110, 30, "•••", 1)
    trackButton(win, "btnCopyCvv", "Copy", 902, 328, 80, 30, cLime())
    wire(getNS("btnCopyCvv"), "vault.copyCvv", funcptr(onCopyField))
    msg_1(getNS("btnCopyCvv"), "setTag:", 7)

    // Identity rows
    trackLabel(win, "lblFullName", "FULL NAME", 500, 484, 110, cMuted(), 10, 1)
    trackField(win, "fullNameField", 624, 478, 250, 30, "Ada Lovelace", 0)
    trackButton(win, "btnCopyFullName", "Copy", 902, 478, 80, 30, cLime())
    wire(getNS("btnCopyFullName"), "vault.copyFullName", funcptr(onCopyField))
    msg_1(getNS("btnCopyFullName"), "setTag:", 8)

    trackLabel(win, "lblEmail", "EMAIL", 500, 434, 110, cMuted(), 10, 1)
    trackField(win, "emailField", 624, 428, 250, 30, "you@example.com", 0)
    trackButton(win, "btnCopyEmail", "Copy", 902, 428, 80, 30, cLime())
    wire(getNS("btnCopyEmail"), "vault.copyEmail", funcptr(onCopyField))
    msg_1(getNS("btnCopyEmail"), "setTag:", 9)

    trackLabel(win, "lblPhone", "PHONE", 500, 384, 110, cMuted(), 10, 1)
    trackField(win, "phoneField", 624, 378, 250, 30, "+1 555 0100", 0)
    trackButton(win, "btnCopyPhone", "Copy", 902, 378, 80, 30, cLime())
    wire(getNS("btnCopyPhone"), "vault.copyPhone", funcptr(onCopyField))
    msg_1(getNS("btnCopyPhone"), "setTag:", 10)

    trackLabel(win, "lblAddress", "ADDRESS", 500, 334, 110, cMuted(), 10, 1)
    trackField(win, "addressField", 624, 328, 250, 30, "Street, city, ZIP", 0)
    trackButton(win, "btnCopyAddress", "Copy", 902, 328, 80, 30, cLime())
    wire(getNS("btnCopyAddress"), "vault.copyAddress", funcptr(onCopyField))
    msg_1(getNS("btnCopyAddress"), "setTag:", 11)

    // Notes row (all types)
    trackLabel(win, "lblNotes", "NOTES", 500, 284, 110, cMuted(), 10, 1)
    let notesBox = textBox(win, area(500, 56, 540, 210))
    doBackground(notesBox, cPanel())
    doTextColor(notesBox, cText())
    doSet(appH(), "notesBox", notesBox)
    trackButton(win, "btnCopyNotes", "Copy", 1018, 56, 60, 30, cLime())
    wire(getNS("btnCopyNotes"), "vault.copyNotes", funcptr(onCopyField))
    msg_1(getNS("btnCopyNotes"), "setTag:", 12)

    // Empty state
    trackLabel(win, "emptyTitle", "NOTHING HERE YET", 500, 340, 420, cText(), 20, 1)
    trackLabel(win, "emptySub", "Select an item, or press ⌘N to create one.", 500, 310, 500, cMuted(), 12, 0)
    okHidden(getNS("emptyTitle"), 1)
    okHidden(getNS("emptySub"), 1)

    // Status bar
    trackLabel(win, "statusLeft", "Local vault  ·  0 items", 500, 18, 320, cMuted(), 10, 0)
    trackLabel(win, "statusRight", "", 660, 18, 420, cLime(), 10, 1)

    // ---------- menus
    let bar = okMenuBar(application)
    let appMenu = okMenuAdd(bar, "Krypton Vault")
    okMenuSelector(appMenu, "Quit Krypton Vault", "q", "terminate:")
    let file = okMenuAdd(bar, "File")
    okMenuAction(file, "New Item", "n", funcptr(onNewItem))
    okMenuAction(file, "Lock Vault", "l", funcptr(onLock))
    okMenuAction(file, "Find", "f", funcptr(onFocusSearch))
    let edit = okMenuAdd(bar, "Edit")
    okMenuSelector(edit, "Cut", "x", "cut:")
    okMenuSelector(edit, "Copy", "c", "copy:")
    okMenuSelector(edit, "Paste", "v", "paste:")
    okMenuSeparator(edit)
    okMenuSelector(edit, "Select All", "a", "selectAll:")

    // Register data source for both tables
    let dsClass = okClass("KryptonVaultDataSource")
    okMethod(dsClass, "numberOfRowsInTableView:", funcptr(tableRows), "q@:@")
    okMethod(dsClass, "tableView:objectValueForTableColumn:row:", funcptr(tableCell), "@@:@@q")
    okRegister(dsClass)
    let itemsSource = okNew(dsClass)
    okDataSource(itemsTable, itemsSource)
    msg(itemsSource, "release")
    let catsSource = okNew(dsClass)
    okDataSource(catsTable, catsSource)
    msg(catsSource, "release")

    // ---------- initial visibility
    setInt("vault.sel", 0 - 1)
    setInt("vault.cat", 0)
    doSet(appH(), "mainWin", win)
    doSet(appH(), "lockWin", lockWin)
    doSet(catsTable, "catlines", navCellLines())
    okSelectRow(catsTable, 0, 0)

    let sealed = readFile(localVaultPath())
    if len(sealed) > 0 {
        setTextState("vault.mode", "unlock")
    } else {
        setTextState("vault.mode", "setup")
    }
    refreshLockScreen()
    doShow(lockWin)
    doRun()
}
