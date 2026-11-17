#!/usr/bin/env python3
"""scripts/validation/pvl_reading_table.py -- the reading table of the verification-line checker (CON-423 r8): how a
person reads a character, derived from ICU (Unicode UTS #39 confusable skeletons, NFKD, case folding and the
Default_Ignorable_Code_Point property) instead of a hand-kept list.

Usage:
  python3 -I scripts/validation/pvl_reading_table.py --check     (exit 0 when the embedded table equals a fresh build)
  python3 -I scripts/validation/pvl_reading_table.py --print     (prints the table text a fresh build gives)
  python3 -I scripts/validation/pvl_reading_table.py --write     (rewrites the table embedded in the checker)
The checker (scripts/validation/check_provisional_verification_lines.py) does not use ICU at run time: it carries the
table built here as the string _READING_TABLE between the markers `# BEGIN READING TABLE` and `# END READING TABLE`,
with its sha256 READING_TABLE_SHA256, and refuses
to run (BLIND) when the text and the sum differ. This file is the generator (section 11.4.77) and the reference
implementation the test harnesses compare the checker against (tests/release/pvl_blockstate.py reads labels with
fold() below, live from ICU; tests/release/pvl_inventory.py compares every code point).

THE READING of one code point C (exactly what fold() computes; the table holds the result for every C it changes):
  1. C is DROPPED (read as nothing) when it is Default_Ignorable_Code_Point, or its general category is Mn, Mc, Me
     (marks), Cf (format), Cs, Co, Cn (surrogate, private use, unassigned), or Cc and not White_Space.
  2. Else C is decomposed with NFKD; each part X that is not dropped is read as:
       X itself in lower case when X is ASCII (an ASCII character is read as itself, case-insensitively);
       else fold(skeleton(fold(X))) when that is ASCII (fold = full case folding, skeleton = UTS #39 confusable
       skeleton), else fold(skeleton(X)) when that is ASCII; else X itself.
  3. The reading of C is the parts joined. When it holds no ASCII character and is not empty, C is read as itself
     (the table only says how a character can be read as ASCII; a character no ASCII reading exists for stands for
     itself).
Table lines (tab separated): `D<TAB>FIRST<TAB>LAST` a dropped range, `R<TAB>CP<TAB>HEX...` a reading (code points in
hex). The header names the ICU and Unicode versions; another ICU gives another table (--check then fails: rebuild,
review the difference, update the checker's sum).
Exit: 0 ok, 1 --check differs, 2 ICU cannot be loaded, 64 usage. Section 11.4.289(C)(2): gate-logic.
"""
import ctypes
import ctypes.util
import hashlib
import html
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKER = os.path.join(HERE, "check_provisional_verification_lines.py")
BEGIN = "# BEGIN READING TABLE\n"
END = "# END READING TABLE\n"
OPEN = '_READING_TABLE = """\\\n'
CLOSE = '"""\n'
_DROP_GC = (0, 6, 7, 8, 16, 17, 18)  # Cn, Mn, Me, Mc, Cf, Co, Cs (ICU UCharCategory)
_CC = 15
_DICP = 5
_WHITE = 31


