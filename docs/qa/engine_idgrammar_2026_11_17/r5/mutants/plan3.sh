#!/usr/bin/env bash
# Round-5 mutation plan, part 3, on the final engine (field patch reverted).
# NOOP is a control (an identity replacement). Re-runs the part-2 mutants
# whose run included the reverted field patch.
set -u
W=/mnt/DATA1TB/claude-work/scratch/con456r5_Ipwnma; REV="${1:?rev}"; R="$W/tools/mutrun.sh"
P=scripts/workable-items/cmd/workable-items
$R $W $REV NOOP3 $P/bodypatch.go 'func setRecord(' 'func setRecord('
$R $W $REV RM1b3 $P/bodypatch.go $'if strings.HasPrefix(t, "**") && strings.Contains(t, ":**") {\n\t\t\t\t\tbreak' $'if false && strings.HasPrefix(t, "**") && strings.Contains(t, ":**") {\n\t\t\t\t\tbreak'
$R $W $REV OM43 $P/bodypatch.go 'for i := m.end; i+len(want) <= limit; i++ {' 'for i := 0 * m.end; i+len(want) <= limit; i++ {'
$R $W $REV OM53 $P/bodypatch.go $'\t\tif !done {\n\t\t\tout = append(out, withNewline(record' $'\t\tif true {\n\t\t\tout = append(out, withNewline(record'
$R $W $REV OM113 $P/mutate.go 'probs = append(probs, blockRecordKept(oldBody, newBody)...)
	}
	if len(probs) > 0 {
		fmt.Fprintf(os.Stderr, "update: refusing' '_ = blockRecordKept
	}
	if len(probs) > 0 {
		fmt.Fprintf(os.Stderr, "update: refusing'
$R $W $REV M23 $P/mutate.go $'\tif len(probs) > 0 {\n\t\tfmt.Fprintf(os.Stderr, "update: refusing' $'\tif false && len(probs) > 0 {\n\t\tfmt.Fprintf(os.Stderr, "update: refusing'
echo PLAN3-DONE
