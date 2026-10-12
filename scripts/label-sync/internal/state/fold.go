package state

import (
	"fmt"
	"sort"
	"strconv"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/label"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
)

// PidTable answers whether a LOCAL process is alive (fakeable in tests).
type PidTable interface{ Alive(pid int) bool }

// Raw is the folded (declared) state: what the events say, before render-time
// computation (label, staleness). Persisted as fold.json (internal).
type Raw struct {
	Seq      uint64                   `json:"seq"`
	Active   model.Active             `json:"active"`
	Entities map[string]*model.Entity `json:"entities"`
}

// NewRaw returns an empty fold.
func NewRaw() *Raw { return &Raw{Entities: map[string]*model.Entity{}} }

var patchKeys = map[string]bool{"parent_id": true, "session_id": true, "pid": true, "host": true,
	"cwd": true, "track": true, "branch": true, "alias": true, "model": true, "effort": true,
	"follow_active": true, "source": true, "state": true, "kind": true}

func applyPatch(e *model.Entity, p map[string]string) error {
	for k := range p {
		if !patchKeys[k] {
			return fmt.Errorf("unknown patch key %q", k)
		}
	}
	// validate before mutating
	if v, ok := p["state"]; ok && !model.ValidState(v) {
		return fmt.Errorf("invalid state %q", v)
	}
	if v, ok := p["kind"]; ok && !model.ValidKind(v) {
		return fmt.Errorf("invalid kind %q", v)
	}
	if v, ok := p["pid"]; ok {
		if _, err := strconv.Atoi(v); err != nil {
			return fmt.Errorf("invalid pid %q", v)
		}
	}
	if v, ok := p["follow_active"]; ok {
		if _, err := strconv.ParseBool(v); err != nil {
			return fmt.Errorf("invalid follow_active %q", v)
		}
	}
	for k, v := range p {
		switch k {
		case "parent_id":
			e.ParentID = v
		case "session_id":
			e.SessionID = v
		case "pid":
			e.PID, _ = strconv.Atoi(v)
		case "host":
			e.Host = v
		case "cwd":
			e.Cwd = v
		case "track":
			e.Track = v
		case "branch":
			e.Branch = v
		case "alias":
			e.Alias = v
		case "model":
			e.Model = v
		case "effort":
			e.Effort = v
		case "follow_active":
			e.FollowActive, _ = strconv.ParseBool(v)
		case "source":
			e.Source = v
		case "state":
			e.State = v
		case "kind":
			e.Kind = v
		}
	}
	return nil
}

