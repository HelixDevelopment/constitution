#!/usr/bin/env python3
"""render_keys.py -- content-addressed per-twin render key (SpecKit-004
"fast-dev-cycles", User Story 2; plan.md T-C12; SC-002, FR-022; tasks.md
T080, "the key half" of T062).

Guarded by
constitution/scripts/fastcycle/tests/test_render_keys_red.sh (T062).
No dedicated contracts/ file names this tool (confirmed absent, per the
same pattern T057/T060/T061 already document for their own tools --
specs/004-fast-dev-cycles/contracts/ has no render-keys*.md or
twin-rendering*.md entry, per fixtures/render_keys/README.md's own audit).
This docstring restates the BINDING wire format DEFINED by that README
(itself following the fixtures/verdict_cache/README.md precedent) -- the
README is authoritative; if the two ever diverge, the README wins.

T080 scope note (Producer != Verifier, §11.4.240 -- the KEY half only):
this task implements render_keys.py's own compute/check/store
subcommands, so a per-twin key can be computed, verified against a
recorded sidecar, and stored. It does NOT wire this tool into
scripts/testing/sync_all_markdown_exports.sh (parallel batched
regeneration, the mtime-AND-key freshness gate inside THAT script) -- that
is T081's separate, later task, per tasks.md's own line split ("the key
half of T062" here vs "until T062 is fully GREEN" there). This file never
edits sync_all_markdown_exports.sh.

test_render_keys_red.sh's Sections C1/C2 exercise the ALREADY-EXISTING
real exporter directly (today's mtime-only behaviour, and the correct
must-be-preserved all-four-formats regeneration) and pass today regardless
of this file's existence. Only Sections C3 (golden-bad: a changed source
whose key sidecar was not updated must be caught, STALE) and C4 (the
direct positive contrast: a touched-but-content-identical source must be
recognised FRESH) invoke THIS tool -- via `check` -- and are this task's
GREEN criterion.

Key formula (per fixtures/render_keys/README.md and
tests/lib/render_keys_ref.py, the T062 reference this implementation was
independently written from -- not by importing that file's code, but the
two are BYTE-IDENTICAL in formula because both follow the same written
contract; verified live against this checkout's own tracked fixtures
before this docstring was written, never merely assumed, §11.4.6: running
render_keys_ref.py against rk_stale_key_caught/source.md and
rk_touched_identical/source.md with this host's real `pandoc --version` /
`weasyprint --version` and the real exporter script's sha256 reproduces
key_v1.json's and key_matching.json's recorded "key" fields exactly):

    key = SHA-256(
      source bytes ||
      stylesheet (path/identifier string, as supplied via --stylesheet)||
      exporter version (a caller-supplied string via --exporter-version;
        the fixture convention is a SHA-256 of scripts/testing/
        sync_all_markdown_exports.sh's OWN bytes, since that script
        publishes no semver today -- this tool never computes that hash
        itself, it only receives whatever string the caller passes) ||
      pandoc version string (via --pandoc-version) ||
      weasyprint version string (via --weasyprint-version) ||
      format ("html" | "pdf" | "docx", via --format)
    ), fields U+001F-separated (SEP), matching dec07_key_ref.py's /
    render_keys_ref.py's own convention (reused for consistency, not
    independently re-derived).

Deliberately EXCLUDED from the preimage (T-C12's whole point): the source
file's PATH (only its BYTES are hashed) and its mtime -- a bare `touch`
must never change the key.

CLI (per fixtures/render_keys/README.md's DEFINED, binding-if-adopted
contract):

    render_keys.py compute --source <path.md> --format {html|pdf|docx} \\
        --stylesheet <path> --exporter-version <str> \\
        --pandoc-version <str> --weasyprint-version <str> \\
        [--determinism-check]
      Computes the key from the CURRENT source bytes + the 5 named
      components and prints the 64-hex-char SHA-256 key to stdout.
      --determinism-check (C-003, FR-021): computes the key TWICE
      internally from the identical inputs and refuses (exit 1, naming
      the mismatch) if the two runs disagree -- they never should, since
      the formula reads no clock/random/host state, but the flag exists
      so a caller can PROVE that rather than assume it. Exit 0 on
      success.

    render_keys.py check --source <path.md> --format {html|pdf|docx} \\
        --key-file <path/to/key.json> \\
        --stylesheet <path> --exporter-version <str> \\
        --pandoc-version <str> --weasyprint-version <str> \\
        [--determinism-check]
      Reads the RECORDED key from --key-file's top-level "key" field,
      recomputes the CURRENT key from the same 5 flags read live, and
      compares. On a match, prints "FRESH" and exits 0 (the exporter may
      safely skip the render -- "a skipped render is still proven
      current", plan.md T-C12's own Work line). On a mismatch, prints
      "STALE" (naming the differing component where the key-file's own
      "key_components"/"recorded_source_sha256" fields make that
      determinable) and exits 1 -- this IS "the freshness gate" T-C12's
      Work line and rk_stale_key_caught/'s golden-bad scenario both name.

    render_keys.py store --source <path.md> --format {html|pdf|docx} \\
        --key-file <path/to/key.json> \\
        --stylesheet <path> --exporter-version <str> \\
        --pandoc-version <str> --weasyprint-version <str> \\
        [--determinism-check]
      Computes the key from the CURRENT inputs (same formula as compute)
      and writes/overwrites --key-file with the recorded key (mirroring
      the tracked fixtures' own key_v1.json/key_matching.json shape:
      source basename, format, key, key_components, recorded_source_
      sha256, and a provenance-only computed_at timestamp that -- per the
      formula above -- is never part of the key preimage itself). Exit 0
      on success.

Exit codes (C-001, specs/004-fast-dev-cycles/contracts/common-
conventions.md): 0 success / FRESH; 1 a finding (STALE, or a
--determinism-check mismatch); 2 usage/missing-flag/unparseable-input
error; 4 BLIND (a required file -- --source or --key-file -- could not be
read). This tool never falls back to a bare process exit code the caller
might misread (§11.4.6) -- FRESH/STALE are always printed to stdout as the
same literal tokens this docstring and the README name, in addition to
the exit code.

Fix-forward note on test_render_keys_red.sh (§11.4.6, "no bluff" --
documented, not silently patched around): as originally authored, Section
C3's success condition read `[ "$C3_RC" -eq 0 ] && echo "$C3_OUT" | grep
-qi 'STALE'`, requiring a ZERO exit code on a STALE (mismatch) verdict.
This contradicts (a) the same file's own module docstring ("self-flips
GREEN (expected: STALE + non-zero exit)"), (b) the same block's own
`bad`-branch explanatory text ("once T-C12 lands this check must
genuinely flip to STALE+nonzero"), (c) fixtures/render_keys/README.md's
CLI contract ("prints STALE ... and exits non-zero"), (d) C-001's own
exit-code table (a finding = exit 1), and (e) Section C4's own parallel,
internally-consistent pattern (`[ "$C4_RC" -eq 0 ] && grep -qi 'FRESH'`,
correctly pairing exit 0 with the FRESH verdict). This is a genuine
copy/paste typo in the test's executable assertion, not a considered
design choice -- every other authority in the same file and the README
agrees STALE must be non-zero. Per this task's TDD mandate ("if it has a
genuine bug, fix forward with documented evidence"), line 375 of
test_render_keys_red.sh was corrected from `-eq 0` to `-ne 0` (T080; see
that file's own inline comment at the fix site for this same citation).
The test was never weakened: the fix makes it assert the STRICTER, already
-documented-elsewhere behaviour (a real freshness gate that reports STALE
but exits 0 would let a naive `if render_keys.py check; then skip_render;
fi` caller silently skip re-rendering a genuinely stale twin -- the exact
defect class T-C12 exists to prevent).
"""
import argparse
import hashlib
import json
import os
import sys
import time

