#!/usr/bin/env kr
// krypton_inspector.ks -- native macOS inspector for Krypton app bundles and
// Mach-O binaries.
//
// The audit engine is dist/objc-audit. The app bundles it as an auxiliary
// executable and renders its report, so the CLI and the GUI never disagree.
// This first slice is metadata/ABI/binary inspection only: no disassembly,
// no debugger, no decompiler.

import "k:okui"
import "k:objc"

func dq() { emit fromCharCode(34) }
func bs() { emit fromCharCode(92) }

func appH() { emit sharedApp() }

// Objective-C associated objects only retain NSString values safely.
func setTextState(key, value) {
    doSet(appH(), key, nsString(value))
    emit "1"
}

func textState(key) {
    let boxed = get(appH(), key)
    if boxed == 0 { emit "" }
    emit msg(boxed, "UTF8String")
}

func inspQuote(s) {
    emit dq() + replace(s, dq(), bs() + dq()) + dq()
}

func cleanLine(s) {
    let t = trim(s)
    if t == "0" { emit "" }
    emit t
}

func isDarkMode() {
    let mode = cleanLine(exec("defaults read -g AppleInterfaceStyle 2>/dev/null"))
    if contains(mode, "Dark") { emit 1 }
    emit 0
}

func inspBg() {
    if isDarkMode() == 1 { emit rgb(28, 32, 38) }
    emit windowBackground()
}

func inspText() {
    if isDarkMode() == 1 { emit rgb(230, 233, 236) }
    emit textColor()
}

func inspMuted() {
    if isDarkMode() == 1 { emit rgb(156, 165, 174) }
    emit secondaryTextColor()
}

func tint(view) {
    doTextColor(view, inspText())
    emit view
}

func tintMuted(view) {
    doTextColor(view, inspMuted())
    emit view
}

func tintButton(view) {
    doButtonTextColor(view, inspText())
    emit view
}

func status(textValue) {
    doText(get(appH(), "status"), textValue)
    emit "1"
}

func target() {
    emit trim(text(get(appH(), "target")))
}

func toolPath() {
    let bundled = bundledExecutable("objc-audit")
    if bundled != "" { emit bundled }
    emit "dist/objc-audit"
}

func toolReady() {
    if shellRun("test -x " + inspQuote(toolPath())) == "0" { emit 1 }
    emit 0
}

func audit(command, path) {
    let tool = toolPath()
    let cmd = inspQuote(tool) + " " + command + " " + inspQuote(path) + " 2>&1"
    emit exec(cmd)
}

func setReport(body) {
    let view = get(appH(), "report")
    if body == "" { body = "(no output)" }
    doTextBox(view, body)
    doTextRangeColor(view, inspText(), 0, len(body))
    setTextState("reportText", body)
    emit "1"
}

func runCommand(command, label) {
    let path = target()
    if path == "" {
        setReport("Choose an .app bundle or a Mach-O binary first.")
        status(label + ": no target")
        emit "1"
    }
    if toolReady() != 1 {
        setReport("objc-audit was not found.\n\nBuild it with:\n  scripts/build-objc-audit.sh")
        status(label + ": audit tool missing")
        emit "1"
    }
    status(label + "…")
    setReport(audit(command, path))
    status(label + " complete")
    emit "1"
}

func onInspect(self, cmd, sender) { runCommand("report", "Overview") }
func onSelectors(self, cmd, sender) { runCommand("scan", "Selectors") }
func onSecurity(self, cmd, sender) { runCommand("security", "Security") }
func onStrings(self, cmd, sender) { runCommand("strings", "Strings") }
func onBundle(self, cmd, sender) { runCommand("bundle", "Bundle") }

func onChooseApp(self, cmd, sender) {
    let path = chooseFolder("Choose an app bundle")
    if path != "" {
        doText(get(appH(), "target"), path)
        status("Target set")
    }
    emit "1"
}

func onChooseBinary(self, cmd, sender) {
    let path = chooseFile("Choose a Mach-O binary")
    if path != "" {
        doText(get(appH(), "target"), path)
        status("Target set")
    }
    emit "1"
}

