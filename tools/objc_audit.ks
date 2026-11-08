// tools/objc_audit.ks -- macOS Objective-C ABI audit and binary inspector.
//
// Krypton apps call AppKit by sending selectors as plain strings. Nothing
// type-checks those strings, so a typo or a wrong receiver shows up only as
// a crash at runtime (or a no-op). This tool closes that gap:
//
//   scan  Extract selector-like strings from a Mach-O binary, resolve each
//         one against the ObjC classes the binary references, and print the
//         method type encoding. Unresolved argument selectors are reported.
//   info  Print the binary's load commands, dylibs, rpaths, code signature,
//         entitlements, imports, and selector inventory.
//   dump  Probe named classes for a caller-supplied selector list.
//
// Only documented runtime entry points that the Krypton macOS backend already
// allowlists are used (objc_lookUpClass, sel_registerName, objc_msgSend).
// Method signatures come from NSMethodSignature, so no new C bindings are
// needed for this slice.

import "k:objc"

func oaQuote(s) {
    emit "'" + replace(s, "'", "'\\''") + "'"
}

func oaHasColon(s) {
    if indexOf(s, ":") >= 0 { emit 1 }
    emit 0
}

func oaFileExists(p) {
    if shellRun("test -f " + oaQuote(p)) == "0" { emit 1 }
    emit 0
}

// Newline-delimited set. Small inputs, so a containment check is plenty.
func oaAddUnique(list, item) {
    if item == "" { emit list }
    if contains("\n" + list + "\n", "\n" + item + "\n") == 1 { emit list }
    emit list + item + "\n"
}

func oaCountNonEmpty(list) {
    let n = lineCount(list)
    let c = 0
    let i = 0
    while i < n {
        if len(trim(getLine(list, i))) > 0 { c += 1 }
        i += 1
    }
    emit c
}

func oaListHas(list, item) {
    if contains("\n" + list + "\n", "\n" + item + "\n") == 1 { emit 1 }
    emit 0
}

func oaCommaLines(s) {
    emit replace(s, ",", "\n")
}

// Full method encoding, e.g. v@:@ or @@:{CGRect=...}QQB.
func oaEncoding(sig) {
    if sig == 0 { emit "?" }
    let ret = msg(sig, "methodReturnType")
    let n = msg(sig, "numberOfArguments")
    let out = ret
    let i = 0
    while i < n {
        out = out + msg_1(sig, "getArgumentTypeAtIndex:", i)
        i += 1
    }
    emit out
}

func oaProbeOne(c, name, token) {
    let s = sel(token)
    if msg_1(c, "instancesRespondToSelector:", s) != 0 {
        let sig = msg_1(c, "instanceMethodSignatureForSelector:", s)
        print(name + "  -" + token + "  " + oaEncoding(sig))
    }
    if msg_1(c, "respondsToSelector:", s) != 0 {
        let sig = msg_1(c, "methodSignatureForSelector:", s)
        print(name + "  +" + token + "  " + oaEncoding(sig))
    }
    emit "1"
}

// Classes the binary names as strings, plus any _OBJC_CLASS_$_ references and
// caller-supplied names. objc_lookUpClass filters out words that aren't real
// classes and confirms which frameworks are already loaded.
//
// Class clusters (NSAttributedString, etc.) return false from
// instancesRespondToSelector: on the abstract class, so the concrete private
// classes are included explicitly. NSTextStorage/NSTextContainer/CALayer are
// common inferred receivers that rarely appear in a binary's strings.
func oaClassList(bin, extra) {
    let out = ""

    let names = exec("strings -a " + oaQuote(bin) + " | grep -E " + oaQuote("^[A-Z][A-Za-z0-9_]*$"))
    let n = lineCount(names)
    let i = 0
    while i < n {
        let name = trim(getLine(names, i))
        if name != "" && objc_lookUpClass(name) != 0 { out = oaAddUnique(out, name) }
        i += 1
    }

    let prefix = "_OBJC_CLASS_$_"
    let refs = exec("strings -a " + oaQuote(bin) + " | grep " + oaQuote(prefix))
    n = lineCount(refs)
    i = 0
    while i < n {
        let line = trim(getLine(refs, i))
        if startsWith(line, prefix) == 1 {
            let name = substring(line, len(prefix), len(line))
            if objc_lookUpClass(name) != 0 { out = oaAddUnique(out, name) }
        }
        i += 1
    }

    let supplemental = "NSConcreteAttributedString\n" +
        "NSConcreteMutableAttributedString\n" +
        "NSTextStorage\n" +
        "NSTextContainer\n" +
        "NSLayoutManager\n" +
        "CALayer\n" +
        "NSColor\n" +
        "NSFont\n" +
        "NSImage\n" +
        "NSWorkspace\n" +
        "NSPasteboard\n" +
        "NSAlert\n" +
        "NSURL\n" +
        "NSData\n" +
        "NSDate\n" +
        "NSNumber\n" +
        "NSValue\n" +
        "NSDictionary\n" +
        "NSMutableDictionary\n" +
        "NSArray\n" +
        "NSMutableArray\n" +
        "NSSet\n" +
        "NSMutableSet\n" +
        "NSIndexSet\n" +
        "NSMutableIndexSet\n" +
        "NSGraphicsContext\n" +
        "NSGradient\n" +
        "NSBitmapImageRep\n" +
        "NSSecureTextField\n" +
        "NSTableColumn\n" +
        "NSSplitView\n" +
        "NSProgressIndicator\n"
    let sn = lineCount(supplemental)
    i = 0
    while i < sn {
        let name = trim(getLine(supplemental, i))
        if name != "" && objc_lookUpClass(name) != 0 { out = oaAddUnique(out, name) }
        i += 1
    }

    let extraLines = oaCommaLines(extra)
    n = lineCount(extraLines)
    i = 0
    while i < n {
        let name = trim(getLine(extraLines, i))
        if name != "" && objc_lookUpClass(name) != 0 { out = oaAddUnique(out, name) }
        i += 1
    }

    emit out
}