SEP = "\x1f"

EXIT_OK = 0
EXIT_FINDING = 1
EXIT_USAGE = 2
EXIT_SELFTEST = 3
EXIT_BLIND = 4

FORMATS = ("html", "pdf", "docx")


def compute_key(source_bytes, stylesheet, exporter_version, pandoc_version,
                 weasyprint_version, fmt):
    """T-C12 key formula -- see module docstring. Byte-identical to
    tests/lib/render_keys_ref.py's reference_key() (verified against the
    tracked fixtures, never merely assumed)."""
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


def read_source_bytes(path, who):
    """C-001 exit 4 (BLIND): a required --source file that cannot be read
    is an evidence-file-missing condition, never guessed / never treated
    as an empty-bytes source (§11.4.6)."""
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except OSError as exc:
        sys.stderr.write(f"render_keys.py {who}: cannot read --source {path!r}: {exc}\n")
        sys.exit(EXIT_BLIND)


def compute_key_with_optional_determinism_check(args, who):
    """Shared by compute/check/store: computes the key from args' 5
    components + the current --source bytes; if --determinism-check is
    set, computes it a SECOND time from the identical inputs and refuses
    (EXIT_FINDING, naming the mismatch) unless the two runs agree
    byte-for-byte (C-003/FR-021 -- the formula reads no clock/random/host
    state, so a real mismatch here means the tool itself is broken, not
    that the world changed between the two calls)."""
    source_bytes = read_source_bytes(args.source, who)
    key = compute_key(source_bytes, args.stylesheet, args.exporter_version,
                       args.pandoc_version, args.weasyprint_version, args.format)
    if args.determinism_check:
        key2 = compute_key(source_bytes, args.stylesheet, args.exporter_version,
                            args.pandoc_version, args.weasyprint_version, args.format)
        if key != key2:
            sys.stderr.write(
                f"render_keys.py {who}: --determinism-check FAILED: two "
                f"consecutive computations of the identical inputs produced "
                f"different keys ({key} != {key2})\n"
            )
            sys.exit(EXIT_FINDING)
    return source_bytes, key


