#!/usr/bin/env bash
# Round-5 mutation plan. RMn = the reviewer's r4 mutant adapted to the round-5
# code (detailcarry.go is gone; the analogue mutates the same property in
# bodypatch.go); OMn = own mutants. At most one mutant runs at a time.
set -u
W=/mnt/DATA1TB/claude-work/scratch/con456r5_Ipwnma; REV="${1:?rev}"; R="$W/tools/mutrun.sh"
P=scripts/workable-items/cmd/workable-items
$R $W $REV CONTROL x x x
$R $W $REV RM1 $P/bodypatch.go 'return t == "" || t == "---" ||' 'return t == "---" ||'
$R $W $REV RM1b $P/bodypatch.go $'if strings.HasPrefix(t, "**") && strings.Contains(t, ":**") {\n\t\t\t\t\tbreak' $'if false {\n\t\t\t\t\tbreak'
$R $W $REV RM3 $P/bodypatch.go 'if strings.HasPrefix(t, "**"+k+":**") {' 'if strings.HasPrefix(strings.TrimSpace(t), "**"+k+":**") {'
$R $W $REV RM4 $P/bodypatch.go 'return strings.HasPrefix(t, "```") || strings.HasPrefix(t, "~~~")' 'return strings.HasPrefix(t, "```")'
$R $W $REV RM5 $P/bodypatch.go 'for j < m.end && isReopenedDetailBullet(lines[j]) {' 'for j < m.end && false && isReopenedDetailBullet(lines[j]) {'
$R $W $REV RM6 $P/crud.go $'\t\t\t\t\tn += 2\n' ''
$R $W $REV RM7 $P/mutate.go 'newBody, _ = dropRecords(newBody, recChoices)' 'newBody, _ = dropRecords(newBody, recChoices, recReopened)'
$R $W $REV RM9 $P/bodypatch.go 'DELETE FROM operator_block_details WHERE atm_id=?`, id); err != nil {
		return fmt.Errorf' 'DELETE FROM operator_block_details WHERE 0 AND atm_id=?`, id); err != nil {
		return fmt.Errorf'
$R $W $REV M2 $P/mutate.go $'\tif len(probs) > 0 {\n\t\tfmt.Fprintf(os.Stderr, "update: refusing' $'\tif false && len(probs) > 0 {\n\t\tfmt.Fprintf(os.Stderr, "update: refusing'
$R $W $REV OM1 $P/mutate.go $'\t\tnewBody, endedRecord = dropRecords(newBody, recOBD, recChoices)\n\t}\n\t// ATM-627-part-2' $'\t\t_ = endedRecord\n\t}\n\t// ATM-627-part-2'
$R $W $REV OM2 $P/bodypatch.go 'recordHistory(tx, id, "Updated", "AI", "operator-block-ended", removed)' 'error(nil)'
$R $W $REV OM3 $P/bodypatch.go 'if strings.TrimSpace(oldDesc) == strings.TrimSpace(newDesc) {' 'if true {'
$R $W $REV OM4 $P/bodypatch.go 'for i := m.end; i+len(want) <= limit; i++ {' 'for i := 0; i+len(want) <= limit; i++ {'
$R $W $REV OM5 $P/bodypatch.go $'\t\tif !done {\n\t\t\tout = append(out, withNewline(record' $'\t\tif true {\n\t\t\tout = append(out, withNewline(record'
$R $W $REV OM6 $P/bodypatch.go 'skip[last] = true' 'skip[0] = true'
$R $W $REV OM7 $P/mutate.go 'if got, _, _ := operatorBlockParts(newBody); strings.TrimSpace(got) != strings.TrimSpace(rec) {' 'if got, _, _ := operatorBlockParts(newBody); false && strings.TrimSpace(got) != strings.TrimSpace(rec) {'
$R $W $REV OM8 $P/mutate.go 'if loc == "Fixed" {' 'if false && loc == "Fixed" {'
$R $W $REV OM9 $P/mutate.go 'recordKindOf(key+" x") == kind {' 'false && recordKindOf(key+" x") == kind {'
$R $W $REV OM10 $P/crud.go 'synced, endedRecord = dropRecords(synced, recOBD, recChoices)' '_ = endedRecord'
$R $W $REV OM11 $P/mutate.go 'probs = append(probs, blockRecordKept(oldBody, newBody)...)' '_ = blockRecordKept'
$R $W $REV OM12 $P/crud.go 'closedBody, endedRecord = dropRecords(closedBody, recOBD, recChoices)' '_ = endedRecord'
$R $W $REV OM13 $P/mutate.go $'\t\tnewBody, endedRecord = dropRecords(newBody, recOBD, recChoices)\n\t}\n\t// One round trip (idgrammar.go, CON-456): the moved' $'\t\t_ = endedRecord\n\t}\n\t// One round trip (idgrammar.go, CON-456): the moved'
$R $W $REV OM14 $P/mutate.go $'\t\tnewBody, endedRecord = dropRecords(newBody, recOBD, recChoices)\n\t}\n\t// One round trip (idgrammar.go, CON-456): the reopened' $'\t\t_ = endedRecord\n\t}\n\t// One round trip (idgrammar.go, CON-456): the reopened'
$R $W $REV OM15 $P/obsolete.go 'return setRecord(body, recObsolete, detailsLine)' 'return body + detailsLine + "\n"'
echo PLAN-DONE
