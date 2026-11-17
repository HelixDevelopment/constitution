#!/usr/bin/env python3
"""Generate the per-character UTS #39 confusable prototype table from the host ICU (libicui18n, uspoof_getSkeletonUTF8).
Output TSV: hex code point, TAB, the skeleton of that single character as space-separated hex code points; only
characters whose skeleton differs from their NFD. Usage: gen_confusables.py <icu-major> > table.tsv"""
import ctypes, sys, unicodedata
def init(v):
  global sc, sk
  lib = ctypes.CDLL('libicui18n.so.%s' % v)
  op = getattr(lib, 'uspoof_open_%s' % v); op.restype = ctypes.c_void_p; op.argtypes = [ctypes.POINTER(ctypes.c_int)]
  sk = getattr(lib, 'uspoof_getSkeletonUTF8_%s' % v); sk.restype = ctypes.c_int32
  sk.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_char_p, ctypes.c_int32, ctypes.c_char_p, ctypes.c_int32, ctypes.POINTER(ctypes.c_int)]
  st = ctypes.c_int(0); sc = op(ctypes.byref(st))
  if st.value > 0 or not sc: sys.exit('uspoof_open failed %d' % st.value)
def skel(s):
    b = s.encode('utf-8'); buf = ctypes.create_string_buffer(256); e = ctypes.c_int(0)
    n = sk(sc, 0, b, len(b), buf, 256, ctypes.byref(e))
    if e.value > 0: raise SystemExit('getSkeleton failed %d on %r' % (e.value, s))
    return buf.raw[:n].decode('utf-8')
if __name__ == '__main__':
    init(sys.argv[1])
    if len(sys.argv) > 2:  # check mode: print ICU skeletons of the given strings
        for s in sys.argv[2:]: print(' '.join('%04X' % ord(c) for c in skel(s)))
        sys.exit(0)
    for cp in range(0x110000):
        if 0xD800 <= cp <= 0xDFFF: continue
        c = chr(cp); s = skel(c)
        if s != unicodedata.normalize('NFD', c):
            print('%04X\t%s' % (cp, ' '.join('%04X' % ord(x) for x in s)))
