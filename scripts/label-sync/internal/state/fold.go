package state

import (
	"fmt"
	"sort"
	"strconv"
	"time"

	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/label"
	"github.com/HelixDevelopment/HelixConstitution/scripts/label-sync/internal/model"
)

// PidTable answers whether a LOCAL process is the one that was registered
// (fakeable in tests). Start returns an opaque start identity for pid ("" when
// it cannot be read); Alive(pid, start) is true only when the process exists
// AND, if start is non-empty, it is the SAME process (pid-reuse guard).
type PidTable interface {
	Alive(pid int, start string) bool
	Start(pid int) string
}

// logIndex locates the fold inside events.jsonl so readers parse only the
// events appended after it (review finding 5). It is persisted in fold.json
// only; it is not part of the logical state and is excluded from Verify's
// comparison.
type logIndex struct {
	Ino     uint64 `json:"ino"`      // inode of events.jsonl the offset refers to
	Off     int64  `json:"off"`      // byte offset just past the last folded event
	Events  int    `json:"events"`   // events physically in events.jsonl
	BaseSeq uint64 `json:"base_seq"` // seq of base.json (0 = no compaction yet)
}

// Raw is the folded (declared) state: what the events say, before render-time
// computation (label, staleness, binding). Persisted as fold.json (internal)
// and, at compaction, as base.json (authoritative base of the log).
type Raw struct {
	Seq      uint64                   `json:"seq"`
	Active   model.Active             `json:"active"`
	Entities map[string]*model.Entity `json:"entities"`
	Index    logIndex                 `json:"index"`
}

// NewRaw returns an empty fold.
func NewRaw() *Raw { return &Raw{Entities: map[string]*model.Entity{}} }

