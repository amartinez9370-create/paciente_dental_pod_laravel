# Locked decisions

Status as of chat 2.17, after Batch A (tag `2.17-A`). These come from the Phase B handoff (chat 2.16), the Migration Brief, the D.0 scheduling revision, and decisions made in chat 2.17. If a task seems to need a change to anything here, stop and tell the user. Do not change it silently.

Reference copies of the Phase 1 files are in `docs/reference/` (`schema.sql`, `Migration_Brief.md`). `schema.sql` is the starting point for migrations, but its comments are partly stale (see section 2).

## 1. Stack and environment

- Laravel 13, PHP 8.3 to 8.5 supported (local is 8.5.11), MariaDB 10.4.32, Livewire and Alpine later, plain Blade for static pages, layouts and the print report. No Filament, no starter kit.
- The admin panel is fully hand-built Livewire. Interactive screens (request wizard, admin tables, walk-in flow, dependents) are Livewire. Email templates are Blade mailables. Small UI touches are Alpine.
- The local database is `dbPacienteDentalPodLaravel`. Phase 1's `dbpacientedentalpod` must survive for parity testing.
- The app connects as `root` with an empty password (local only). A dedicated database user was considered and declined. Root can reach every schema on this server, so the database safety rules in `CLAUDE.md` are the main protection. The Phase 1 database was backed up (a copy of the server data folder and an `.sql` export) before B1.
- The project folder is `C:\dev\paciente_dental_pod_laravel`, outside XAMPP's `htdocs`, so Apache can run for phpMyAdmin without exposing the project. The app is served with `php artisan serve`, not Apache.
- The `mariadb` connection sets the session time zone to `+08:00` (`config/database.php`), so database-generated timestamps match the app's Asia/Manila time.

## 2. Database and migrations (Batch B1)

- Fresh, migration-driven database. Seeders replace the `INSERT` block in `schema.sql`.
- Primary and foreign keys use Laravel's default `BIGINT UNSIGNED`, not `INT UNSIGNED`. Preserve everything else: nullability, ENUMs, indexes, and ON DELETE and ON UPDATE rules.
- `users.password_hash` is renamed to `users.password`.
- `users.role` is `ENUM('patient','dentist','staff','admin')`. Add `staff` in the first migration.
- Timestamps on clinics, users, patients, dentists, staff and services: `DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP` for `created_at` and the same plus `ON UPDATE CURRENT_TIMESTAMP` for `updated_at` (`$table->dateTime(...)->useCurrent()` / `->useCurrentOnUpdate()`), not Laravel's `timestamps()`. This matches Phase 1's `created_at` type and nullability exactly and avoids `TIMESTAMP`'s 2038 limit and session-time-zone conversion. `created_at` only on `password_resets`, same DATETIME style. No timestamps on `clinic_hours`, `dentist_schedules` and `dentist_services`.
- `CHECK` constraints are kept, using raw statements.
- Skeleton migrations: replace the skeleton `users` migration. It also creates `password_reset_tokens` and `sessions`: drop the first, and keep `sessions` as its own migration. Keep the skeleton `cache` and `jobs` migrations. Keep the custom `password_resets` table (`token_hash`, `expires_at`, `used_at`), because the walk-in claim flow needs it.
- Phase 1 had no `remember_token` or `email_verified_at`. **Resolved:** add `remember_token` only, so a "Remember me" login can work later. No `email_verified_at` — walk-in sentinel emails (section 9) can't be verified, and Phase 1 had no verification flow. This also resolves the section 10 open item of the same name.
- The stock skeleton assumes a `users.name` column. Our `users` table has none, because names live on the profile tables. The skeleton's `User` model lists `name` as fillable. Check `UserFactory` and `DatabaseSeeder` as well, since the stock versions use `name` and create a test user. Replace all three in B1, or `migrate:fresh --seed` fails. Use the `#[Fillable]` attribute with only columns that exist, never `role` or `is_active`.
- Seeders: always load reference data (clinic, clinic hours, services). Load demo accounts only in the local and testing environments (an allowlist, enforced inside `DemoDataSeeder` as well as `DatabaseSeeder`), hashed with `Hash::make`. Demo accounts are the four Phase 1 users plus one demo staff account. Dentist profiles, their schedules and their service links belong to the demo seeder, because production dentists are created in the admin UI. Keep the Phase 1 ids (users 1 to 4) and add the staff user after them. The demo staff account (user 5, staff profile id 2) is `staff@pdp.com` / `staff123`, "Demo Staff", job title "Front Desk". **Exception to "seed data is fake only" (CLAUDE.md):** the demo patient (user 4 / patient 1, Angeles Martinez Jr.) keeps the real Phase 1 contact details — email, phone, DOB — at the project owner's request, for testing notifications end-to-end. The same details are already in `docs/reference/schema.sql`. Replace both before this repository is shared beyond the project owner, and rewrite Git history or publish from a fresh repository, because earlier commits keep the old details.
- Stale `schema.sql` comments to fix, not copy: the reference code is not deterministic (section 5), the slot lock is not at booking (section 4), and `staff` holds profiles for the admin and staff roles. Skip the trailing "snapshot 45 to 46" migration block. It is already folded into the base `services` table and seed.
- Creation order for B1: `clinics`, `clinic_hours`, `users`, `patients` (self-referencing guardian FK), `dentists`, `staff`, `services`, `dentist_services`, `dentist_schedules`, `password_resets`. The `appointments` table is B2.

## 3. Appointment model: request then assign (Batch B2)

Patients do not choose their own time. A patient submits an appointment request. The dentist, staff or admin assigns the date, time and dentist. This replaces patient self-selection entirely (manuscript chats D.0 onward).

