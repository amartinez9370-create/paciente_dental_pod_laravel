# Migration Brief — Paciente Dental POD: Phase 1 (PHP-vanilla) → Phase 2 (Laravel)

> **Anchor document for the new Laravel project.** Read this first in any new chat before touching code. It explains what changed, why, what carries forward from Phase 1 (including the actual business rules, not just pointers to where they live), and what's being rebuilt. Phase 1's `Project_Summary.md` and `Project_Status_v1–v17.md` remain valid as deeper design-rationale history — treat their "current state" sections as describing the old PHP-vanilla implementation, not the current codebase, but consult them when this brief references a decision and you need the full discussion behind it.

---

## 1. Why this migration happened

Phase 1 (hand-rolled PHP MVC, no framework) satisfied the previous semester's requirement to demonstrate manual MVC mechanics — and did so well: a working, tested system with a full patient/dentist/admin flow, walk-in handling, dependents, email notifications, and cron-based reminders.

This semester and the next shift focus to **application and solution engineering** — addressing needs and problems with innovative solutions, with any tool and approach available. Decision: **migrate to Laravel.** Full reasoning and cited sources: ClickUp Research Log, rows **R038, R042, R043, R044**.

---

## 2. Business rules and architecture decisions carried forward

These are the actual decisions from 17 status docs — not just pointers to them. All still apply in Phase 2 unless explicitly marked otherwise.

### 2.1 Auth & identity
- **Unified login, role-based redirect.** All users authenticate at one login point; `users.role` (`patient`/`dentist`/`admin`) drives redirect: patient → dashboard, dentist → schedule, admin → dashboard.
- **Registration requires age ≥ 18**, validated both client-side and server-side. Minors cannot self-register — the guardian/dependent model (§2.2) is how minors get into the system.
- **Passwords:** bcrypt via `password_hash`/`password_verify` only. Session ID regenerated after login.
- **CSRF tokens were deliberately NOT built in Phase 1** — explicitly reasoned as "an advanced security topic appropriate for a production hardening phase, not a core student project requirement" (v2), but remained on the "pinned — before go-live" list through every status doc up to v17, and was never actually implemented. **In Laravel this is free** (built-in CSRF middleware) — treat as "just enable it," not a deferred decision.
- **RBAC / Staff role was designed but deliberately never built.** Discussed at length (v7): decision was to keep a single `admin` role for all of Phase 1. Future design (still valid, still not built): split `admin` into `admin` (full rights) and `staff` (appointment management only, no clinic settings/roster). The `staff` table already exists in the schema for this; `requireRole()` already accepts variadic roles. Worth actually building in Phase 2 given "any tool available."