var patchKeys = map[string]bool{"parent_id": true, "session_id": true, "pid": true, "pid_start": true, "host": true,
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
	if v, ok := p["pid"]; ok && v != "" {
		if n, err := strconv.Atoi(v); err != nil || n < 0 {
			return fmt.Errorf("invalid pid %q", v)
		}
	}
	if v, ok := p["follow_active"]; ok {
		if _, err := strconv.ParseBool(v); err != nil {
			return fmt.Errorf("invalid follow_active %q", v)
		}
	}
	for _, k := range []string{"parent_id", "session_id"} {
		if v, ok := p[k]; ok && v != "" && !label.ValidID(v) {
			return fmt.Errorf("invalid %s %q", k, v)
		}
	}
	for k, v := range p {
		switch k {
		case "parent_id":
			e.ParentID = v
		case "session_id":
			e.SessionID = v
		case "pid":
			e.PID, _ = strconv.Atoi(v) // "" clears to 0
		case "pid_start":
			e.PIDStart = v
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

// Apply folds one event into r. Pure: no I/O, no clock (ev.TS and ev.Seq are
// already assigned). On error r is unchanged. Binding is NOT copied anywhere
// here: it is derived at render time (resolveBinding).
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
		e.Label, e.Stale, e.Binding = "", false, ""
		e.UpdatedAt = ev.TS
		if old, ok := r.Entities[e.ID]; ok && e.StartedAt.IsZero() { // MUT:startedat
			e.StartedAt = old.StartedAt
		}
		if e.StartedAt.IsZero() {
			e.StartedAt = ev.TS
		}
		r.Entities[e.ID] = &e
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
	case model.EvHeartbeat:
		e, ok := r.Entities[ev.ID]
		if !ok {
			return fmt.Errorf("heartbeat: unknown id %q", ev.ID)
		}
		cp := *e
		if err := applyPatch(&cp, ev.Patch); err != nil {
			return err
		}
		if _, set := ev.Patch["state"]; !set && cp.State == model.StateUnknown { // MUT:hbrevive
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

// maxDepth bounds every ancestor walk (cycles in parent_id are tolerated).
const maxDepth = 32

// resolver answers ancestry questions for one render pass in O(1) per hop.
type resolver struct {
	r        *Raw
	sessions map[string]*model.Entity // session_id -> its kind=session entity
}

func newResolver(r *Raw) *resolver {
	rv := &resolver{r: r, sessions: map[string]*model.Entity{}}
	for _, e := range r.Entities {
		if e.Kind != model.KindSession || e.SessionID == "" {
			continue
		}
		if cur, ok := rv.sessions[e.SessionID]; !ok || e.ID < cur.ID { // deterministic tie-break
			rv.sessions[e.SessionID] = e
		}
	}
	return rv
}

// parent is the nearest ancestor of e: its parent_id entity when present,
// else (for non-session entities) the session entity sharing its session_id.
func (rv *resolver) parent(e *model.Entity) *model.Entity {
	if e.ParentID != "" {
		if p, ok := rv.r.Entities[e.ParentID]; ok && p != e {
			return p
		}
	}
	if e.SessionID != "" && e.Kind != model.KindSession {
		if p, ok := rv.sessions[e.SessionID]; ok && p != e {
			return p
		}
	}
	return nil
}

// pinned: the entity carries its own process-bound binding.
func pinned(e *model.Entity) bool { return !e.FollowActive && e.Alias != "" } // MUT:pinned

// resolveBinding returns the alias/model/effort an entity displays and where
// it came from. RULE (CONTRACT.md §4.2), evaluated at render time:
//  1. pinned (follow_active=false AND own alias) -> its own triple;
//  2. else the nearest ancestor's binding, resolved by this same rule;
//  3. a ROOT (no ancestor) that follows -> the ACTIVE context;
//  4. a root that neither follows nor has an alias -> unknown ('?').
//
// So a child of a pinned session shows the session's alias, a child of a
// following session follows active THROUGH the session, and changing the
// session's binding changes every descendant with no write to them.
func (rv *resolver) resolveBinding(e *model.Entity) (alias, mo, ef, src string) {
	seen := map[*model.Entity]bool{}
	for cur, depth := e, 0; cur != nil && depth < maxDepth && !seen[cur]; depth++ { // MUT:bdepth
		seen[cur] = true
		if pinned(cur) {
			src = "own"
			if cur != e {
				src = "inherited:" + cur.ID
			}
			return cur.Alias, cur.Model, cur.Effort, src
		}
		p := rv.parent(cur)
		if p == nil {
			if cur.FollowActive { // MUT:follow
				return rv.r.Active.Alias, rv.r.Active.Model, rv.r.Active.Effort, "active"
			}
			break
		}
		cur = p
	}
	return "", "", "", "unknown"
}

// inheritedPlace returns track/branch, inherited from the nearest ancestor
// that has them when the entity does not.
func (rv *resolver) inheritedPlace(e *model.Entity) (track, branch string) {
	track, branch = e.Track, e.Branch
	seen := map[*model.Entity]bool{e: true}
	for cur, depth := e, 0; depth < maxDepth && (track == "" || branch == ""); depth++ { // MUT:pdepth
		cur = rv.parent(cur)
		if cur == nil || seen[cur] {
			break
		}
		seen[cur] = true
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
// provably-alive local process (same pid AND same start identity).
func isStale(e *model.Entity, o RenderOpts) bool {
	if e.State == model.StateDone {
		return false
	}
	age := o.Now.Sub(e.UpdatedAt)
	if !(age > o.TTL) { // MUT:ttl
		return false
	}
	local := e.Host == "" || e.Host == o.LocalHost
	if local && e.PID > 0 && o.Pids != nil && o.Pids.Alive(e.PID, e.PIDStart) {
		return false
	}
	return true
}

// sanitiseOut makes every free-text field of a rendered entity safe to print
// (defence in depth: writers already sanitise, but old logs may not be).
func sanitiseOut(e *model.Entity) {
	for _, f := range []*string{&e.Host, &e.Track, &e.Branch, &e.Alias, &e.Model, &e.Effort, &e.Source, &e.PIDStart} {
		*f = label.Clean(*f, label.MaxFieldRunes)
	}
	e.Cwd = label.Clean(e.Cwd, maxCwdRunes)
	for _, f := range []*string{&e.ID, &e.ParentID, &e.SessionID} {
		if *f != "" && !label.ValidID(*f) {
			*f = label.Clean(*f, 160)
		}
	}
}

// Render produces the consumer-facing snapshot from the declared state.
func Render(r *Raw, o RenderOpts) model.Snapshot {
	rv := newResolver(r)
	act := r.Active
	act.Alias, act.Model, act.Effort = label.Clean(act.Alias, label.MaxFieldRunes), label.Clean(act.Model, label.MaxFieldRunes), label.Clean(act.Effort, label.MaxFieldRunes)
	snap := model.Snapshot{Seq: r.Seq, GeneratedAt: o.Now, Active: act, Entities: make([]model.Entity, 0, len(r.Entities))}
	for _, e := range r.Entities {
		out := *e
		a, m, f, src := rv.resolveBinding(e)
		t, b := rv.inheritedPlace(e)
		out.Alias, out.Model, out.Effort, out.Track, out.Branch, out.Binding = a, m, f, t, b, src
		if isStale(e, o) {
			out.Stale = true
			out.State = model.StateUnknown
		}
		sanitiseOut(&out)
		out.Label = label.Compose(label.Fields{Track: out.Track, Branch: out.Branch, Alias: out.Alias, Model: out.Model, Effort: out.Effort})
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
