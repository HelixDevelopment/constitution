#!/usr/bin/env python3
# Reviewer-authored mutants (CON-456 r5 review). Each: (id, file, old, new, intent).
# apply: python3 -I mutants.py <src_dir_of_cmd_package> <ID>  -> exits 3 if the
# old text is not found exactly once (control needle: the mutant must apply).
import sys, os
M = [
 ("NOOP", "bodypatch.go", "func bodyText(line string) string {", "func bodyText(line string) string {", "identity control"),
 ("RV1", "bodypatch.go",
  "\treturn t == \"\" || t == \"---\" || strings.HasPrefix(t, \"#\") || isFenceLine(line)",
  "\treturn t == \"\" || t == \"---\" || strings.HasPrefix(t, \"#\")",
  "metadata block no longer ends at a fence line"),
 ("RV2", "bodypatch.go",
  "\tif strings.TrimSpace(oldBody) == \"\" {\n\t\treturn nil\n\t}\n\to := unownedLines",
  "\tif true {\n\t\treturn nil\n\t}\n\to := unownedLines",
  "owned-line gate disabled entirely"),
 ("RV3", "bodypatch.go",
  "\tfor i := m.end; i+len(want) <= limit; i++ {",
  "\tfor i := 0; i+len(want) <= limit; i++ {",
  "description region searched from the top of the body (metadata block included)"),
 ("RV4", "mutate.go",
  "\t\tnewBody, _ = dropRecords(newBody, recChoices)\n",
  "",
  "re-block keeps the old Unblock-Choices record of the metadata block"),
 ("RV5", "bodypatch.go",
  "\tif err := recordHistory(tx, id, \"Updated\", \"AI\", \"operator-block-ended\", removed); err != nil {\n\t\treturn fmt.Errorf(\"history: %v\", err)\n\t}\n",
  "",
  "ending a block writes no item_history row"),
 ("RV6", "bodypatch.go",
  "\tif kind != recObsolete && m.typeIdx >= 0 {",
  "\tif m.typeIdx >= 0 {",
  "Obsolete-Details inserted after Type instead of at end of block"),
 ("RV7", "bodypatch.go",
  "\t\tcase recReopened:\n\t\t\tfor j < m.end && isReopenedDetailBullet(lines[j]) {\n\t\t\t\tj++\n\t\t\t}\n",
  "\t\tcase recReopened:\n",
  "Reopened-Details record no longer owns its attribution bullets"),
 ("RV8", "bodypatch.go",
  "\tif ook && (!nok || oldText != newText) {",
  "\tif ook && !nok {",
  "blockRecordKept compares presence only, not the record text"),
 ("RV9", "bodypatch.go",
  "\t\t\t\tout = append(out, withNewline(ln, lines[b-1]))",
  "\t\t\t\tout = append(out, ln+\"\\n\")",
  "replaced description region always ends with a newline"),
 ("RV10", "bodypatch.go",
  "\t\t\tif bodyText(lines[i+k]) != strings.TrimRight(w, \"\\r\") {",
  "\t\t\tif strings.TrimSpace(bodyText(lines[i+k])) != strings.TrimSpace(w) {",
  "description region matched ignoring surrounding white space"),
 ("RV3b", "bodypatch.go",
  "\tfor i := m.end; i+len(want) <= limit; i++ {",
  "\t_ = m\n\tfor i := 0; i+len(want) <= limit; i++ {",
  "description region searched from the top of the body (compiles)"),
 ("RV8b", "bodypatch.go",
  "\tif ook && (!nok || oldText != newText) {",
  "\t_, _ = oldText, newText\n\tif ook && !nok {",
  "blockRecordKept compares presence only (compiles)"),
]
if __name__ == "__main__":
    d, mid = sys.argv[1], sys.argv[2]
    m = [x for x in M if x[0] == mid][0]
    p = os.path.join(d, m[1]); s = open(p).read()
    if s.count(m[2]) != 1:
        print("NOT-APPLIED", mid, s.count(m[2])); sys.exit(3)
    open(p, "w").write(s.replace(m[2], m[3], 1)); print("APPLIED", mid, m[4])