// subtree returns the IDs of every entity belonging to the session entity
// sid: same non-empty session_id, plus every parent_id descendant.
func (r *Raw) subtree(sess *model.Entity) []string {
	in := map[string]bool{}
	for id, e := range r.Entities {
		if id != sess.ID && sess.SessionID != "" && e.SessionID == sess.SessionID {
			in[id] = true
		}
	}
	for changed := true; changed; {
		changed = false
		for id, e := range r.Entities {
			if id != sess.ID && !in[id] && e.ParentID != "" && (e.ParentID == sess.ID || in[e.ParentID]) {
				in[id] = true
				changed = true
			}
		}
	}
	ids := make([]string, 0, len(in))
	for id := range in {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}

// republish binds the whole subtree of a non-following session to that
// session's own alias/model/effort (SessionStart under a different alias).
func (r *Raw) republish(sess *model.Entity) {
	if sess.Kind != model.KindSession || sess.FollowActive || sess.Alias == "" {
		return
	}
	for _, id := range r.subtree(sess) {
		e := r.Entities[id]
		e.FollowActive = false
		e.Alias, e.Model, e.Effort = sess.Alias, sess.Model, sess.Effort
	}
}

// Apply folds one event into r. Pure: no I/O, no clock (ev.TS and ev.Seq are
// already assigned). On error r is unchanged.
func (r *Raw) Apply(ev model.Event) error {
	switch ev.Type {
	case model.EvRegister:
		if ev.Entity == nil || ev.Entity.ID == "" {
			return fmt.Errorf("register: entity with id required")
		}
		if !model.ValidKind(ev.Entity.Kind) {
			return fmt.Errorf("register: invalid kind %q", ev.Entity.Kind)
		}
		e := *ev.Entity
		if e.State == "" {
			e.State = model.StateRunning
		}
		if !model.ValidState(e.State) {
			return fmt.Errorf("register: invalid state %q", e.State)
		}
		e.Label, e.Stale = "", false
		e.UpdatedAt = ev.TS
		if old, ok := r.Entities[e.ID]; ok && e.StartedAt.IsZero() {
			e.StartedAt = old.StartedAt
		}
		if e.StartedAt.IsZero() {
			e.StartedAt = ev.TS
		}
		r.Entities[e.ID] = &e
		r.republish(&e)
	case model.EvUpdate:
		e, ok := r.Entities[ev.ID]
		if !ok {
			return fmt.Errorf("update: unknown id %q", ev.ID)
		}
		cp := *e
		if err := applyPatch(&cp, ev.Patch); err != nil {
			return err
		}
		cp.UpdatedAt = ev.TS
		*e = cp
		r.republish(e)
	case model.EvHeartbeat:
		e, ok := r.Entities[ev.ID]
		if !ok {
			return fmt.Errorf("heartbeat: unknown id %q", ev.ID)
		}
		cp := *e
		if err := applyPatch(&cp, ev.Patch); err != nil {
			return err
		}
		if _, set := ev.Patch["state"]; !set && cp.State == model.StateUnknown {
			cp.State = model.StateRunning
		}
		cp.UpdatedAt = ev.TS
		*e = cp
	case model.EvUnregister:
		e, ok := r.Entities[ev.ID]
		if !ok {
			return fmt.Errorf("unregister: unknown id %q", ev.ID)
		}
		e.State = model.StateDone
		e.UpdatedAt = ev.TS
	case model.EvAliasSwitch:
		if ev.Active == nil || ev.Active.Alias == "" {
			return fmt.Errorf("alias_switch: alias required")
		}
		r.Active = model.Active{Alias: ev.Active.Alias, Model: ev.Active.Model, Effort: ev.Active.Effort, SwitchedAt: ev.TS, Seq: ev.Seq}
	case model.EvReap:
		if _, ok := r.Entities[ev.ID]; !ok {
			return fmt.Errorf("reap: unknown id %q", ev.ID)
		}
		delete(r.Entities, ev.ID)
	case model.EvReconcile:
	default:
		return fmt.Errorf("unknown event type %q", ev.Type)
	}
	r.Seq = ev.Seq
	return nil
}

// resolveBinding returns the alias/model/effort an entity displays.
// RULE (CONTRACT.md §4): follow_active => the ACTIVE context; otherwise the
// entity's own alias triple if it has an alias; otherwise the nearest
// ancestor's own triple; otherwise unknown (empty -> '?').
func resolveBinding(r *Raw, e *model.Entity) (alias, mo, ef string) {
	if e.FollowActive { // MUT:follow
		return r.Active.Alias, r.Active.Model, r.Active.Effort
	}
	for cur, depth := e, 0; cur != nil && depth < 32; depth++ {
		if !cur.FollowActive && cur.Alias != "" {
			return cur.Alias, cur.Model, cur.Effort
		}
		if cur.ParentID == "" {
			break
		}
		cur = r.Entities[cur.ParentID]
	}
	return "", "", ""
}

// inheritedPlace returns track/branch, inherited from the nearest ancestor
// that has them when the entity does not.
func inheritedPlace(r *Raw, e *model.Entity) (track, branch string) {
	track, branch = e.Track, e.Branch
	for cur, depth := e, 0; depth < 32 && (track == "" || branch == ""); depth++ {
		if cur.ParentID == "" {
			break
		}
		cur = r.Entities[cur.ParentID]
		if cur == nil {
			break
		}
		if track == "" {
			track = cur.Track
		}
		if branch == "" {
			branch = cur.Branch
		}
	}
	return
}

// RenderOpts are the render-time inputs.
type RenderOpts struct {
	Now       time.Time
	Pids      PidTable
	TTL       time.Duration
	LocalHost string
}

// isStale implements the staleness rule: not done, older than TTL, and no
// provably-alive local process.
func isStale(e *model.Entity, o RenderOpts) bool {
	if e.State == model.StateDone {
		return false
	}
	age := o.Now.Sub(e.UpdatedAt)
	if !(age > o.TTL) { // MUT:ttl
		return false
	}
	local := e.Host == "" || e.Host == o.LocalHost
	if local && o.Pids != nil && o.Pids.Alive(e.PID) {
		return false
	}
	return true
}

// Render produces the consumer-facing snapshot from the declared state.
func Render(r *Raw, o RenderOpts) model.Snapshot {
	snap := model.Snapshot{Seq: r.Seq, GeneratedAt: o.Now, Active: r.Active, Entities: []model.Entity{}}
	for _, e := range r.Entities {
		out := *e
		a, m, f := resolveBinding(r, e)
		t, b := inheritedPlace(r, e)
		out.Alias, out.Model, out.Effort, out.Track, out.Branch = a, m, f, t, b
		if isStale(e, o) {
			out.Stale = true
			out.State = model.StateUnknown
		}
		out.Label = label.Compose(label.Fields{Track: t, Branch: b, Alias: a, Model: m, Effort: f})
		snap.Entities = append(snap.Entities, out)
	}
	sort.Slice(snap.Entities, func(i, j int) bool {
		if !snap.Entities[i].StartedAt.Equal(snap.Entities[j].StartedAt) {
			return snap.Entities[i].StartedAt.Before(snap.Entities[j].StartedAt)
		}
		return snap.Entities[i].ID < snap.Entities[j].ID
	})
	return snap
}