// Argument selectors (ending in ':') plus, with includeBare, bare identifiers
// that might be no-argument methods. Bare identifiers are only reported if a
// class actually implements them, so ordinary UI text drops out.
func oaSelectorList(bin, includeBare) {
    let out = ""

    let colon = exec("strings -a " + oaQuote(bin) + " | grep -E " + oaQuote("^[A-Za-z][A-Za-z0-9_]*(:[A-Za-z0-9_]+)*:$"))
    let n = lineCount(colon)
    let i = 0
    while i < n {
        let t = trim(getLine(colon, i))
        if t != "" { out = oaAddUnique(out, t) }
        i += 1
    }

    if includeBare == 1 {
        let ids = exec("strings -a " + oaQuote(bin) + " | grep -E " + oaQuote("^[A-Za-z][A-Za-z0-9_]*$"))
        n = lineCount(ids)
        i = 0
        while i < n {
            let t = trim(getLine(ids, i))
            if t != "" { out = oaAddUnique(out, t) }
            i += 1
        }
    }

    emit out
}

func oaScan(bin, extra, strict, includeBare, allow, quiet) {
    let classes = oaClassList(bin, extra)
    let selectors = oaSelectorList(bin, includeBare)
    let nClasses = oaCountNonEmpty(classes)
    let nSelectors = oaCountNonEmpty(selectors)

    if nClasses == 0 {
        printErr("objc-audit: no loaded ObjC classes referenced by " + bin)
        emit "1"
    }

    let records = ""
    let seen = ""
    let resolved = ""
    let unresolved = ""
    let allowed = 0

    let nSel = lineCount(selectors)
    let si = 0
    while si < nSel {
        let token = trim(getLine(selectors, si))
        if token != "" {
            let s = sel(token)
            let matched = 0
            let nCls = lineCount(classes)
            let ci = 0
            while ci < nCls {
                let name = trim(getLine(classes, ci))
                if name != "" {
                    let c = objc_lookUpClass(name)
                    if c != 0 {
                        if msg_1(c, "instancesRespondToSelector:", s) != 0 {
                            let enc = oaEncoding(msg_1(c, "instanceMethodSignatureForSelector:", s))
                            let key = "-\t" + token + "\t" + enc
                            if oaListHas(seen, key) == 0 {
                                seen = oaAddUnique(seen, key)
                                records = oaAddUnique(records, name + "  -" + token + "  " + enc)
                            }
                            matched = 1
                        }
                        if msg_1(c, "respondsToSelector:", s) != 0 {
                            let enc = oaEncoding(msg_1(c, "methodSignatureForSelector:", s))
                            let key = "+\t" + token + "\t" + enc
                            if oaListHas(seen, key) == 0 {
                                seen = oaAddUnique(seen, key)
                                records = oaAddUnique(records, name + "  +" + token + "  " + enc)
                            }
                            matched = 1
                        }
                    }
                }
                ci += 1
            }
            if matched == 1 {
                resolved = oaAddUnique(resolved, token)
            } else if oaHasColon(token) == 1 {
                if oaListHas(allow, token) == 1 {
                    allowed += 1
                } else {
                    unresolved = oaAddUnique(unresolved, token)
                }
            }
        }
        si += 1
    }

    if quiet == 0 {
        let nRec = lineCount(records)
        let ri = 0
        while ri < nRec {
            let line = getLine(records, ri)
            if len(line) > 0 { print(line) }
            ri += 1
        }
        if oaCountNonEmpty(unresolved) > 0 { print("") }
    }

    let nUn = oaCountNonEmpty(unresolved)
    if nUn > 0 {
        print("unresolved selectors:")
        let nU = lineCount(unresolved)
        let ui = 0
        while ui < nU {
            let line = trim(getLine(unresolved, ui))
            if line != "" { print("  warning: no referenced class implements " + line) }
            ui += 1
        }
        print("")
    }

    print("classes=" + nClasses + " selectors=" + nSelectors +
        " resolved=" + oaCountNonEmpty(resolved) +
        " signatures=" + oaCountNonEmpty(records) +
        " allowed=" + allowed +
        " unresolved=" + nUn)

    if strict == 1 && nUn > 0 { emit "1" }
    emit "0"
}