- **D1.** Requests live in the existing `appointments` table. Date and time are nullable until assigned. Preference columns are added. Status `requested` replaces `pending`. A `CHECK` requires a date on confirmed rows. Walk-in queue rows (confirmed, `source = 'walkin'`, no start time) stay distinguishable by status and source.
- **D2.** The reference code is generated at assignment. `reference_code` is nullable until then, and an unassigned request shows its row id.
- **D3.** The patient names a dentist or chooses **No preference**. Admin and staff assign any request and may assign a different dentist from the one requested. A patient who cannot make the assigned time cancels and requests again.
- **D4.** Overlap at assignment is a hard block for the same dentist, under the lock in section 4. There is no override.
- **Status flow:** `requested` then `confirmed`, `completed`, `no_show`, `cancelled` or `declined`. After `completed`, `cancelled` or `declined`, no further changes.
- **Proposed columns, not yet confirmed (settle in the B2 plan):** `requested_dentist_id` (nullable, NULL means no preference), `dentist_id` (nullable until assigned, set at creation for walk-ins), and a `CHECK` requiring a date and a dentist for confirmed, completed and no-show rows.
- No reschedule flow. Patients cancel and request again.

## 4. Concurrency

- Lock the dentist's row inside a transaction (`lockForUpdate()`), with Laravel's retry-on-deadlock as a backup.
- The lock is taken by every path that sets a date and time: assignment, walk-in creation, and the walk-in claim flow. It is taken on the dentist being assigned to, including when staff change the dentist.
- Creating a request takes no lock, because it claims nothing.
- Phase 1 had no lock. Removing it in v2 was deliberate. Reinstating it is a Phase 2 decision.

## 5. Reference code

- Format `APT-YYYYMMDD-HHMM-CCDD-XXX`. Date and time are the appointment's, CC is the clinic id, DD is the dentist id (each zero-padded to 2 digits), and XXX is a 3-character random suffix.
- Uniqueness comes from the unique index on `reference_code`. Catch the unique violation, regenerate the suffix and retry a small fixed number of times, inside the same locked transaction.
- It is not deterministic. Do not call it "semi-deterministic".

## 6. Roles and access

- Four roles: patient, dentist, staff, admin. `users.role` is the access identity. `staff.job_title` is display only.
- Role middleware on route groups (`role:admin,staff` for shared routes, `role:admin` for admin-only), Policies and Gates for ownership, and a middleware that re-checks `users.is_active` on every request.
- Staff can do everything admin can except: patient deactivation and reactivation, clinic hours and booking settings, the services catalog, the dentist roster, and staff accounts. Staff access to EMR data is payments only.
- A patient's allowed set is themselves plus their dependents (`guardian_patient_id`).
- A dentist assigns only to themselves, for requests that name them or have no preference. Admin and staff assign to any dentist.
- Admin and staff both receive the admin emails (exception emails and the daily digest). Recipients are all active users with role admin or staff, replacing the single address in Phase 1's mail config.
- CSRF protection stays on. Keep `@csrf` in every Blade form, and check that Livewire and any custom fetch calls send the token.

## 7. Retention (applies when the EMR is added)

- `ON DELETE RESTRICT` on every clinical table's `patient_id`. Patients are deactivated, never hard-deleted. Do not add EMR tables in 2.17.

## 8. Scope

- Reschedule is out of scope. The only report is the printable admin appointment report (filters: status, dentist, date). Payment tracking is in scope for the EMR and payment processing is not.

## 9. Phase 1 business rules to carry forward (full text in `docs/reference/Migration_Brief.md`)

- Registration requires age 18 or over. Minors enter through the guardian and dependent model (dependents are `patients` rows with `guardian_patient_id`).
- Walk-ins need first name, last name and phone, not email. Sentinel email is `walkin-{normalizedPhone}@pdp.internal`. Phones normalize to `63XXXXXXXXXX`. There is no unique constraint on `patients.phone`.
- Walk-in appointments are confirmed immediately. A queued walk-in has no start time. The Phase 1 slot override was removed on purpose and must not return.
- `is_emergency` can be set only on appointments scheduled for today.
- Services have `duration_minutes`. There is no buffer time. `online_bookable = 0` services are hidden from patients.
- Schedule changes that create conflicts are flagged and never auto-cancelled.
- Currency is the peso with no decimals when whole, and "Free" for zero. Timezone is Asia/Manila.

## 10. Open items (do not decide these silently)

- Notification matrix rows for request submitted and time assigned.
- What `booking_lead_minutes` and `booking_window_days` mean for requests.
- The request wizard screens, including the No preference option.
- ~~Whether to add `remember_token` and `email_verified_at` (section 2).~~ Resolved in B1: `remember_token` only.
- Production admin account creation (no demo passwords in production).

## 11. Batch B1 acceptance checklist

1. Ten tables exist (all Phase 1 tables except `appointments`). Skeleton `sessions`, `cache` and `jobs` still exist.
2. `php artisan migrate:fresh --seed` passes on a clean database.
3. `SHOW CREATE TABLE` output matches `schema.sql` for every table, except the documented changes in section 2.
4. Foreign key actions are preserved (for example `patients.guardian_patient_id` is RESTRICT and `dentists.user_id` is CASCADE).
5. Each `CHECK` constraint rejects a bad row. Show the attempt and the error.
6. `users.role` includes `staff` and the column is named `password`.
7. Demo accounts load only in local and testing. Passwords are hashed with `Hash::make`.
8. No `appointments` table and no EMR tables exist.
