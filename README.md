# Paciente Dental POD

Appointment request and scheduling system for a small dental clinic in Makati, Philippines. Patients submit an appointment request, and the clinic (dentist, staff or admin) assigns the date, time and dentist. This repository is the Laravel 13 port of the Phase 1 system, which was written in plain PHP.

## Status

Porting Phase 1: database migrations and seeders, then models, routes and views. The electronic medical record (EMR) is planned after the port and is not part of this repository yet.

## Stack

| Layer | Choice |
|---|---|
| Framework | Laravel 13 (PHP 8.3 or newer; developed on 8.5) |
| Database | MariaDB 10.4 (XAMPP) |
| Views | Blade for static pages, layouts and print views. Livewire for interactive screens and Alpine for small UI touches (planned) |
| Assets | Vite |

## Requirements

- PHP 8.3 or newer with these extensions enabled: `bcmath`, `ctype`, `curl`, `dom`, `fileinfo`, `mbstring`, `openssl`, `pdo_mysql`, `tokenizer`, `xml`, `zip`. Tests also need `pdo_sqlite` and `sqlite3`.
- Composer 2
- Node.js and npm, for the asset build
- MariaDB or MySQL running locally (XAMPP is fine)

## Local setup

```
git clone <repository-url>
cd paciente_dental_pod_laravel
composer install
```

Copy `.env.example` to `.env` (in PowerShell: `Copy-Item .env.example .env`), then:

```
php artisan key:generate
```

Create an empty database named `dbPacienteDentalPodLaravel` with character set `utf8mb4` and collation `utf8mb4_unicode_ci`. The connection values in `.env.example` match a default XAMPP install, so adjust the username and password in `.env` only if yours differ.

Once the migrations are in (batch B1), build the schema and load the seed data:

```
php artisan migrate:fresh --seed
```

When the views are in place, build the assets:

```
npm install
npm run build
```

Start the app:

```
php artisan serve
```

It runs at http://localhost:8000.

**Notes**
- Serve the app with `php artisan serve`. Only the `public/` folder should ever be reachable from a web server. If the project sits under XAMPP's `htdocs`, keep Apache stopped, because it would expose `.env` and `vendor/`.
- Demo accounts are seeded only outside production, with fake data. Do not enter real patient data into a development database.

## Tests

```
php artisan test
```

The default tests run against in-memory SQLite. Tests for row locking will need MariaDB and will be added with the booking logic.

## Repository guide

- `docs/decisions.md` records the locked design decisions and conventions.
- `docs/reference/` holds the Phase 1 database schema and migration brief that the port is built from.
- Everything else follows the standard Laravel layout.

## Working method

- One branch per batch of work, named `batch/<chat>-<id>-<slug>`, for example `batch/2.17-b1-migrations`.
- Each branch is squash-merged into `main`, so `main` has one commit per batch. `main` should always pass `php artisan migrate:fresh --seed` once migrations exist.
- One tag per batch, for example `2.17-A`.
- Commit messages use `type(scope): summary`. The body says why the change was made and cites the decision it follows.
- Never commit `.env`, database dumps, real patient data or images.