func oaInfo(bin) {
    print("== file ==")
    print(trim(exec("file " + oaQuote(bin))))
    print("")
    print("== linked libraries ==")
    print(trim(exec("otool -L " + oaQuote(bin))))
    print("")
    print("== rpaths ==")
    let rp = trim(exec("otool -l " + oaQuote(bin) + " | grep -A 2 LC_RPATH"))
    if rp == "" { print("(none)") } else { print(rp) }
    print("")
    print("== code signature ==")
    print(trim(exec("codesign -dv --verbose=4 " + oaQuote(bin) + " 2>&1")))
    print("")
    print("== entitlements ==")
    let ent = trim(exec("codesign -d --entitlements - " + oaQuote(bin) + " 2>&1"))
    if ent == "" { print("(none)") } else { print(ent) }
    print("")
    print("== imported symbols ==")
    print(trim(exec("nm -gj " + oaQuote(bin))))
    print("")
    print("== objc argument selectors ==")
    let sels = exec("strings -a " + oaQuote(bin) + " | grep -E " + oaQuote("^[A-Za-z][A-Za-z0-9_]*(:[A-Za-z0-9_]+)*:$"))
    if trim(sels) == "" { print("(none)") } else { print(trim(sels)) }
    emit "1"
}

func oaDump(classes, selectors) {
    let nC = lineCount(classes)
    let i = 0
    while i < nC {
        let name = trim(getLine(classes, i))
        if name != "" {
            let c = objc_lookUpClass(name)
            if c == 0 {
                print(name + "  (not loaded)")
            } else {
                let nS = lineCount(selectors)
                let j = 0
                while j < nS {
                    let token = trim(getLine(selectors, j))
                    if token != "" { oaProbeOne(c, name, token) }
                    j += 1
                }
            }
        }
        i += 1
    }
    emit "1"
}

func oaUsage() {
    print("usage:")
    print("  objc-audit scan <binary> [--classes A,B] [--allow sel1,sel2]")
    print("                  [--all] [--quiet] [--strict]")
    print("  objc-audit info <binary>")
    print("  objc-audit dump --class NAME --selectors sel1,sel2 [--class NAME ...]")
    emit "1"
}

just run {
    let argc = argCount()
    if argc < 1 {
        oaUsage()
        exit(1)
    }

    let cmd = arg(0)

    if cmd == "scan" {
        let bin = ""
        let classesArg = ""
        let allowArg = ""
        let strict = 0
        let includeBare = 0
        let quiet = 0
        let i = 1
        while i < argc {
            let a = arg(i)
            if a == "--classes" {
                i += 1
                if i < argc { classesArg = arg(i) }
            } else if a == "--allow" {
                i += 1
                if i < argc { allowArg = arg(i) }
            } else if a == "--all" {
                includeBare = 1
            } else if a == "--quiet" {
                quiet = 1
            } else if a == "--strict" {
                strict = 1
            } else if bin == "" {
                bin = a
            }
            i += 1
        }
        if bin == "" {
            oaUsage()
            exit(1)
        }
        if oaFileExists(bin) != 1 {
            printErr("objc-audit: no such file: " + bin)
            exit(1)
        }
        let allowLines = ""
        let allowRaw = oaCommaLines(allowArg)
        let an = lineCount(allowRaw)
        let ai = 0
        while ai < an {
            let t = trim(getLine(allowRaw, ai))
            if t != "" { allowLines = oaAddUnique(allowLines, t) }
            ai += 1
        }
        exit(toInt(oaScan(bin, classesArg, strict, includeBare, allowLines, quiet)))
    }

    if cmd == "info" {
        if argc < 2 {
            oaUsage()
            exit(1)
        }
        let bin = arg(1)
        if oaFileExists(bin) != 1 {
            printErr("objc-audit: no such file: " + bin)
            exit(1)
        }
        oaInfo(bin)
        exit(0)
    }

    if cmd == "dump" {
        let classes = ""
        let selectors = ""
        let i = 1
        while i < argc {
            let a = arg(i)
            if a == "--class" {
                i += 1
                if i < argc { classes = oaAddUnique(classes, arg(i)) }
            } else if a == "--selectors" {
                i += 1
                if i < argc {
                    let more = oaCommaLines(arg(i))
                    let n = lineCount(more)
                    let j = 0
                    while j < n {
                        let t = trim(getLine(more, j))
                        if t != "" { selectors = oaAddUnique(selectors, t) }
                        j += 1
                    }
                }
            }
            i += 1
        }
        if classes == "" || selectors == "" {
            oaUsage()
            exit(1)
        }
        oaDump(classes, selectors)
        exit(0)
    }

    oaUsage()
    exit(1)
}
