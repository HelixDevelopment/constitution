-- workable-items DDL — §11.4.93 SQLite-SSoT for workable items
--
-- Canonical authority: constitution/Constitution.md §11.4.93
-- Forensic anchor: User mandate 2026-05-27.
--
-- This schema is the AUTHORITATIVE source for every workable item.
-- All Markdown / HTML / PDF / Summary / Status surfaces are generator
-- output derived from this DB. Sync drift is mechanically impossible
-- because every regeneration starts from these tables.
--
-- Bidirectional regeneration guarantee (§11.4.93):
--   md→db: `workable-items sync md-to-db` parses Issues.md + Fixed.md +
--          Status.md fleet, upserts here.
--   db→md: `workable-items sync db-to-md` regenerates the same docs from
--          this DB. Round-trip MUST be byte-identical modulo whitespace.

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;       -- crash-resistant + concurrent read
PRAGMA synchronous = NORMAL;     -- balance durability vs throughput

-- ============================================================
-- §11.4.93 — items: primary registry
-- ============================================================
CREATE TABLE IF NOT EXISTS items (
    -- §11.4.54 ATM-NNN ticket identifier (monotonic, append-only, never
    -- renumbered, never reused). NOT a bare PRIMARY KEY: the SAME ticket id
    -- legitimately appears in BOTH trackers — a tombstone in Issues.md AND a
    -- closure row in Fixed.md (e.g. HXC-017). The identity is therefore
    -- (atm_id, current_location); see the composite PRIMARY KEY below.
    atm_id           TEXT NOT NULL,

    -- §11.4.16 Type closed-set
    type             TEXT NOT NULL CHECK (type IN ('Bug', 'Feature', 'Task')),

    -- §11.4.15 + §11.4.21 + §11.4.90 Status closed-set (8 values)
    status           TEXT NOT NULL CHECK (status IN (
                         'Queued', 'In progress', 'Ready for testing',
                         'In testing', 'Reopened', 'Operator-blocked',
                         'Fixed (→ Fixed.md)', 'Implemented (→ Fixed.md)',
                         'Completed (→ Fixed.md)', 'Obsolete (→ Fixed.md)'
                     )),

    -- Severity (informational only; not closed-set, but recommended)
    severity         TEXT,

    -- Heading line text (full H2 heading including code prefix per §11.4.54)
    title            TEXT NOT NULL,

    -- §11.4.91 description floor: ≥ 6 words OR ≥ 40 chars (enforced at insert)
    description      TEXT NOT NULL,

    -- Forensic anchor — verbatim user mandate or operator quote
    forensic_anchor  TEXT,

    -- Closure criteria (markdown body)
    closure_criteria TEXT,

    -- Composes-with cross-references — JSON array of §-letter or ATM-NNN refs
    composes_with    TEXT,                    -- JSON-encoded array

    -- Group-atomic track-assignment (docs/tracks/ASSIGNMENT_MECHANISM_DESIGN.md
    -- §3.1; §11.4.176/§11.4.119/§11.4.111). destination = the branch this item
    -- lands on ('main' | 'feature:<slug>'); logic_group = the single
    -- mutually-exclusive set the item belongs to. Referential integrity
    -- (logic_group -> logic_groups.group_id) is enforced at the Go layer by
    -- `validate-groups` (a later phase) — no DB-level FOREIGN KEY, consistent
    -- with the obsolete_details / operator_block_details / firebase_metadata
    -- precedent of Go-side-validated cross-references rather than SQL FK. Both
    -- columns are NULL until classified (one-time seeding, a later phase); NULL
    -- means "not yet classified", never "no group" — every item whose status is
    -- open MUST carry non-null values before it is dispatchable (a later
    -- phase's totality invariant).
    destination      TEXT,
    logic_group      TEXT,

    -- Participant attribution (§11.4.104 / Herald PARTICIPANT_ATTRIBUTION.md).
    -- created_by  = canonical handle that opened the item; assigned_to = canonical
    -- handle the item is assigned to. Canonical handle closed set: "Claude" (the
    -- system agent; never tagged), or a subscriber's @username. Empty '' = legacy
    -- item with no attribution recorded (back-compat default).
    created_by       TEXT NOT NULL DEFAULT '',
    assigned_to      TEXT NOT NULL DEFAULT '',

    -- Current document location for atomic-move discipline per §11.4.19
    current_location TEXT NOT NULL CHECK (current_location IN ('Issues', 'Fixed')) DEFAULT 'Issues',

    -- §11.4.93 byte-identical-round-trip mechanism: the verbatim raw Markdown
    -- block (Issues H2 item) or raw table row (Fixed) this item was parsed
    -- from. db→md regeneration concatenates these (interleaved with
    -- doc_segments raw prose) to reproduce the source byte-for-byte.
    body_md          TEXT,

    -- Timestamps
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    last_modified    TEXT NOT NULL DEFAULT (datetime('now')),

    -- Composite identity: a ticket may be present in both trackers at once.
    PRIMARY KEY (atm_id, current_location)
);

-- Performance: covering indexes for the most frequent query patterns.
-- status + type are the primary filter axes for status-summary generation and
-- per-status sweeps (Issues_Summary, Fixed_Summary, gate checks).
CREATE INDEX IF NOT EXISTS idx_items_status ON items(status);
CREATE INDEX IF NOT EXISTS idx_items_type ON items(type);
CREATE INDEX IF NOT EXISTS idx_items_status_type ON items(status, type);

-- logic_group + destination are the join+filter axes for work-track-binding
-- guards (§11.4.191) and group-completion sweeps. Queried on every PreToolUse
-- git-commit check.
CREATE INDEX IF NOT EXISTS idx_items_logic_group ON items(logic_group);
CREATE INDEX IF NOT EXISTS idx_items_destination ON items(destination);

-- current_location is the discriminator for "open vs closed" queries; filtered
-- on every sync/validation pass.
CREATE INDEX IF NOT EXISTS idx_items_current_location ON items(current_location);

-- created_by + assigned_to are the participant-attribution lookup axes
-- (§11.4.104), queried on notification-tagging sweeps.
CREATE INDEX IF NOT EXISTS idx_items_created_by ON items(created_by);
CREATE INDEX IF NOT EXISTS idx_items_assigned_to ON items(assigned_to);

-- ============================================================
-- §11.4.93 — item_history: append-only audit log
-- Covers §11.4.34 Reopened attribution + §11.4.90 Obsolete attribution +
-- §11.4.42 iteration discipline state transitions.
-- ============================================================
CREATE TABLE IF NOT EXISTS item_history (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    atm_id           TEXT NOT NULL,

    -- Event type — closed-set
    event_type       TEXT NOT NULL CHECK (event_type IN (
                         'Opened', 'Updated', 'Reopened',
                         'Fixed', 'Implemented', 'Completed', 'Obsolete'
                     )),

    -- §11.4.34 source attribution
    by               TEXT CHECK (by IN ('AI', 'User', NULL)),

    -- ISO date
    on_date          TEXT NOT NULL,

    -- §11.4.34 / §11.4.90 closed-set Reason vocabulary
    reason           TEXT,

    -- Captured-evidence per §11.4.5 — path to artefact under qa-results/ etc.
    evidence_path    TEXT,

    -- T-A05 (SpecKit-004): the event's OWN provable occurrence time (UTC
    -- ISO-8601, seconds), DISTINCT from created_at (row-INSERT wall-clock
    -- time, §11.4.226 evidence-class-at-closure). NULL unless a requester
    -- supplied it or a provable artefact backfilled it. NEVER guessed
    -- (§11.4.6) and NEVER copied from created_at (§11.4.226).
    occurred_at      TEXT,

    -- Provenance of occurred_at: "commit:<sha>", "evidence:<path>",
    -- "registry:<field>", or the literal "UNKNOWN" when occurred_at is
    -- NULL. Set automatically by recordHistoryWithTime — never left NULL
    -- itself, so an UNKNOWN time is always machine-distinguishable from an
    -- unset column.
    occurred_at_source TEXT,

    created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_item_history_atm_id ON item_history(atm_id);
CREATE INDEX IF NOT EXISTS idx_item_history_event_type ON item_history(event_type);
CREATE INDEX IF NOT EXISTS idx_item_history_atm_id_event ON item_history(atm_id, event_type);

-- ============================================================
-- §11.4.90 — obsolete_details: triple-check evidence for Obsolete items
-- ============================================================
CREATE TABLE IF NOT EXISTS obsolete_details (
    atm_id                  TEXT PRIMARY KEY,

    -- ISO date of obsolescence determination
    since                   TEXT NOT NULL,

    -- §11.4.90 closed-set Reason vocabulary
    reason                  TEXT NOT NULL CHECK (reason IN (
                                'superseded-by-design-change',
                                'superseded-by-later-mandate',
                                'feature-removed',
                                'duplicate-of',
                                'unsupported-topology'
                            )),

    -- §-letter / ATM-NNN reference of the work that obsoleted this item
    superseding_item        TEXT NOT NULL,

    -- §11.4.90 triple-check: positive captured evidence (NOT bare assertion)
    triple_check_evidence   TEXT NOT NULL
);

-- ============================================================
-- §11.4.21 — operator_block_details: when Status=Operator-blocked
-- ============================================================
CREATE TABLE IF NOT EXISTS operator_block_details (
    atm_id                       TEXT PRIMARY KEY,
    what                         TEXT NOT NULL,
    why_exhausted_alternatives   TEXT NOT NULL,
    unblock_condition            TEXT NOT NULL,
    who                          TEXT
);

-- ============================================================
-- §11.4.47 — firebase_metadata: per-item Firebase-sourced telemetry
-- ============================================================
CREATE TABLE IF NOT EXISTS firebase_metadata (
    atm_id                 TEXT PRIMARY KEY,
    firebase_issue_ids     TEXT,           -- JSON array
    firebase_url           TEXT,
    stacktrace_cluster_hash TEXT,
    kpi                    TEXT,           -- Performance KPI ref
    funnel                 TEXT            -- Analytics funnel ref
);

-- ============================================================
-- docs/tracks/ASSIGNMENT_MECHANISM_DESIGN.md §3.2 — logic_groups: the
-- group-atomic track-assignment mechanism's authoritative group registry
-- (§11.4.176/§11.4.119/§11.4.111). A track claims ONE group_id at a time
-- (exactly-once, multitrack_claim.sh) and works every item whose
-- items.logic_group equals that group_id to full completion before freeing.
-- Referential integrity (items.logic_group -> logic_groups.group_id) is
-- enforced at the Go layer (a later phase's `validate-groups`) rather than a
-- SQL FOREIGN KEY, consistent with the rest of this schema's cross-reference
-- style (obsolete_details / operator_block_details / firebase_metadata).
-- ============================================================
CREATE TABLE IF NOT EXISTS logic_groups (
    -- Stable id, lowercase snake/kebab (§11.4.29), e.g. 'mistiq-vader-rebrand',
    -- 'audio-5.1-multichannel', 'video-bugs', 'urgent-main', 'unassigned-triage'.
    group_id     TEXT PRIMARY KEY,

    -- Human title (>= 6 words / §11.4.91 clarity floor).
    title        TEXT NOT NULL,

    -- The single branch every member of this group lands on: 'main' |
    -- 'feature:<slug>'. A group is homogeneous in destination (design §3.1
    -- destination-agreement invariant, Go-validated by a later phase).
    destination  TEXT NOT NULL,

    -- Lower = sooner. Derived from ROADMAP ordering; 'urgent-main' = 0.
    priority     INTEGER NOT NULL,

    -- Group lifecycle state machine (ASSIGNMENT_MECHANISM_DESIGN.md §4).
    -- 'open': >=1 open member, unowned. 'in-progress': exactly one track owns
    -- it (multitrack_claim.sh). 'group-complete': every member terminal +
    -- destination merge confirmed; the owning track has freed.
    state        TEXT NOT NULL DEFAULT 'open'
                 CHECK (state IN ('open', 'in-progress', 'group-complete')),

    -- Plain-language membership definition for audit — NOT a matcher (the
    -- defect this mechanism replaces was substring-matching free text; this
    -- field is documentation only, never consulted by the assigner).
    scope_note   TEXT,

    -- Pointer to the ROADMAP / priority-doc line that set this group's
    -- priority (audit trail for §11.4.66 operator-confirmed priorities).
    roadmap_ref  TEXT,

    -- §11.4.191 work-to-track/branch binding: the operator-pinned canonical
    -- track id this group's work MUST land on ('track-1'..'track-N', matching
    -- config/multitrack/<host>.yaml tracks[].id). `destination` stays the
    -- authoritative BRANCH (already read by guard-branch-consistency.sh);
    -- `canonical_track` records the TRACK. NULL = "branch-bound but not
    -- track-pinned" (branch enforced, track not) — additive, every existing
    -- consumer of `destination` is unaffected. Go-side seeded (a later phase);
    -- the guard/resolver treat NULL as "no track assertion" (honest boundary).
    canonical_track TEXT
);

CREATE INDEX IF NOT EXISTS idx_logic_groups_destination ON logic_groups(destination);
CREATE INDEX IF NOT EXISTS idx_logic_groups_state ON logic_groups(state);

-- ============================================================
-- §11.4.191 — group_paths: the file-scope manifest (the missing datum).
-- One row per repo-root-relative glob; many globs per group. Answers the
-- question guard-branch-consistency.sh could NOT: "does this changed file
-- belong to a group whose canonical branch/track != the current checkout?".
-- Referential integrity (group_id -> logic_groups.group_id) is Go-validated
-- (schema style §11.4.93), not a SQL FOREIGN KEY. A path owned by NO row is
-- UNCLASSIFIED -> main-eligible (belongs to no feature group); only a path
-- matching a glob whose group's destination != the current branch is a
-- violation. Globs MUST be as specific as the real ownership (§11.4.6 — avoid
-- over-blocking); longest-glob (most-specific) wins at resolution time.
-- ============================================================
CREATE TABLE IF NOT EXISTS group_paths (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id     TEXT NOT NULL,          -- FK-ish -> logic_groups.group_id (Go-validated)
    path_glob    TEXT NOT NULL,          -- repo-root-relative glob, e.g. 'device/rockchip/atmosphere/remote_host/**'
    note         TEXT,                   -- audit rationale (why this path is this group's exclusive scope)
    UNIQUE(group_id, path_glob)
);

CREATE INDEX IF NOT EXISTS idx_group_paths_group_id ON group_paths(group_id);

-- ============================================================
-- §11.4.93 — doc_segments: ordered byte-identical-round-trip ledger
--
-- Each source document (Issues.md / Fixed.md) is decomposed into an
-- ordered sequence of segments. A segment is either:
--   kind='item' — a parsed workable item; raw text lives in items.body_md,
--                 referenced by atm_id. (Queryable + validatable.)
--   kind='raw'  — verbatim prose (preamble, prefix-convention section,
--                 inter-item separators, table header/footer) that is NOT
--                 a workable item; raw text lives in `raw`.
--
-- db→md walks this table in (document, seq) order, emitting raw segments
-- verbatim and item segments from items.body_md — reproducing the source
-- byte-for-byte (modulo trailing whitespace tolerance).
-- ============================================================
CREATE TABLE IF NOT EXISTS doc_segments (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    document    TEXT NOT NULL CHECK (document IN ('Issues', 'Fixed')),
    seq         INTEGER NOT NULL,
    kind        TEXT NOT NULL CHECK (kind IN ('item', 'raw')),
    atm_id      TEXT,          -- set when kind='item' (FK-ish to items.atm_id)
    raw         TEXT,          -- set when kind='raw'
    UNIQUE(document, seq)
);

CREATE INDEX IF NOT EXISTS idx_doc_segments_document ON doc_segments(document);

-- ============================================================
-- meta: schema version + sync state
-- ============================================================
CREATE TABLE IF NOT EXISTS meta (
    key                  TEXT PRIMARY KEY,
    value                TEXT NOT NULL,
    last_modified        TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT OR REPLACE INTO meta(key, value) VALUES
    ('schema_version', '4'),
    ('last_sync_direction', 'none'),
    ('last_sync_timestamp', ''),
    ('integrity_hash', '');