def cmd_compute(args):
    _source_bytes, key = compute_key_with_optional_determinism_check(args, "compute")
    print(key)
    return EXIT_OK


def load_key_file(path, who):
    """C-001: a missing --key-file is an evidence-file-missing condition
    (exit 4, BLIND); a present-but-unparseable one is a malformed-input
    usage error (exit 2) -- distinct failure classes, per C-001's own
    row descriptions."""
    if not os.path.isfile(path):
        sys.stderr.write(f"render_keys.py {who}: --key-file not found: {path}\n")
        sys.exit(EXIT_BLIND)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        sys.stderr.write(f"render_keys.py {who}: --key-file is not readable/parseable JSON: {exc}\n")
        sys.exit(EXIT_USAGE)


def identify_stale_components(doc, source_bytes, args):
    """Best-effort attribution of WHICH input changed, using whatever
    provenance fields the recorded --key-file happens to carry
    (key_components / recorded_source_sha256 -- both OPTIONAL per the
    README's "at minimum a top-level key field" contract). Returns a list
    of human-readable "<field> (recorded X -> current Y)" strings; an
    empty list means the recorded sidecar carried no provenance fields to
    attribute the mismatch to (still correctly reported STALE, just
    without a named component -- "naming the differing component where
    determinable", per the README)."""
    findings = []
    recorded_source_sha256 = doc.get("recorded_source_sha256")
    if isinstance(recorded_source_sha256, str):
        current_source_sha256 = hashlib.sha256(source_bytes).hexdigest()
        if current_source_sha256 != recorded_source_sha256:
            findings.append(
                f"source (recorded sha256 {recorded_source_sha256} -> "
                f"current sha256 {current_source_sha256})"
            )
    key_components = doc.get("key_components")
    if isinstance(key_components, dict):
        checks = (
            ("stylesheet", args.stylesheet),
            ("exporter_version", args.exporter_version),
            ("pandoc_version", args.pandoc_version),
            ("weasyprint_version", args.weasyprint_version),
        )
        for name, current_value in checks:
            recorded_value = key_components.get(name)
            if recorded_value is not None and recorded_value != current_value:
                findings.append(
                    f"{name} (recorded {recorded_value!r} -> current {current_value!r})"
                )
    recorded_format = doc.get("format")
    if isinstance(recorded_format, str) and recorded_format != args.format:
        findings.append(f"format (recorded {recorded_format!r} -> current {args.format!r})")
    return findings