### 2.2 Guardian / dependent model (fully built, v14–v16)
- **Architecture: "Option B"** — dependents get their own `patients` row with a self-referencing `guardian_patient_id` FK. No separate dependents table.
- Dashboard shows guardian + all dependents' appointments in one combined list, with a "For [First Name]" pill on dependent cards.
- Admin patient list always shows dependents, badged "Dependent · [Guardian Name]".
- Terminology is **"Dependents"** throughout the UI (not "Family Members") — a deliberate wording decision.
- Entry points: patient profile page, and Step 1 of the booking wizard ("Who is this appointment for?").
- `relationship` field (Child / Spouse-Partner / Parent / Sibling / Other) plus `medical_notes` reused for dependent special-needs notes (PWD accommodations, etc.).
- **Dependents 18+ can claim their own account** (same admin-mediated claim flow as walk-ins). **Dependents under 18 are explicitly blocked** from claiming — shown a blocked state with explanation instead of a claim form.
- Removing a dependent with upcoming appointments is blocked with a clear message; historical records are always preserved, never deleted.
- Guardian's real email is used for a dependent's appointment emails/reminders (dependent doesn't need their own email).
- DOB is required (not optional) on every dependent-creation surface — this was tightened after initially being optional.

### 2.3 Walk-in system (fully built, v9+)
- **Admin-only creation** — no patient self-service walk-in booking.
- Minimum required fields: first name, last name, phone. **Email is not required.**
- Sentinel email format: `walkin-{normalizedPhone}@pdp.internal` (and `walkin-dep-{...}@pdp.internal` for dependent walk-ins). Phone normalized to canonical `63XXXXXXXXXX` form consistently everywhere it's touched.
- **Multiple patients can intentionally share a phone number** — no unique constraint on `patients.phone` (family members, or a walk-in + online account existing before merge).
- Walk-in appointments are created with `status = 'confirmed'` immediately — they skip the `pending` state entirely.
- **Slot override was built, then deliberately removed entirely** (v10). Rationale, verbatim from the postmortem: *"override contradicted the system's core purpose of preventing double booking."* Admin must queue an unschedulable walk-in instead of force-booking over a taken slot. This is a real product decision — don't silently reintroduce an override in the Laravel version without re-raising it with the team.
- **Walk-in queue:** patients without a fixed slot wait and get served in the first gap between scheduled appointments. Signal: `source = 'walkin' AND start_time IS NULL`. Sort order (tuned over two iterations): `COALESCE(start_time, GREATEST(TIME(arrived_at), CURTIME()))` — queued cards slip below appointments whose scheduled time has already elapsed, on page refresh, with `arrived_at` as a tiebreaker for multiple simultaneously-queued patients.
- **Silent merge at self-registration:** if a patient self-registers with the same phone AND exact first+last name as an existing walk-in record, their appointment history transfers automatically and the walk-in shell is deleted. Merge failure is non-fatal — logged, registration proceeds anyway.
- **Admin-mediated claim** (separate flow from silent merge): admin sends a "Claim this account" email to a real address for an existing walk-in patient; patient sets a password via the same reset-password mechanism; full appointment history attaches to the new account.

### 2.4 Emergency flagging
- `is_emergency` boolean. Settable by admin at walk-in booking, or on **any appointment scheduled for today only** — enforced both in the controller (date check) and the view (conditional render), not just one layer.
- Dentist can also toggle it (peer review) — today's appointments only, same restriction.
- Visual priority: emergency red border overrides the queued-walk-in amber border (`!important` in CSS) — emergency status always wins visually.

### 2.5 Appointment status rules
- State machine: `pending → confirmed → completed`; `pending → cancelled/declined`; `confirmed → cancelled/completed/no_show`.
- **Once completed, cancelled, or declined, no further status changes are possible** — this is an explicit, documented rule, not just an implementation detail.
- **Reasons are required** (not optional) for patient cancellation and dentist decline.
- Clinical notes are captured separately from patient-facing notes, written by the dentist (or admin) at completion time.
- Audit trail (`confirmed_by_user_id`, `cancelled_by_user_id`, `completed_by_user_id`) is silent — tracked in the DB, never surfaced in the UI.
- **Admin can also mark appointments completed** (`completeByAdmin()`, added later) — not exclusively a dentist action.
- **Schedule-conflict detection:** when clinic hours or a dentist's availability changes, `getConflictingAppointments()` flags existing appointments that now fall outside the new window. These are surfaced as a warning + distinct card styling — **never auto-cancelled**. Admin/dentist must manually review and act.

### 2.6 Reschedule policy
- **Deliberately not a distinct flow.** "Cancel + rebook" is the only path, consistently through every status doc through v17. Documented explicitly in the system doc: *"Direct rescheduling is not available in Phase 1."* Treat as still-Phase-1 status unless the team explicitly decides to build it in Phase 2.

### 2.7 Service / slot / conflict-detection history
- The system briefly moved to fixed clinic-wide 30-minute slots (dropping per-service duration entirely) in an earlier snapshot, on the stated basis that "duration is irrelevant to patients." **This was later reversed** — per-service `duration_minutes` and range-overlap conflict detection came back and are the current, final state (confirmed directly in the code). No action needed here — just know the history if an old doc's description of "fixed 30-min slots" seems to contradict the schema.
- `online_bookable = 0` services (e.g., Dental X-ray) are catalog/walk-in-only — hidden from the patient-facing wizard.
- No buffer time between appointments — the dentist confirmed service durations are already generous; a `buffer_minutes` column was added speculatively, then removed.
- Slot interval, booking lead time, and booking window are clinic-configurable via the admin UI (`clinics.slot_interval`, `booking_lead_minutes`, `booking_window_days`) — not hardcoded, replacing original hardcoded values.

### 2.8 Notification matrix (stakeholder-confirmed, v5 — treat as a business requirement, not an implementation detail)

| Trigger | Patient | Dentist | Admin |
|---|---|---|---|
| Booking submitted | ✓ | ✓ | — |
| Dentist confirms | ✓ | — | — |
| Dentist declines | ✓ | — | ✓ |
| Patient cancels | — | ✓ | ✓ |
| Admin cancels | ✓ | ✓ | — |
| 24h reminder | ✓ | — | — |
| Daily digest (9 AM) | — | — | ✓ |

Admin receives **exception-only** notifications (declines, patient cancellations) — not routine events. Dentist deliberately does **not** get the daily digest — their dashboard is considered sufficient.

### 2.9 Currency, timezone, locale conventions
- Philippine peso (₱), **no decimals shown for whole amounts** ("₱1,200" not "₱1,200.00"). "Free" is shown instead of "₱0" when price is zero.
- Timezone: Asia/Manila, no DST handling needed (Philippines doesn't observe DST).
- Age display: "42 yrs"; yellow "Minor" badge under 18; blue "Senior" badge at 60+ (corrected down from an initial 70 threshold).

### 2.10 Booking wizard / UX conventions (Project_Summary §11 — still the reference for whatever replaces the wizard)
- Stepper at the top, with labels — patients (often anxious) want to see the full path ahead.
- No "Step X of 4" eyebrow text — the page title alone communicates position.
- No "Edit" links on the review step — the Back button handles backward navigation.
- **No policy checkbox** — replaced with clickwrap text below the Confirm button ("By confirming, you agree to the cancellation policy"), deemed legally defensible without the extra UI friction of a checkbox.
- No "Cancel booking" link — patients use the browser back button.
- **Slot-taken conflicts show an inline alert, never a modal** — deliberately kept simple.
- Steps are not clickable to skip ahead — only the Back button allows revisiting a prior step.

### 2.11 Reports
- Built: a printable/filterable admin appointment report (filter criteria + aggregate counts + full appointment table), using the browser's native "Print / Save as PDF." Advanced analytics is explicitly out of scope through v17 — revisit given the new "solution engineering, any tool available" mandate if the team wants to build it out properly in Phase 2.

---

## 3. Two items to explicitly revisit (not silently fix, not silently port)

**These were previously mischaracterized as bugs in an earlier draft of this brief — they were deliberate Phase 1 decisions, not oversights. Revisit them with the team, don't just "fix" them unilaterally.**

1. **No transaction/row-locking on slot conflict checks.** Original Phase 1 plan called for `SELECT ... FOR UPDATE` inside a transaction (Project_Summary.md §"Conflict prevention"). This was **deliberately removed** in v2, with the documented reasoning: *"the race condition being guarded against is functionally impossible at this clinic's scale (one dentist, 5–10 patients/day)... the slot is still validated before insert, just without row-level locking."* Worth revisiting now because: (a) Laravel makes `DB::transaction()` + `lockForUpdate()` a few lines, not a hard problem; (b) the schema's multi-clinic/multi-dentist readiness means the "impossible at this scale" assumption may not hold if the system ever grows; (c) it's a reasonable "solution engineering" improvement to demonstrate. **Decide with the team — don't just add it back unilaterally without discussion**, since removing it was a considered choice, not a mistake.

2. **Reference codes use a random suffix, not the deterministic scheme the schema comments describe.** Unlike item 1, no explicit discussion of *why* the random suffix was chosen was found in the status docs — this looks like implementation drift rather than a deliberate decision. Track under Research Log **R039**; decide during migration whether to keep the random-suffix approach or implement true determinism.

---

## 4. What carries forward unchanged (reference material)

| Artifact | Status |
|---|---|
| `schema.sql` | Starting point for Laravel migrations + Eloquent models. |
| DFDs (`DFD__Level_0/1/2`, corrected Level-1) | Describe system behavior — still accurate. Level-1 correction history: Process 1.0 renamed "Authenticate User" (was implying patient-only auth), D1 renamed "User Records" (was "Patient Records" but holds all roles), added flow `3.0 → D1` for admin-created dentist/staff accounts. |
| `Dental_Clinic_Interview_Script.docx`, `Advance_Questions.docx` | Stakeholder requirements — unchanged. |
| `PDP_Appointment_System_Documentation_v2.docx` | Functional scope, target users, Phase boundaries — still accurate. |
| RRL Research Brief + Research Log (ClickUp) | Academic + architecture-decision grounding — unchanged, now also holds R038–R044. |
| `Project_Summary.md`, `Project_Status_v1–v17.md` | Kept for deeper design-rationale and bug-postmortem detail beyond what §2 of this brief summarizes. |
| `booking_wizard_mockup_v2.html` | Visual/UX reference — still canonical. |

---

## 5. What's being rebuilt

| Layer | Phase 1 (old) | Phase 2 (new) |
|---|---|---|
| Framework | None — hand-rolled | Laravel |
| Routing | Flat `$routes` array in `App.php` | Laravel route files (`web.php`) |
| Data access | Raw PDO, hand-written SQL | Eloquent ORM |
| Frontend reactivity | Vanilla JS + manual `fetch()` AJAX | Livewire + Alpine.js |
| Views | `Controller::view()` + `layout.php` | Blade + Livewire components |
| Auth | Hand-rolled `requireRole()` | Laravel auth scaffolding + role middleware |
| Admin panel | Hand-built `AdminController` (1,501 lines) | **Full Livewire, no Filament** — see §6 |
| Mail | Custom `Mailer` + PHPMailer + 15 hand-written templates | Laravel Mailables + Blade mail templates |
| Scheduled jobs | `cron/reminder.php`, `cron/digest.php` | Laravel Task Scheduling |
| CSS | Custom design system (`styles.css`) | Unchanged for now — see §7 |

---

## 6. Admin panel: full Livewire, no Filament

Considered Filament, rejected in favor of hand-built Livewire — full reasoning in Research Log **R043**. Summary: the team weighed uniformity and full ownership over Filament's raw speed advantage, and analysis of the actual `AdminController` showed only **Services** is genuinely vanilla CRUD — Dentists (bundled account creation), Patients (nested dependents), and Appointments (workflow-action-driven, not field-edit) each have a distinct shape.

**Build approach:** Services first (bespoke), then Dentists; extract a shared search/sort/filter/paginate table-shell component *after* both exist, based on real overlap. Create/edit forms stay separate per entity. Appointments stays a filtered list + action buttons, never a CRUD form.

---

## 7. CSS / Tailwind — deferred decision

Keeping the existing `styles.css` design system as-is for now — it was already deliberately tuned to a "Tier 2" quality bar. Revisit **after** the Livewire component structure stabilizes; Tailwind v4's CSS cascade layers make component-by-component adoption viable later without a big-bang rewrite.

---

## 8. Migration sequencing plan

0. **EMR entity-boundary checkpoint — before any migration file is written.** A short, dedicated planning pass (a napkin ERD is enough) deciding *where clinical data will eventually attach* — e.g., does it live on a separate table keyed to `patient_id`, `appointment_id`, or both; is a treatment plan its own entity spanning multiple visits — even though the *build* of that table waits for Research Log R013/R015/R016 to be answered. Goal: don't reproduce Phase 1's `medical_notes` catch-all-text anti-pattern by finalizing `Patient`/`Appointment` models with zero thought toward where EMR eventually attaches. Cheap to decide now, expensive to redo once 2.x is built on the wrong boundary. See `Development_Roadmap.md` Phase B for the full version of this step.
1. **Migration Brief (this doc) + database layer** — Laravel migrations from `schema.sql`, Eloquent models, informed by step 0's boundary decision. Decide on §3's two items here.
2. **Auth & core scaffolding** — Laravel auth, role middleware. Consider building the RBAC/staff-role split (§2.1) now that it's finally in scope.
3. **Booking wizard** — first Livewire component; maps closely to Livewire's server-owned-state model. Preserve the UX conventions in §2.10.
4. **Patient portal** — dashboard, profile, dependents (§2.2), cancel flow.
5. **Dentist portal** — schedule view, status actions (§2.5), availability management.
6. **Admin suite**, in order: Services → Dentists → *(extract shared table shell)* → Patients+Dependents → Appointments → walk-in flow (§2.3) → clinic-hours editor → walk-in-to-patient claim/merge.
7. **Mail layer** — Mailables + Blade mail templates, preserving the notification matrix in §2.8; Task Scheduling replacing the two cron scripts.
8. **Enable CSRF** (§2.1) — essentially free in Laravel, no reason to defer it the way Phase 1 did.

---

## 9. Open questions for the team

- **New project folder name** — suggested `paciente_dental_pod_laravel`, to be confirmed.
- **§3, item 1** (transaction locking) — explicit team decision needed, not a default.
- **§3, item 2** (reference code determinism) — explicit team decision needed.
- **RBAC/staff role** (§2.1) — build it in Phase 2, or continue deferring?
- **Reschedule flow** (§2.6) and **advanced reporting** (§2.11) — both explicitly out of Phase 1 scope; worth a deliberate in/out decision for Phase 2 given the new "any tool, any approach" mandate.

**Resolved:**
- **Version control** — git is the documented, team-facing method for Phase 2. Zip snapshots continue as a personal local backup for one team member only, never referenced in shared documentation or handoffs.
- **Local dev environment** — XAMPP, continuing from Phase 1. Chosen deliberately over Sail/Herd, for continuity and timeline protection: the team already has it installed and knows it, avoiding a new tool on top of an already-heavy migration (Laravel, Livewire, new admin architecture all at once) during a semester with no real slack left to spend on tooling detours. **Not because of database portability** — a MySQL database moves between any hosting environment (XAMPP, Docker/Sail, anything) via a standard export/import; that was never a real cost of switching. The schema rebuild into Laravel migrations (Phase C) happens regardless of which local server hosts MySQL — it's driven by moving from raw PDO to Eloquent, not by this tooling choice. Two real risks to check during Phase C, not assume away:
  1. **PHP version compatibility** — Laravel 13 (current as of March 2026) requires PHP 8.3 minimum. Verify the existing XAMPP install's bundled PHP version actually meets this before building on it; upgrade XAMPP itself if it doesn't, not just tweak config.
  2. **Windows performance tuning** — Laravel on XAMPP under Windows has documented file-system and Apache-config overhead. Known, fixable (OPcache setup, excluding the project folder from antivirus real-time scanning) — worth applying proactively rather than discovering it as an unexplained slowdown later.

---

## 10. How to resume in a new chat

1. Attach: this `Migration_Brief.md`, `schema.sql`, and the Phase 1 project zip.
2. Open with: *"We're migrating Paciente Dental POD from hand-rolled PHP MVC to Laravel. Read Migration_Brief.md first — section 2 has the actual business rules and section 3 has two decisions that need explicit team input before proceeding. Then we'll pick up at [step from §8]."*
3. Research Log rows R038–R044 (ClickUp) hold the full cited reasoning behind the Phase 2 stack decisions — consult before revisiting any of them.