func onCopy(self, cmd, sender) {
    doCopyText(textState("reportText"))
    status("Report copied")
    emit "1"
}

func putLabel(win, textValue, x, y, w) {
    let lbl = label(win, textValue, area(x, y, w, 22))
    tintMuted(lbl)
    emit lbl
}

func setupMenus(application) {
    let bar = menuBar()
    let edit = menu(bar, "Edit")
    menuSelector(edit, "Cut", "x", "cut:")
    menuSelector(edit, "Copy", "c", "copy:")
    menuSelector(edit, "Paste", "v", "paste:")
    menuSeparator(edit)
    menuSelector(edit, "Select All", "a", "selectAll:")
    emit "1"
}

just run {
    let application = app("Krypton Inspector")
    setupMenus(application)

    let win = window("Krypton Inspector", 1040, 780)
    minSize(win, 900, 680)
    doWindowBackground(win, inspBg())
    doTransparentTitlebar(win)

    let headline = title(win, "Krypton Inspector", area(24, 728, 300, 28))
    tint(headline)
    let statusLabel = label(win, "Choose a target", area(800, 728, 216, 22))
    tintMuted(statusLabel)

    putLabel(win, "Target", 24, 690, 60)
    let targetField = field(win, area(90, 686, 620, 28))
    tint(targetField)
    doPlaceholder(targetField, "/path/to/App.app or /path/to/binary")

    let appBtn = button(win, "App…", area(722, 684, 78, 30))
    tintButton(appBtn)
    let binBtn = button(win, "Binary…", area(808, 684, 92, 30))
    tintButton(binBtn)
    let inspectBtn = button(win, "Inspect", area(908, 684, 108, 30))
    tintButton(inspectBtn)

    let overviewBtn = button(win, "Overview", area(24, 642, 104, 30))
    tintButton(overviewBtn)
    let selectorsBtn = button(win, "Selectors", area(136, 642, 104, 30))
    tintButton(selectorsBtn)
    let securityBtn = button(win, "Security", area(248, 642, 104, 30))
    tintButton(securityBtn)
    let stringsBtn = button(win, "Strings", area(360, 642, 104, 30))
    tintButton(stringsBtn)
    let bundleBtn = button(win, "Bundle", area(472, 642, 104, 30))
    tintButton(bundleBtn)
    let copyBtn = button(win, "Copy Report", area(900, 642, 116, 30))
    tintButton(copyBtn)

    let report = textBox(win, area(24, 24, 992, 598))
    doFont(report, mono(12))
    doNoWrap(report)
    doTextColor(report, inspText())
    doBackground(report, textBackground())
    doTextBox(report, "Choose an .app bundle or Mach-O binary, then press Inspect.\n\n" +
        "Overview runs the full report. Selectors checks every selector-like\n" +
        "string against the runtime and prints its ABI encoding. Security shows\n" +
        "signature, entitlements, Gatekeeper, hardened runtime, and notarization.\n" +
        "Strings groups URLs, paths, versions, and selectors.")

    doSet(application, "status", statusLabel)
    doSet(application, "target", targetField)
    doSet(application, "report", report)
    setTextState("reportText", "")

    doClick(inspectBtn, "inspector.report", funcptr(onInspect))
    doClick(overviewBtn, "inspector.overview", funcptr(onInspect))
    doClick(selectorsBtn, "inspector.selectors", funcptr(onSelectors))
    doClick(securityBtn, "inspector.security", funcptr(onSecurity))
    doClick(stringsBtn, "inspector.strings", funcptr(onStrings))
    doClick(bundleBtn, "inspector.bundle", funcptr(onBundle))
    doClick(appBtn, "inspector.chooseApp", funcptr(onChooseApp))
    doClick(binBtn, "inspector.chooseBinary", funcptr(onChooseBinary))
    doClick(copyBtn, "inspector.copy", funcptr(onCopy))

    doShow(win)
    doRun()
}