def cmd_check(args):
    doc = load_key_file(args.key_file, "check")
    recorded_key = doc.get("key")
    if not isinstance(recorded_key, str) or not recorded_key:
        sys.stderr.write(
            f"render_keys.py check: --key-file {args.key_file!r} has no "
            f"top-level string \"key\" field\n"
        )
        return EXIT_USAGE

    source_bytes, current_key = compute_key_with_optional_determinism_check(args, "check")

    if current_key == recorded_key:
        print(f"FRESH key={current_key}")
        return EXIT_OK

    findings = identify_stale_components(doc, source_bytes, args)
    if findings:
        print(f"STALE key={current_key} recorded_key={recorded_key} mismatch={'; '.join(findings)}")
    else:
        print(
            f"STALE key={current_key} recorded_key={recorded_key} "
            f"mismatch=<no key_components/recorded_source_sha256 recorded "
            f"to attribute this to>"
        )
    return EXIT_FINDING


def cmd_store(args):
    source_bytes, key = compute_key_with_optional_determinism_check(args, "store")
    doc = {
        "source": os.path.basename(args.source),
        "format": args.format,
        "key": key,
        "key_components": {
            "stylesheet": args.stylesheet,
            "exporter_version": args.exporter_version,
            "pandoc_version": args.pandoc_version,
            "weasyprint_version": args.weasyprint_version,
        },
        "recorded_source_sha256": hashlib.sha256(source_bytes).hexdigest(),
        "recorded_source_sha256_note": (
            "sha256 of source's bytes at store-time -- NOT part of the key "
            "preimage itself (the composite key already covers source "
            "bytes), kept purely so a later `check` can attribute a "
            "mismatch to the source specifically"
        ),
        "computed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "computed_at_note": (
            "provenance only -- per T-C12's own formula, mtime/timestamps "
            "are NEVER part of the key"
        ),
    }
    key_file_dir = os.path.dirname(os.path.abspath(args.key_file))
    if key_file_dir:
        os.makedirs(key_file_dir, exist_ok=True)
    with open(args.key_file, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2, sort_keys=True)
        fh.write("\n")
    print(f"STORED key={key} key_file={args.key_file}")
    return EXIT_OK


def add_common_flags(parser, require_key_file):
    parser.add_argument("--source", required=True)
    parser.add_argument("--format", required=True, choices=FORMATS)
    parser.add_argument("--stylesheet", required=True)
    parser.add_argument("--exporter-version", required=True)
    parser.add_argument("--pandoc-version", required=True)
    parser.add_argument("--weasyprint-version", required=True)
    parser.add_argument("--determinism-check", action="store_true")
    if require_key_file:
        parser.add_argument("--key-file", required=True)


def main(argv):
    parser = argparse.ArgumentParser(
        prog="render_keys.py",
        description="content-addressed per-twin render key (plan.md T-C12)",
    )
    sub = parser.add_subparsers(dest="subcommand")

    compute_p = sub.add_parser("compute")
    add_common_flags(compute_p, require_key_file=False)

    check_p = sub.add_parser("check")
    add_common_flags(check_p, require_key_file=True)

    store_p = sub.add_parser("store")
    add_common_flags(store_p, require_key_file=True)

    if len(argv) < 2:
        parser.print_usage(sys.stderr)
        return EXIT_USAGE

    # argparse itself calls sys.exit(2) on a missing/unrecognised
    # required flag -- already C-001-compliant (EXIT_USAGE), left as-is.
    args = parser.parse_args(argv[1:])

    if args.subcommand == "compute":
        return cmd_compute(args)
    if args.subcommand == "check":
        return cmd_check(args)
    if args.subcommand == "store":
        return cmd_store(args)

    parser.print_usage(sys.stderr)
    return EXIT_USAGE


if __name__ == "__main__":
    sys.exit(main(sys.argv))
