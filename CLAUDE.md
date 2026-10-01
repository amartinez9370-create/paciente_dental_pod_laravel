# Paciente Dental POD: Laravel (Phase 2)

Laravel 13 port of a working Phase 1 system (hand-rolled PHP MVC) for a small dental clinic in Makati, Philippines. Phase 2 adds an EMR later, but this repo is currently at the Phase 1 port (chat 2.17).

**Read `docs/decisions.md` before planning any work.** Phase 1 reference files are in `docs/reference/`.

## Environment
- Windows, PowerShell. PHP 8.5.11, Laravel 13.34, MariaDB 10.4.32 from XAMPP.
- Serve with `php artisan serve`. Apache is not used. Only MariaDB runs from XAMPP.
- Database `dbPacienteDentalPodLaravel`, driver `mariadb`, user root with an empty password (local only).
- No starter kit and no Filament. Livewire and Alpine are added at the views step, not yet. Static pages and layouts are plain Blade.

## How to work
- Plan first. Propose the approach and wait for approval before creating or editing files. Use plan mode for each batch.
- One batch at a time. Stop at the batch boundary and report. The user's prompt names the current batch. Do not start the next one.
- Do not touch EMR tables or models in 2.17.
- Migrations are the source of truth. `php artisan migrate:fresh --seed` must pass on `main`.
- Report what you ran and what it printed. Never claim a check passed without running it.

## Database safety
- The only database you may touch is `dbPacienteDentalPodLaravel`. The Phase 1 database (`dbpacientedentalpod`) and every other schema on this server are off limits, including reads.
- Run `php artisan db:show` and read the `Database` line before any `migrate:fresh`, `migrate:rollback` or `db:seed`. Stop if it names anything else.
- Never run the `mysql` or `mysqldump` clients, raw `DROP` or `TRUNCATE`, or `db:wipe`. The app connects as root, so these rules are the main protection.
- Do not read, print or edit `.env`. Change `.env.example` instead and tell the user what to copy across.

## Git
- One branch per batch: `batch/2.17-<id>-<slug>`. Do not commit to `main` after Batch A.
- Commit messages are `type(scope): summary`. The body says why and cites the source, for example `Refs: docs/decisions.md section 3`.
- Ask before every commit. Never push, merge, tag, force-push or `reset --hard` unless asked. The user squash-merges and tags.
- Do not add or remove commit trailers by hand. Attribution follows the user's Claude Code settings.
- Never commit `.env`, database dumps, real patient data or images. Seed data is fake only.

## Code conventions
- Use "appointment request" and "assign" in new class, route, view and column names. Do not use "booking", and do not port Phase 1 names such as `BookingController`.
- Preserve Phase 1 column types, nullability, ENUMs, indexes and ON DELETE rules, except where `docs/decisions.md` section 2 says otherwise.
- Use raw `DB::statement` for `CHECK` constraints.
- Timezone is Asia/Manila. Currency is the peso: no decimals when whole, and "Free" for zero.
- Keep Eloquent models thin: relationships, casts, scopes and small accessors. Business logic goes in service classes. Declare `$fillable` explicitly, and never make `role` or `is_active` mass-assignable.