class ICU:
    """The ICU functions the reading needs, loaded with ctypes (no compiler, no Python package)."""

    def __init__(self):
        uc_name = ctypes.util.find_library("icuuc")
        i18n_name = ctypes.util.find_library("icui18n")
        if not uc_name or not i18n_name:
            raise OSError("ICU (libicuuc, libicui18n) not found")
        self.uc = ctypes.CDLL(uc_name)
        self.i18n = ctypes.CDLL(i18n_name)
        m = re.search(r"\.so\.(\d+)", uc_name)
        suffixes = [""] + (["_" + m.group(1)] if m else [])
        self._suf = None
        for s in suffixes:
            if hasattr(self.uc, "u_charType" + s):
                self._suf = s
        if self._suf is None:
            raise OSError("ICU symbol u_charType not found in %s" % uc_name)
        f = self._fn
        self.char_type = f(self.uc, "u_charType", ctypes.c_int8, [ctypes.c_int32])
        self.has_prop = f(self.uc, "u_hasBinaryProperty", ctypes.c_int8, [ctypes.c_int32, ctypes.c_int])
        err = ctypes.c_int(0)
        get_nfkd = f(self.uc, "unorm2_getNFKDInstance", ctypes.c_void_p, [ctypes.POINTER(ctypes.c_int)])
        self._nfkd = get_nfkd(ctypes.byref(err))
        self._check(err, "unorm2_getNFKDInstance")
        self._normalize = f(self.uc, "unorm2_normalize", ctypes.c_int32,
                            [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int32, ctypes.c_char_p, ctypes.c_int32,
                             ctypes.POINTER(ctypes.c_int)])
        self._fold = f(self.uc, "u_strFoldCase", ctypes.c_int32,
                       [ctypes.c_char_p, ctypes.c_int32, ctypes.c_char_p, ctypes.c_int32, ctypes.c_uint32,
                        ctypes.POINTER(ctypes.c_int)])
        sp_open = f(self.i18n, "uspoof_open", ctypes.c_void_p, [ctypes.POINTER(ctypes.c_int)])
        self._sc = sp_open(ctypes.byref(err))
        self._check(err, "uspoof_open")
        self._skel = f(self.i18n, "uspoof_getSkeleton", ctypes.c_int32,
                       [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_int32, ctypes.c_char_p,
                        ctypes.c_int32, ctypes.POINTER(ctypes.c_int)])
        ver = (ctypes.c_uint8 * 4)()
        f(self.uc, "u_getVersion", None, [ctypes.c_void_p])(ver)
        self.icu_version = ".".join(str(x) for x in ver[:2])
        f(self.uc, "u_getUnicodeVersion", None, [ctypes.c_void_p])(ver)
        self.unicode_version = ".".join(str(x) for x in ver[:2])
        self._cache = {}

    def _fn(self, lib, name, res, args):
        fn = getattr(lib, name + self._suf)
        fn.restype = res
        fn.argtypes = args
        return fn

    @staticmethod
    def _check(err, what):
        if err.value > 0:
            raise OSError("%s failed (ICU error %d)" % (what, err.value))

    def _call16(self, fn, *pre, s, post=()):
        src = s.encode("utf-16-le")
        cap = 4 * len(s) + 64
        buf = ctypes.create_string_buffer(2 * cap)
        err = ctypes.c_int(0)
        n = fn(*pre, src, len(src) // 2, buf, cap, *post, ctypes.byref(err)) if not pre or pre[0] is not None else 0
        self._check(err, getattr(fn, "__name__", "ICU call"))
        return buf.raw[:2 * n].decode("utf-16-le", "surrogatepass")

    def nfkd(self, s):
        src = s.encode("utf-16-le")
        cap = 32 * len(s) + 64
        buf = ctypes.create_string_buffer(2 * cap)
        err = ctypes.c_int(0)
        n = self._normalize(self._nfkd, src, len(src) // 2, buf, cap, ctypes.byref(err))
        self._check(err, "unorm2_normalize")
        return buf.raw[:2 * n].decode("utf-16-le", "surrogatepass")

    def fold(self, s):
        src = s.encode("utf-16-le")
        cap = 4 * len(s) + 64
        buf = ctypes.create_string_buffer(2 * cap)
        err = ctypes.c_int(0)
        n = self._fold(buf, cap, src, len(src) // 2, 0, ctypes.byref(err))
        self._check(err, "u_strFoldCase")
        return buf.raw[:2 * n].decode("utf-16-le", "surrogatepass")

    def skeleton(self, s):
        src = s.encode("utf-16-le")
        cap = 32 * len(s) + 64
        buf = ctypes.create_string_buffer(2 * cap)
        err = ctypes.c_int(0)
        n = self._skel(self._sc, 0, src, len(src) // 2, buf, cap, ctypes.byref(err))
        self._check(err, "uspoof_getSkeleton")
        return buf.raw[:2 * n].decode("utf-16-le", "surrogatepass")

    def dropped(self, cp):
        gc = self.char_type(cp)
        if gc in _DROP_GC or self.has_prop(cp, _DICP):
            return True
        return gc == _CC and not self.has_prop(cp, _WHITE)

    def _part(self, x):
        if ord(x) < 128:
            return x.lower()
        for cand in (self.fold(self.skeleton(self.fold(x))), self.fold(self.skeleton(x))):
            if cand and all(ord(y) < 128 for y in cand):
                return cand.lower()
        return x

    def reading(self, cp):
        """The reading of the code point CP (see THE READING)."""
        r = self._cache.get(cp)
        if r is None:
            if self.dropped(cp):
                r = ""
            else:
                r = "".join(self._part(x) for x in self.nfkd(chr(cp)) if not self.dropped(ord(x)))
                if r and not any(ord(y) < 128 for y in r):
                    r = chr(cp)
            self._cache[cp] = r
        return r


def code_points():
    return (cp for cp in range(0x110000) if not 0xD800 <= cp <= 0xDFFF)


def build(icu):
    """The table text (header, dropped ranges, readings) of a fresh build."""
    drops, reads = [], []
    start = None
    for cp in range(0x110001):
        d = cp <= 0x10FFFF and (0xD800 <= cp <= 0xDFFF or icu.dropped(cp))
        if d and start is None:
            start = cp
        elif not d and start is not None:
            drops.append((start, cp - 1))
            start = None
        if cp <= 0x10FFFF and not d and not 0xD800 <= cp <= 0xDFFF:
            r = icu.reading(cp)
            if r != chr(cp):
                reads.append((cp, r))
    out = ["# pvl reading table: icu %s unicode %s; built by scripts/validation/pvl_reading_table.py; do not edit\n"
           % (icu.icu_version, icu.unicode_version)]
    out += ["D\t%04X\t%04X\n" % r for r in drops]
    out += ["R\t%04X\t%s\n" % (cp, " ".join("%04X" % ord(y) for y in r)) for cp, r in reads]
    return "".join(out)


def fold(icu, s):
    """S read as a person reads it (character references decoded, then THE READING of every character), live from ICU;
    the checker's fold() must give the same string for every input."""
    return "".join(icu.reading(ord(c)) if not 0xD800 <= ord(c) <= 0xDFFF else "" for c in html.unescape(s))


def embedded(path=CHECKER):
    """(table text, sum) embedded in the checker, or (None, None)."""
    src = open(path, encoding="utf-8").read()
    i, j = src.find(BEGIN), src.find(END)
    m = re.search(r'^READING_TABLE_SHA256 = "([0-9a-f]{64})"$', src, re.M)
    if i < 0 or j < i or not src[i + len(BEGIN):j].startswith(OPEN) or not src[:j].endswith(CLOSE):
        return None, m.group(1) if m else None
    return src[i + len(BEGIN) + len(OPEN):j - len(CLOSE)], m.group(1) if m else None


def main(argv):
    if len(argv) != 2 or argv[1] not in ("--check", "--print", "--write"):
        sys.stderr.write("usage: pvl_reading_table.py --check|--print|--write\n")
        return 64
    try:
        icu = ICU()
    except OSError as exc:
        print("READING-TABLE-BLIND ICU cannot be loaded: %s" % exc)
        return 2
    text = build(icu)
    h = hashlib.sha256(text.encode("utf-8")).hexdigest()
    nd = sum(1 for ln in text.splitlines() if ln.startswith("D\t"))
    nr = sum(1 for ln in text.splitlines() if ln.startswith("R\t"))
    if argv[1] == "--print":
        sys.stdout.write(text)
        return 0
    if argv[1] == "--write":
        src = open(CHECKER, encoding="utf-8").read()
        i, j = src.find(BEGIN), src.find(END)
        if i < 0 or j < i:
            print("READING-TABLE-FAIL the checker has no table markers")
            return 1
        src = src[:i + len(BEGIN)] + OPEN + text + CLOSE + src[j:]
        src = re.sub(r'^READING_TABLE_SHA256 = "[0-9a-f]*"$', 'READING_TABLE_SHA256 = "%s"' % h, src, count=1,
                     flags=re.M)
        with open(CHECKER, "w", encoding="utf-8") as fh:
            fh.write(src)
    have, hsum = embedded()
    ok = have == text and hsum == h
    print("READING-TABLE %s sha256=%s drop_ranges=%d readings=%d icu=%s unicode=%s" % (
        "OK" if ok else "DIFFERS", h, nd, nr, icu.icu_version, icu.unicode_version))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
