// created_at_snapshot_test.go — CON-339: the created_at snapshot md-to-db
// carries across its two document transactions. Unit test of the lookup rule
// (exact key first, else the earliest value of the same item, else nil so the
// column default applies to a genuinely new item).
package main

import "testing"

// TestCON339_CreatedAtFallbackIsEarliestOfTheItem: a row whose exact key
// (atm_id, location, representation) did not exist before takes the EARLIEST
// created_at the snapshot holds for that atm_id.
func TestCON339_CreatedAtFallbackIsEarliestOfTheItem(t *testing.T) {
	snap := createdAtSnapshot{
		"WIT-001|Issues|section": "2020-05-05 05:05:05",
		"WIT-001|Fixed|table":    "2020-01-01 01:01:01",
		"WIT-002|Issues|section": "2020-02-02 02:02:02",
	}
	cases := []struct{ id, loc, rep, want string }{
		{"WIT-001", "Issues", "section", "2020-05-05 05:05:05"}, // exact key wins
		{"WIT-001", "Fixed", "section", "2020-01-01 01:01:01"},  // earliest of the item
		{"WIT-002", "Fixed", "section", "2020-02-02 02:02:02"},
		{"WIT-009", "Issues", "section", ""}, // unknown item: the column default applies
	}
	for _, c := range cases {
		got := snap.lookup(c.id, c.loc, c.rep)
		if (c.want == "" && got != nil) || (c.want != "" && (got == nil || *got != c.want)) {
			gs := "<nil>"
			if got != nil {
				gs = *got
			}
			t.Errorf("lookup(%s,%s,%s) = %s, want %q", c.id, c.loc, c.rep, gs, c.want)
		}
	}
}
