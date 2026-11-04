# Issues

Preamble prose that is not a workable item — kept verbatim as a raw segment.

## WIT-801 — never assessed bug carries no record

**Status:** Queued
**Type:** Bug
**Severity:** High

No reproduction record: reproduction_state is UNSET and no line is rendered.

## WIT-802 — planned reproduction not yet run

**Status:** In progress
**Type:** Bug
**Severity:** Medium
**Reproduction:** none — UNREPRODUCED — red-command `bash tests/red.sh --board D2` — signature `rc=1 and "frame-size 0"` — updated 2026-11-03T10:00:00Z — by `conductor`
**Investigation:** in-progress — updated 2026-11-03T10:00:00Z — by `conductor`

Body prose that must survive the round trip.

## WIT-803 — host fixture reproduction with a complete record

**Status:** Ready for testing
**Type:** Bug
**Severity:** Low
**Reproduction:** reproduced-host-fixture — REPRODUCED — surface host-only — evidence `qa-results/wit803/red.txt` — red-command `go test -run TestX ./...` — green-command `go test -run TestX ./...` — env `host linux, go 1.26` — signature ``the log carries `frame-size 0` | twice`` — updated 2026-11-03T11:00:00Z — by `agent-a`
**Investigation:** root-cause-found-with-evidence — root-cause `off-by-one in the parser — fixed in parse.go` — evidence `qa-results/wit803/rca.md` — updated 2026-11-03T11:00:00Z — by `agent-a`
**Verification:** provisional

PROVISIONAL-DONE: Ready for testing with a REPRODUCED record.

## WIT-804 — reproduction blocked on a device without a capture rig

**Status:** Queued
**Type:** Bug
**Severity:** Critical
**Reproduction:** blocked-no-device-with-recorded-blocker — UNREPRODUCED — blocker `needs: D2 board; missing: HDMI capture rig` — updated 2026-11-03T12:00:00Z — by `conductor`

## WIT-805 — legacy prose lines stay prose

**Status:** Queued
**Type:** Task
**Severity:** Low
**Reproduction:** reproduced by the operator on 2026-10-01, see the session log
**Investigation:** see the incident write-up

Neither line above is a structured record.

## WIT-806 — live reproduction missing env stays UNREPRODUCED

**Status:** Queued
**Type:** Bug
**Severity:** High
**Reproduction:** reproduced-live — UNREPRODUCED — surface live-target — evidence `qa-results/wit806/red.txt` — red-command `adb shell dumpsys media.audio_flinger` — signature `count=0`

### Sub-component notes

**Reproduction:** none — UNREPRODUCED

The record above belongs to the sub-heading, not to WIT-806.

---
