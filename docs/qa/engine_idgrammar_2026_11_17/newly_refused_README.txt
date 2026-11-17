Why 29 cases that the d3fa run classified RT_OK are refused by round 2.

The class enumeration oracle (class_enum.py classify) compares ids
and the carried fields only. It does not compare the item's own text, so a
description or details line that the generator rewrites, or that detaches
from its item, still classifies RT_OK. The 29 cases are three shapes:

1. heading_raw: a description line "## Notes". On d3fa the add succeeds,
   md-to-db keeps only "line one of the description" in the item body
   (newly_refused_d3fa_heading_raw_body.txt), and after a move to Fixed the
   text "## Notes / more words here..." stays behind in Issues.md as an
   orphan section (lines 5845-5846 of the full export; the committed excerpt
   newly_refused_d3fa_heading_raw_after_move_Issues_lines_5836_5850.md holds
   lines 5836 to 5850, the orphan is its lines 10-11).
2. status_line: a description line "**Status:** Fixed (-> Fixed.md)". On
   d3fa the generator rewrote that user line to "**Status:** Queued"
   (Issues) or "**Status:** Completed (-> Fixed.md)" (Fixed) while the item's
   own Status line stayed "Queued" in Fixed.md. Evidence: the d3fa run's per-case
   exports B_canon_status_line_Issues/Issues.md line 5852 and
   B_canon_status_line_Fixed/Fixed.md lines 201 and 206 (scratch, not committed;
   the verdict rows are in class_red_d3fa_table.tsv).
3. nl_status (block details): details "blocked\n**Status:** Fixed (-> Fixed.md)"
   became "**Operator-Block-Details:** WHAT: blocked" followed by a rewritten
   "**Status:** Operator-blocked" line (d3fa run, per-case
   export C_block_canon_nl_status/Issues.md lines 5847-5850, scratch, not committed).

Round 2 refuses each before writing anything (REFUSED = DB dump hash
unchanged), naming the text that would not survive. These are therefore
silent rewrites the field-only oracle could not see, not false refusals.
Limit: the probe for shape 1 was run on one id form (canonical CON-70245);
the other forms are inferred from the same parser path, UNCONFIRMED per id form.
