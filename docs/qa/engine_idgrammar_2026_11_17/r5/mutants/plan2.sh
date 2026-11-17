#!/usr/bin/env bash
# Round-5 mutation plan, part 2, on the revision with the field-update patch.
# RM1b and OM4 of part 1 did not compile (an unused variable); they are
# re-authored here so the mutant compiles. OM5 is re-run against its new
# killing test. OM16/OM17 cover the field-update patch. Names carry a "2"
# suffix so part-1 worktrees and logs are kept.
set -u
W=/mnt/DATA1TB/claude-work/scratch/con456r5_Ipwnma; REV="${1:?rev}"; R="$W/tools/mutrun.sh"
P=scripts/workable-items/cmd/workable-items
$R $W $REV CONTROL2 x x x
$R $W $REV RM1b2 $P/bodypatch.go $'if strings.HasPrefix(t, "**") && strings.Contains(t, ":**") {\n\t\t\t\t\tbreak' $'if false && strings.HasPrefix(t, "**") && strings.Contains(t, ":**") {\n\t\t\t\t\tbreak'
$R $W $REV OM42 $P/bodypatch.go 'for i := m.end; i+len(want) <= limit; i++ {' 'for i := 0 * m.end; i+len(want) <= limit; i++ {'
$R $W $REV OM52 $P/bodypatch.go $'\t\tif !done {\n\t\t\tout = append(out, withNewline(record' $'\t\tif true {\n\t\t\tout = append(out, withNewline(record'
$R $W $REV OM16 $P/mutate.go $'\tif len(fieldsSet) > 0 {\n\t\tnewBody = alignMetaLines(newBody, *cur)' $'\tif false && len(fieldsSet) > 0 {\n\t\tnewBody = alignMetaLines(newBody, *cur)'
$R $W $REV OM17 $P/mutate.go 'description: descEdit, fields: fieldsSet}' 'description: descEdit}'
$R $W $REV OM18 $P/bodypatch.go 'm != nil && fk[strings.ToLower(m[1])] {' 'm != nil {'
$R $W $REV OM112 $P/mutate.go 'probs = append(probs, blockRecordKept(oldBody, newBody)...)
	}
	if len(probs) > 0 {
		fmt.Fprintf(os.Stderr, "update: refusing' '_ = blockRecordKept
	}
	if len(probs) > 0 {
		fmt.Fprintf(os.Stderr, "update: refusing'
echo PLAN2-DONE
