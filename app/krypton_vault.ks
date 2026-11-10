#!/usr/bin/env kr
// krypton_vault.ks -- native macOS-first shell for Krypton Vault.
//
// This is a product scaffold with encrypted local persistence and blind VPS
// sync. Harden the prototype KDF before a public release.

import "k:okui"
import "k:objc"
import "k:vault_crypto_macos"
import "k:vault_model"
import "k:json_emit"
import "k:json_parse"

func dq() { emit fromCharCode(34) }
func bs() { emit fromCharCode(92) }

func appH() { emit sharedApp() }

// doSet stores raw Krypton strings as Objective-C associated objects, which
// crashes objc_retain. Box string state as NSString and unbox on read.
func setTextState(key, value) {
    doSet(appH(), key, nsString(value))
    emit "1"
}

func textState(key) {
    let boxed = get(appH(), key)
    if boxed == 0 { emit "" }
    emit msg(boxed, "UTF8String")
}

func cleanLine(s) {
    let t = trim(s)
    if t == "0" { emit "" }
    emit t
}

func shellQuote(s) {
    emit dq() + replace(s, dq(), bs() + dq()) + dq()
}

func isDarkMode() {
    let mode = cleanLine(exec("defaults read -g AppleInterfaceStyle 2>/dev/null"))
    if contains(mode, "Dark") { emit 1 }
    emit 0
}

func vaultBg() {
    if isDarkMode() == 1 { emit rgb(28, 32, 38) }
    emit windowBackground()
}

func vaultText() {
    if isDarkMode() == 1 { emit rgb(230, 233, 236) }
    emit textColor()
}

func vaultMuted() {
    if isDarkMode() == 1 { emit rgb(156, 165, 174) }
    emit secondaryTextColor()
}

func tint(view) {
    doTextColor(view, vaultText())
    emit view
}

func tintMuted(view) {
    doTextColor(view, vaultMuted())
    emit view
}

func tintButton(view) {
    doButtonTextColor(view, vaultText())
    emit view
}

func setStatus(textValue) {
    doText(get(appH(), "status"), textValue)
    emit "1"
}

func fieldText(key) {
    emit text(get(appH(), key))
}

