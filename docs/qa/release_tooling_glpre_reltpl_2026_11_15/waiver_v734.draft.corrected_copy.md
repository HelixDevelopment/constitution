# DRAFT COPY (evidence only, CON-417, 2026-11-15) — operator override in the §11.4.271 waiver shape for helixconstitution-v73.4

NOT RECORDED. This is a corrected COPY of the scratch draft `waiver_v734.draft.md`, kept in this evidence pack
only. It is not a waiver, records nothing and authorises nothing. Changed against the draft: section "What it
relaxes" is now "What it overrides", and it no longer says that (L1), (L6) or (L7) "ride open" under a waiver.
§11.4.230(E.3) and (F.3)(2): an (L1) entry is never waived, (L6) is never skipped or waived, an open (L7) entry
blocks a release of every class and is never waived, so no conforming §11.4.271 waiver can cover them. What
carries the release over them is the operator decision itself, an override of the rule, stated as such.

---

(original draft text, corrected below)

Status of this text: draft. Operator decision 4 of `docs/operator_decisions/2026-11-11_relayed_decisions.md`
(relayed, not verbatim) records the DECISION only: authoriser `milosvasic`, expiry 30 days from the date the
waiver is recorded, recorded after the release work lands. This file is the text to commit at that moment.

Open points that must be resolved BEFORE it is recorded (each is listed in CHECKLIST.md, UNCONFIRMED U-2):
- §11.4.271(B) roster resolution: `config/full_suite_operators.roster` at main 02c10935 holds ONE identity,
  `i@mvasic.ru` (Милош Васић). The handle `milosvasic` is not literally in the roster. The waiver names the
  rostered identity and the handle; the mapping handle -> `i@mvasic.ru` is the operator's (UNCONFIRMED in-repo).
- §11.4.271(B) / §11.4.240 producer exclusion: commits on this repository are authored as `i@mvasic.ru` even when
  an agent produced them (e.g. 02c10935, co-authored by an agent). The template line "not the producer of this
  commit" is then only true in the sense "the human did not produce the change"; state it exactly that way, or the
  operator records how producer identity is read. Do not claim more.
- Location: no waiver register file exists in the tree (`git ls-files | grep -i waiver` empty at 02c10935).
  Proposed: `docs/operator_decisions/2026-11-1X_waiver_v73.4.md` (tracked, §11.4.215) plus the tracked item below.

---

## §11.4.271 waiver W-v73.4-01 — helixconstitution-v73.4 PROVISIONAL pre-release

| Field | Value |
|---|---|
| Waiver id | W-v73.4-01 |
| Recorded (date the 30-day expiry runs from) | `<YYYY-MM-DD>` — the day this file is committed on `main` |
| Expiry | `<recorded date + 30 days, YYYY-MM-DD>`, end of day UTC; no renewal without a new recorded operator decision (§11.4.271(C), §11.4.261) |
| Authoriser | `milosvasic` = rostered identity `i@mvasic.ru` (Милош Васић), `config/full_suite_operators.roster` |
| Producer exclusion | the authoriser did not author the waived changes; the changes were produced by agent sessions (commits carry the authoriser's git identity plus a `Co-Authored-By` agent line). UNCONFIRMED whether the operator accepts this reading; see open points. |
| Decision source | `docs/operator_decisions/2026-11-11_relayed_decisions.md` decision 4 (relayed by the conductor, not verbatim) |
| Candidate | release commit `<SHA of the release commit>`, tag `helixconstitution-v73.4`, release class pre-release |
| Tracked item (owed work, §11.4.271(D)) | `<CON-NNN>` — "§11.4.40 `--include-heavy` retest and §11.4.185 confirmation of the v73.4 candidate" |

### What it overrides, for this candidate only (an override of the rule, not a conforming waiver)

1. §11.4.230(F.3)(1): the §11.4.185 manual-QA confirmation, and any §11.4.40 retest verdict other than PASS-FULL
   (`scripts/run_full_suite.sh --include-heavy`, exit 0). The entry states the actual verdict through the
   `retest_statement` manual key (PASS-FULL, PARTIAL-TOPOLOGY, FAIL or NOT RUN), never an implied pass.
2. §11.4.230(F.3)(2): the entries of class (L1) (no live verdict per PROVISIONAL item on this fingerprint), (L6)
   (the §11.4.40 retest; closed only on a PASS-FULL verdict) and (L7) (no `docs/PRODUCTION_READINESS.md`; every
   §11.4.260 invariant UNKNOWN) that are open on this candidate. (F.3)(2) says these classes never ride open and
   that an open (L7) entry blocks a release of every class and is never waived. This text does NOT relax (L7) or
   waive any of the three: a §11.4.271 waiver cannot, because the (E.3) permitted-disposition table gives (L1),
   (L6) and (L7) no `waived` disposition. The release does not conform to (F.3)(2) for these entries; it ships only
   because the operator decided to override the rule, and the entry says so in those words. Whether that override
   is acceptable is the operator's decision (§11.4.66), not this draft's.

### What it does NOT do

- It promotes nothing to VERIFIED-DONE (§11.4.290); every item keeps its PROVISIONAL label and verification job.
- It does not stand in for the §11.4.185 confirmation of a FINAL release (CON-230 / FINAL precondition 2): an
  agent-roster QA run is evidence a FINAL entry may cite, never the human confirmation.
- It does not relax §11.4.129 (huge blocker), §11.4.264 (build once, promote), §11.4.113 (no force), or any
  verdict-absence seam other than the ones named above, and it does not certify (L7) green or turn the
  open (L1), (L6), (L7) entries into conforming dispositions.
- At expiry with the tracked item still open, the relaxed conditions return to blocking for any later tag; the
  v73.4 tag itself is never re-tagged or patched (§11.4.230(F.1)).
