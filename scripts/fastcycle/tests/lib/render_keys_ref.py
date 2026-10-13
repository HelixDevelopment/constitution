#!/usr/bin/env python3
"""
T062 reference (non-production) implementation of T-C12's per-twin key
formula, authored independently of `constitution/scripts/fastcycle/docs/
render_keys.py` (a later, separate task -- it does not exist yet at the
time this file was written). Used ONLY by `test_render_keys_red.sh` to
build/verify its fixture pairs under `fixtures/render_keys/` -- it never
claims to BE render_keys.py and it is never itself the tool a later GREEN
run invokes (Producer != Verifier, §11.4.240).

Contract: specs/004-fast-dev-cycles/plan.md T-C12 ("Content-addressed,
parallel, batched twin regeneration"), Work line, verbatim:

    key = hash(source bytes || stylesheet || exporter version ||
               pandoc/weasyprint versions || format)

No contracts/ file names this tool explicitly (confirmed absent by this
file's own author, per the same "confirmed no contract exists" pattern
T057/T060/T061 already document for their own tools). The concrete
separator, hash algorithm, and per-component string forms below are
DEFINED here, following the house precedent set by
`tests/lib/dec07_key_ref.py` (DEC-07, whose SEP + canon_map + "excluded
fields" style this file reuses byte-for-byte, not independently
re-derived) -- UNCONFIRMED by the plan itself, binding-if-adopted on
T-C12's real implementer, never silently assumed.

    key = SHA-256(
      source bytes ||
      stylesheet (path or identifier string) ||
      exporter version (a SHA-256 of the exporter script's OWN bytes --
        `scripts/testing/sync_all_markdown_exports.sh` publishes no
        semver today, so its content hash is the defensible,
        content-addressed proxy this file adopts, mirroring DEC-07's own
        "gate-script bytes are a key component" precedent) ||
      pandoc version string (as reported by `pandoc --version`'s first
        line) ||
      weasyprint version string (as reported by `weasyprint --version`) ||
      format ("html" | "pdf" | "docx")
    )

Deliberately EXCLUDED from the preimage (mirroring DEC-07's own excluded
list): the source file's PATH (only its BYTES are hashed) and its mtime
(T-C12's whole point is that mtime must NOT decide freshness -- a recorded
key comparison is the freshness gate the plan itself names).

Usage: render_keys_ref.py <source_md_path> <stylesheet> <exporter_version>
<pandoc_version> <weasyprint_version> <format>
Prints the 64-hex-char reference key to stdout and exits 0, or prints
nothing and exits 1 on a malformed input (missing source file, wrong
argument count).
"""
import hashlib
import sys

SEP = "\x1f"


def reference_key(source_bytes, stylesheet, exporter_version, pandoc_version,
                   weasyprint_version, fmt):
    parts = [
        source_bytes.decode("latin-1"),
        stylesheet,
        exporter_version,
        pandoc_version,
        weasyprint_version,
        fmt,
    ]
    payload = SEP.join(parts).encode("utf-8", errors="surrogateescape")
    return hashlib.sha256(payload).hexdigest()


def main():
    if len(sys.argv) != 7:
        print(
            "usage: render_keys_ref.py <source_md_path> <stylesheet> "
            "<exporter_version> <pandoc_version> <weasyprint_version> "
            "<format>",
            file=sys.stderr,
        )
        return 1
    (source_path, stylesheet, exporter_version, pandoc_version,
     weasyprint_version, fmt) = sys.argv[1:7]
    try:
        with open(source_path, "rb") as f:
            source_bytes = f.read()
        print(
            reference_key(
                source_bytes, stylesheet, exporter_version, pandoc_version,
                weasyprint_version, fmt,
            )
        )
    except OSError as exc:
        print(f"render_keys_ref.py: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