func nthField(line, want) {
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

func emptyVaultJson() {
    emit vmEmptyJson()
}

func emptyVaultPlain() {
    emit vmEmptyPlain()
}

func itemJson(title, user, url, pass) {
    emit vmLoginItem(title, user, url, pass)
}

func plainJson(plain) {
    emit vmPlainJson(plain)
}

func vaultJsonAppend(plain, item) {
    emit vmAppend(plain, item)
}

func normalizeBaseUrl(url) {
    let out = trim(url)
    while len(out) > 0 && out[len(out) - 1] == "/" { out = substring(out, 0, len(out) - 1) }
    emit out
}

func entryLine(title, user, url) {
    let line = title
    if user != "" { line = line + "    " + user }
    if url != "" { line = line + "    " + url }
    emit line
}

func appendVaultLine(line) {
    let vault = get(appH(), "vault")
    let count = textState("itemCount")
    if count == "" || count == "0" {
        doTextBox(vault, "")
        setTextState("itemCount", "1")
    }
    doAppend(vault, line)
    if len(line) == 0 || line[len(line) - 1] != "\n" { doAppend(vault, "\n") }
    doTextRangeColor(vault, vaultText(), 0, textLength(vault))
    emit "1"
}

func renderVaultWithFilter(plain, query) {
    let vault = get(appH(), "vault")
    let q = trim(query)
    doTextBox(vault, "")
    setTextState("itemCount", "0")
    if vmIsJson(plain) == "1" {
        let parsed = jpParse(vmPlainJson(plain))
        let count = jpArrLen(parsed, "items")
        let j = 0
        while j < count {
            let base = "items." + j
            if q == "" || contains(vmSearchHayAt(parsed, base), q) {
                appendVaultLine(vmEntryLineAt(parsed, base))
            }
            j += 1
        }
    } else {
        // Legacy KVPLAIN1 is migrated on unlock; this only covers a raw view.
        let n = lineCount(plain)
        let i = 0
        while i < n {
            let line = getLine(plain, i)
            if len(line) > 0 && line != "KVPLAIN1" {
                let hay = nthField(line, 0) + " " + nthField(line, 1) + " " + nthField(line, 2)
                if q == "" || contains(hay, q) {
                    appendVaultLine(entryLine(nthField(line, 0), nthField(line, 1), nthField(line, 2)))
                }
            }
            i += 1
        }
    }
    if textState("itemCount") == "0" {
        doTextBox(vault, "No vault items in this local session.\n")
    }
    emit "1"
}

func renderVaultPlain(plain) {
    renderVaultWithFilter(plain, "")
    emit "1"
}

func vaultFindPassword(plain, query) {
    emit vmPasswordForQuery(plain, query)
}

func vaultRemoveMatch(plain, query) {
    emit vmRemoveMatch(plain, query)
}

func clearEntryFields() {
    doText(get(appH(), "itemTitle"), "")
    doText(get(appH(), "itemUser"), "")
    doText(get(appH(), "itemUrl"), "")
    doText(get(appH(), "itemPassword"), "")
    doTextBox(get(appH(), "itemNotes"), "")
    emit "1"
}

func onUnlock(self, cmd, sender) {
    let master = fieldText("master")
    if len(master) < 12 {
        alert("Krypton Vault", "Use a longer master password before opening a vault.")
        setStatus("Locked")
        emit "1"
    }
    let opened = openLocalVault(master)
    if opened != "" {
        // Upgrade a legacy tab-delimited payload before it can be saved.
        let migrated = vmMigrate(opened)
        setTextState("vaultPlain", migrated)
        renderVaultPlain(migrated)
        if migrated != opened {
            setStatus("Unlocked vault (payload upgraded)")
        } else {
            setStatus("Unlocked saved vault")
        }
    } else {
        if textState("vaultPlain") == "" {
            setTextState("vaultPlain", emptyVaultPlain())
        }
        setStatus("Unlocked new vault")
    }
    doText(get(appH(), "lockState"), "Unlocked local session")
    doEnable(get(appH(), "addButton"))
    doEnable(get(appH(), "copyButton"))
    doEnable(get(appH(), "copyMatchButton"))
    doEnable(get(appH(), "deleteMatchButton"))
    doEnable(get(appH(), "findButton"))
    doEnable(get(appH(), "lockButton"))
    emit "1"
}

func onCreateVault(self, cmd, sender) {
    let master = fieldText("setupMaster")
    let confirm = fieldText("setupConfirm")
    if len(master) < 12 {
        alert("Krypton Vault", "Use at least 12 characters for your master password.")
        emit "1"
    }
    if master != confirm {
        alert("Krypton Vault", "The master passwords do not match.")
        emit "1"
    }
    if sealLocalVault(master, emptyVaultPlain()) != "1" {
        alert("Krypton Vault", "The encrypted vault could not be created.")
        emit "1"
    }
    doText(get(appH(), "master"), master)
    msg(get(appH(), "setupWin"), "close")
    doShow(get(appH(), "mainWin"))
    onUnlock(self, cmd, sender)
    emit "1"
}

func onLock(self, cmd, sender) {
    doText(get(appH(), "master"), "")
    doText(get(appH(), "lockState"), "Locked")
    doDisable(get(appH(), "addButton"))
    doDisable(get(appH(), "copyButton"))
    doDisable(get(appH(), "copyMatchButton"))
    doDisable(get(appH(), "deleteMatchButton"))
    doDisable(get(appH(), "findButton"))
    doDisable(get(appH(), "lockButton"))
    setTextState("vaultPlain", "")
    doTextBox(get(appH(), "vault"), "No vault items in this local session.\n")
    setTextState("itemCount", "0")
    clearEntryFields()
    setStatus("Locked")
    emit "1"
}

func onAdd(self, cmd, sender) {
    let kind = choice(get(appH(), "kind"))
    let titleValue = trim(fieldText("itemTitle"))
    if titleValue == "" {
        alert("Krypton Vault", "Add a title for this item.")
        emit "1"
    }
    let plain = textState("vaultPlain")
    if plain == "" { plain = emptyVaultPlain() }
    if startsWith(plain, "KVPLAIN1\n") { plain = vmMigrate(plain) }

    if kind == "Note" {
        let notes = textBoxValue(get(appH(), "itemNotes"))
        if trim(notes) == "" {
            alert("Krypton Vault", "Add note text before saving this item.")
            emit "1"
        }
        plain = vmAppend(plain, vmNoteItem(titleValue, notes))
        setTextState("vaultPlain", plain)
        renderVaultPlain(plain)
        clearEntryFields()
        setStatus("Added note in memory")
        emit "1"
    }

    let userValue = trim(fieldText("itemUser"))
    let urlValue = trim(fieldText("itemUrl"))
    let passValue = fieldText("itemPassword")
    if passValue == "" {
        alert("Krypton Vault", "Add a password before saving this login, or switch the type to Note.")
        emit "1"
    }
    plain = vmAppend(plain, vmLoginItem(titleValue, userValue, urlValue, passValue))
    setTextState("vaultPlain", plain)
    renderVaultPlain(plain)
    clearEntryFields()
    setStatus("Added in memory")
    emit "1"
}

func onCopyPassword(self, cmd, sender) {
    let passValue = fieldText("itemPassword")
    if passValue == "" {
        alert("Krypton Vault", "There is no password in the editor to copy.")
        emit "1"
    }
    doCopyText(passValue)
    setStatus("Password copied")
    emit "1"
}

func onCopyMatch(self, cmd, sender) {
    let query = fieldText("search")
    let passValue = vaultFindPassword(textState("vaultPlain"), query)
    if passValue == "" {
        alert("Krypton Vault", "No unlocked vault item matches that search.")
        setStatus("No match")
        emit "1"
    }
    doCopyText(passValue)
    setStatus("Matched password copied")
    emit "1"
}

func onFind(self, cmd, sender) {
    let plain = textState("vaultPlain")
    if plain == "" {
        alert("Krypton Vault", "Unlock a vault before searching.")
        emit "1"
    }
    renderVaultWithFilter(plain, fieldText("search"))
    setStatus("Filtered")
    emit "1"
}

func onDeleteMatch(self, cmd, sender) {
    let plain = textState("vaultPlain")
    if plain == "" {
        alert("Krypton Vault", "Unlock a vault before deleting.")
        emit "1"
    }
    let nextPlain = vaultRemoveMatch(plain, fieldText("search"))
    if nextPlain == plain {
        alert("Krypton Vault", "No unlocked vault item matches that search.")
        setStatus("No match")
        emit "1"
    }
    setTextState("vaultPlain", nextPlain)
    renderVaultWithFilter(nextPlain, "")
    setStatus("Deleted in memory")
    emit "1"
}

func onSync(self, cmd, sender) {
    let base = normalizeBaseUrl(fieldText("syncUrl"))
    let user = trim(fieldText("syncUser"))
    let token = fieldText("syncToken")
    if base == "" {
        alert("Krypton Vault", "Add the VPS sync URL first.")
        setStatus("Sync not configured")
        emit "1"
    }
    let out = cleanLine(exec("curl -fsS " + shellQuote(base + "/health") + " 2>&1"))
    if contains(out, "krypton-vault-sync") {
        let sealedPath = localVaultPath()
        let sealed = readFile(sealedPath)
        if sealed == "" {
            if user == "" || token == "" {
                alert("Krypton Vault", "Add account and token before restoring an encrypted vault.")
                setStatus("Sync credentials missing")
                emit "1"
            }
            let tmp = "/tmp/krypton_vault_restore.kv"
            let getCmd = "curl -fsS -G " + shellQuote(base + "/v1/vault/blob") +
                " --data-urlencode " + shellQuote("user=" + user) +
                " --data-urlencode " + shellQuote("token=" + token) +
                " -o " + shellQuote(tmp) + " 2>&1"
            let fetched = cleanLine(exec(getCmd))
            let restored = readFile(tmp)
            if vaultIsSealed(restored) == "1" {
                let master = fieldText("master")
                // Authenticate before touching the local vault: a bad or
                // tampered remote blob must never replace a good local one.
                let opened = vaultOpen(master, restored)
                if opened != "" {
                    let vaultDir = environ("HOME") + "/.config/krypton-vault"
                    let restoreTmp = sealedPath + ".restore"
                    exec("mkdir -p " + shellQuote(vaultDir) + " && chmod 700 " + shellQuote(vaultDir))
                    writeFile(restoreTmp, restored)
                    exec("chmod 600 " + shellQuote(restoreTmp))
                    exec("mv -f " + shellQuote(restoreTmp) + " " + shellQuote(sealedPath))
                    exec("chmod 600 " + shellQuote(sealedPath))
                    setTextState("vaultPlain", opened)
                    renderVaultPlain(opened)
                    setStatus("Encrypted vault restored")
                } else {
                    setStatus("Remote vault did not authenticate")
                    alert("Krypton Vault", "The remote vault did not open with this master password. Your local vault was left unchanged.")
                }
                emit "1"
            }
            if fetched != "" { alert("Krypton Vault", fetched) }
            setStatus("No remote vault")
            emit "1"
        }
        if user == "" || token == "" {
            alert("Krypton Vault", "Add account and token before uploading the encrypted vault.")
            setStatus("Sync credentials missing")
            emit "1"
        }
        let post = "curl -fsS -X POST " + shellQuote(base + "/v1/vault") +
            " --data-urlencode " + shellQuote("user=" + user) +
            " --data-urlencode " + shellQuote("token=" + token) +
            " --data-urlencode " + shellQuote("rev=1") +
            " --data-urlencode " + shellQuote("blob@" + sealedPath) + " 2>&1"
        let posted = cleanLine(exec(post))
        if contains(posted, "\"ok\":true") {
            setStatus("Encrypted vault uploaded")
            emit "1"
        }
        alert("Krypton Vault", "The VPS was reachable, but upload failed.")
        setStatus("Upload failed")
        emit "1"
    }
    alert("Krypton Vault", "Could not reach the sync endpoint.")
    setStatus("Sync check failed")
    emit "1"
}

func onPersist(self, cmd, sender) {
    let master = fieldText("master")
    if len(master) < 12 {
        alert("Krypton Vault", "Unlock with a longer master password before saving.")
        setStatus("Save blocked")
        emit "1"
    }
    let plain = textState("vaultPlain")
    if plain == "" || vmHasItems(plain) != "1" {
        alert("Krypton Vault", "There are no vault items to save.")
        emit "1"
    }
    if sealLocalVault(master, plain) == "1" {
        setStatus("Encrypted vault saved")
        emit "1"
    }
    alert("Krypton Vault", "Encrypted save failed. Check the native crypto bridge.")
    setStatus("Save failed")
    emit "1"
}

func putLabel(win, textValue, x, y, w) {
    let lbl = label(win, textValue, area(x, y, w, 22))
    tintMuted(lbl)
    emit lbl
}

func wire(btn, key, handler) {
    doClick(btn, key, handler)
    emit "1"
}

func setupMenus(application) {
    let bar = menuBar()
    let appMenu = menu(bar, "Krypton Vault")
    menuSelector(appMenu, "Quit Krypton Vault", "q", "terminate:")
    let edit = menu(bar, "Edit")
    menuSelector(edit, "Cut", "x", "cut:")
    menuSelector(edit, "Copy", "c", "copy:")
    menuSelector(edit, "Paste", "v", "paste:")
    menuSeparator(edit)
    menuSelector(edit, "Select All", "a", "selectAll:")
    emit "1"
}

just run {
    let application = app("Krypton Vault")
    setupMenus(application)

    let win = window("Krypton Vault", 920, 760)
    minSize(win, 820, 700)
    doWindowBackground(win, vaultBg())
    doTransparentTitlebar(win)

    let headline = title(win, "Krypton Vault", area(24, 710, 260, 28))
    tint(headline)
    let status = label(win, "Locked", area(760, 710, 136, 22))
    tintMuted(status)

    putLabel(win, "Master password", 24, 666, 140)
    let master = password(win, area(166, 662, 384, 28))
    tint(master)
    doPlaceholder(master, "Unlock local vault")
    let unlockBtn = button(win, "Unlock", area(566, 662, 96, 30))
    tintButton(unlockBtn)
    let lockBtn = button(win, "Lock", area(674, 662, 86, 30))
    tintButton(lockBtn)
    let lockState = label(win, "Locked", area(774, 666, 122, 22))
    tintMuted(lockState)

    putLabel(win, "Search", 24, 624, 90)
    let search = field(win, area(166, 620, 298, 28))
    tint(search)
    doPlaceholder(search, "Search title, user, site, or note")
    let findBtn = button(win, "Find", area(478, 620, 72, 30))
    tintButton(findBtn)
    let syncBtn = button(win, "Sync", area(566, 620, 96, 30))
    tintButton(syncBtn)
    let persistBtn = button(win, "Save", area(674, 620, 86, 30))
    tintButton(persistBtn)

    putLabel(win, "VPS URL", 24, 586, 90)
    let syncUrl = field(win, area(166, 582, 300, 28))
    tint(syncUrl)
    doPlaceholder(syncUrl, "https://kry.li")

    putLabel(win, "Account", 488, 586, 90)
    let syncUser = field(win, area(582, 582, 132, 28))
    tint(syncUser)
    doPlaceholder(syncUser, "email")
    let syncToken = password(win, area(724, 582, 172, 28))
    tint(syncToken)
    doPlaceholder(syncToken, "token")

    putLabel(win, "Title", 24, 534, 90)
    let itemTitle = field(win, area(166, 530, 300, 28))
    tint(itemTitle)
    doPlaceholder(itemTitle, "GitHub")

    putLabel(win, "Username", 488, 534, 90)
    let itemUser = field(win, area(582, 530, 314, 28))
    tint(itemUser)
    doPlaceholder(itemUser, "name@example.com")

    putLabel(win, "Website", 24, 494, 90)
    let itemUrl = field(win, area(166, 490, 300, 28))
    tint(itemUrl)
    doPlaceholder(itemUrl, "https://example.com")

    putLabel(win, "Password", 488, 494, 90)
    let itemPassword = password(win, area(582, 490, 314, 28))
    tint(itemPassword)
    doPlaceholder(itemPassword, "Stored only in memory")

    putLabel(win, "Type", 24, 448, 60)
    let kindCombo = choices(win, area(86, 444, 130, 30))
    doAddChoice(kindCombo, "Login")
    doAddChoice(kindCombo, "Note")
    doChoose(kindCombo, 0)
    putLabel(win, "Notes", 250, 448, 60)
    let itemNotes = textBox(win, area(24, 340, 872, 96))

    let addButton = button(win, "Add Item", area(166, 304, 108, 32))
    tintButton(addButton)
    let copyButton = button(win, "Copy Password", area(288, 304, 132, 32))
    tintButton(copyButton)
    let copyMatchButton = button(win, "Copy Match", area(434, 304, 132, 32))
    tintButton(copyMatchButton)
    let deleteMatchButton = button(win, "Delete Match", area(580, 304, 132, 32))
    tintButton(deleteMatchButton)

    putLabel(win, "Vault", 24, 270, 90)
    let vault = textBox(win, area(24, 32, 872, 230))
    doFont(vault, mono(12))
    doNoWrap(vault)
    doTextBox(vault, "No vault items in this local session.\n")
    doTextColor(vault, vaultText())
    doBackground(vault, textBackground())

    doSet(application, "status", status)
    doSet(application, "master", master)
    doSet(application, "lockState", lockState)
    doSet(application, "search", search)
    doSet(application, "syncUrl", syncUrl)
    doSet(application, "syncUser", syncUser)
    doSet(application, "syncToken", syncToken)
    doSet(application, "itemTitle", itemTitle)
    doSet(application, "itemUser", itemUser)
    doSet(application, "itemUrl", itemUrl)
    doSet(application, "itemPassword", itemPassword)
    doSet(application, "kind", kindCombo)
    doSet(application, "itemNotes", itemNotes)
    doSet(application, "vault", vault)
    setTextState("itemCount", "0")
    setTextState("vaultPlain", "")
    doSet(application, "findButton", findBtn)
    doSet(application, "addButton", addButton)
    doSet(application, "copyButton", copyButton)
    doSet(application, "copyMatchButton", copyMatchButton)
    doSet(application, "deleteMatchButton", deleteMatchButton)
    doSet(application, "lockButton", lockBtn)

    doDisable(addButton)
    doDisable(copyButton)
    doDisable(copyMatchButton)
    doDisable(deleteMatchButton)
    doDisable(findBtn)
    doDisable(lockBtn)

    wire(unlockBtn, "vault.unlock", funcptr(onUnlock))
    wire(lockBtn, "vault.lock", funcptr(onLock))
    wire(addButton, "vault.add", funcptr(onAdd))
    wire(copyButton, "vault.copy", funcptr(onCopyPassword))
    wire(copyMatchButton, "vault.copyMatch", funcptr(onCopyMatch))
    wire(deleteMatchButton, "vault.deleteMatch", funcptr(onDeleteMatch))
    wire(findBtn, "vault.find", funcptr(onFind))
    wire(syncBtn, "vault.sync", funcptr(onSync))
    wire(persistBtn, "vault.persist", funcptr(onPersist))

    let setupWin = window("Set Up Krypton Vault", 620, 520)
    minSize(setupWin, 560, 460)
    doWindowBackground(setupWin, vaultBg())
    doTransparentTitlebar(setupWin)

    let setupTitle = title(setupWin, "Set up Krypton Vault", area(40, 430, 540, 34))
    tint(setupTitle)
    let setupIntro = label(setupWin,
        "Create one master password to protect your encrypted vault.",
        area(40, 390, 540, 24))
    tintMuted(setupIntro)
    let setupHint = label(setupWin,
        "Krypton Vault cannot recover this password for you.",
        area(40, 362, 540, 24))
    tintMuted(setupHint)

    let setupMasterLabel = label(setupWin, "Master password", area(40, 300, 160, 24))
    tintMuted(setupMasterLabel)
    let setupMaster = password(setupWin, area(40, 264, 540, 30))
    tint(setupMaster)
    doPlaceholder(setupMaster, "At least 12 characters")

    let setupConfirmLabel = label(setupWin, "Confirm password", area(40, 210, 160, 24))
    tintMuted(setupConfirmLabel)
    let setupConfirm = password(setupWin, area(40, 174, 540, 30))
    tint(setupConfirm)
    doPlaceholder(setupConfirm, "Enter it again")

    let setupCreate = button(setupWin, "Create Vault", area(40, 104, 160, 34))
    tintButton(setupCreate)
    let setupStatus = label(setupWin, "Your vault will be encrypted on this Mac.", area(40, 58, 540, 24))
    tintMuted(setupStatus)

    doSet(application, "mainWin", win)
    doSet(application, "setupWin", setupWin)
    doSet(application, "setupMaster", setupMaster)
    doSet(application, "setupConfirm", setupConfirm)
    doSet(application, "setupStatus", setupStatus)
    wire(setupCreate, "vault.create", funcptr(onCreateVault))

    if readFile(localVaultPath()) == "" {
        doShow(setupWin)
    } else {
        doShow(win)
    }
    doRun()
}
