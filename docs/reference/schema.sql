-- =====================================================================
-- Paciente Dental POD — Appointment System
-- Database schema (Phase 1)
--
-- Target:  MySQL 5.7+ / MariaDB 10.3+ (XAMPP local + Hostinger shared)
-- Engine:  InnoDB (required for foreign keys + SELECT ... FOR UPDATE)
-- Charset: utf8mb4 (full Unicode, including emoji and Filipino characters)
-- Time zone: stored as DATE/TIME values; application enforces Asia/Manila
-- Currency: prices stored in PHP centavos? No — see services table notes.
--
-- Design notes (from Project_Summary.md, Sections 4 and 9):
--   - Multi-dentist + multi-clinic ready: dentist_id and clinic_id are
--     first-class fields, even though Phase 1 has one of each.
--   - Unified login: users.role determines redirect after auth.
--   - Appointment statuses follow a state machine:
--        pending -> confirmed -> completed
--        pending -> cancelled
--        confirmed -> cancelled / completed / no_show
--   - Slot conflict prevention uses transaction + SELECT ... FOR UPDATE
--     against the appointments table; the index on
--     (dentist_id, appointment_date, status) makes that lock cheap.
-- =====================================================================

-- Make sure we're starting from a known state when re-running locally.
-- WARNING: drops everything in dbPacienteDentalPod. Comment this out
-- if you only want to add to an existing database.
DROP DATABASE IF EXISTS dbPacienteDentalPod;
CREATE DATABASE dbPacienteDentalPod
    DEFAULT CHARACTER SET utf8mb4
    DEFAULT COLLATE utf8mb4_unicode_ci;
USE dbPacienteDentalPod;


-- =====================================================================
-- 1. clinics
--    One row in Phase 1. Multi-clinic readiness — every booking-related
--    table carries clinic_id so a future second branch is a data move,
--    not a schema migration.
-- =====================================================================
CREATE TABLE clinics (
    id              INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    name            VARCHAR(120)        NOT NULL,
    address         VARCHAR(255)        NOT NULL,
    phone           VARCHAR(40)         NULL,
    email           VARCHAR(150)        NULL,
    -- Step size (minutes) between slot start times offered to patients.
    -- e.g. 30 means slots at :00 and :30 past each hour.
    -- Each booking occupies exactly one slot (30 minutes).
    slot_interval   SMALLINT UNSIGNED   NOT NULL DEFAULT 30,
    -- Minimum minutes before a slot start that a patient can still book it.
    -- e.g. 60 = patients cannot book a slot starting within 1 hour of now.
    -- Read by getAvailableSlots() — replaces the old hardcoded 60.
    booking_lead_minutes  SMALLINT UNSIGNED   NOT NULL DEFAULT 60,
    -- How many days ahead patients can book (calendar max date).
    -- Read by BookingController and the booking wizard date picker.
    -- Replaces the old hardcoded 60-day window.
    booking_window_days   SMALLINT UNSIGNED   NOT NULL DEFAULT 60,
    -- Free-form opening hours blurb shown on patient-facing pages.
    -- The authoritative weekly schedule lives in clinic_hours.
    hours_text      VARCHAR(255)        NULL,
    is_active       TINYINT(1)          NOT NULL DEFAULT 1,
    created_at      DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;




-- =====================================================================
-- 2. clinic_hours
--    Weekly recurring open hours for the clinic. One row per open day.
--    No row for a day_of_week = clinic is closed that day.
--
--    This is the authoritative machine-readable source of truth for
--    clinic operating hours. The clinics.hours_text column is a
--    human-readable blurb only (shown on public pages) and is NOT
--    used by any scheduling logic.
--
--    Relationship to dentist_schedules:
--      - A dentist may only work on days the clinic is open.
--      - A dentist's start/end must fall within the clinic's
--        open/close for that day.
--      - Enforcement is two-layer:
--          1. UI: dentist availability page clamps options to clinic window.
--          2. Algorithm: getAvailableSlots() intersects the dentist window
--             with the clinic window before generating candidate slots.
--
--    0 = Sunday, 1 = Monday, ..., 6 = Saturday (PHP date('w') convention).
-- =====================================================================
CREATE TABLE clinic_hours (
    id              INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    clinic_id       INT UNSIGNED        NOT NULL,
    day_of_week     TINYINT UNSIGNED    NOT NULL,
    open_time       TIME                NOT NULL,
    close_time      TIME                NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_clinic_hours_day (clinic_id, day_of_week),
    KEY ix_clinic_hours_clinic (clinic_id),
    CONSTRAINT fk_clinic_hours_clinic
        FOREIGN KEY (clinic_id) REFERENCES clinics(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_clinic_hours_dow
        CHECK (day_of_week BETWEEN 0 AND 6),
    CONSTRAINT chk_clinic_hours_times
        CHECK (open_time < close_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =====================================================================
-- 3. users
--    Pure auth table. Email + password + role + activation state.
--    Every authenticated person — patient, dentist, or admin — has a
--    row here. role decides which dashboard they land on after login
--    and is the gate for elevated actions.
--
--    Names live on profile tables (patients, dentists, staff) — there
--    is no first_name/last_name here, so there's no risk of drift
--    between auth and profile data.
--
--    Password is stored ONLY as the bcrypt output of password_hash().
--    Never plain text, never md5/sha1.
-- =====================================================================
CREATE TABLE users (
    id              INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    email           VARCHAR(150)        NOT NULL,
    password_hash   VARCHAR(255)        NOT NULL,
    -- ENUM keeps roles tight; widening is a single ALTER TABLE if
    -- additional roles (hygienist, assistant) are needed later.
    -- Admin elevation is enforced in PHP middleware against this column.
    role            ENUM(
                        'patient',
                        'dentist',
                        'admin'
                    )                   NOT NULL DEFAULT 'patient',
    is_active       TINYINT(1)          NOT NULL DEFAULT 1,
    last_login_at   DATETIME            NULL,
    created_at      DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- 4. patients
--    1:1 with users (where role = 'patient'). Stored separately so the
--    auth layer stays clean and Phase 2 EMR fields can be added here
--    without bloating users.
-- =====================================================================
CREATE TABLE patients (
    id              INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    user_id         INT UNSIGNED        NOT NULL,
    first_name      VARCHAR(80)         NOT NULL,
    middle_name     VARCHAR(80)         NULL,
    last_name       VARCHAR(80)         NOT NULL,
    suffix          VARCHAR(20)         NULL,
    phone           VARCHAR(40)         NOT NULL,
    dob             DATE                NULL,
    -- Self-referencing FK for dependent patients.
    -- NULL  = this patient is their own account holder (or a walk-in)
    -- set   = this patient is a dependent of the referenced patients row
    guardian_patient_id INT UNSIGNED    NULL,
    -- Relationship label for dependent patients (e.g. 'Child', 'Spouse/Partner').
    -- NULL for account holders; set for dependents.
    relationship    VARCHAR(80)         NULL,
    -- Free-form text. Becomes structured fields in Phase 2 (EMR).
    -- Also used to record special needs for dependents (PWD, senior care, etc.).
    medical_notes   TEXT                NULL,
    -- No no_show_flag column — no-show history is queried directly from
    -- appointments WHERE status = 'no_show' AND patient_id = ?
    -- Keeping a denormalized flag here would require manual sync and
    -- would drift. A COUNT(*) query is fast enough for this use case.
    created_at      DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_patients_user (user_id),
    CONSTRAINT fk_patients_user
        FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_patients_guardian
        FOREIGN KEY (guardian_patient_id) REFERENCES patients(id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- 5. dentists
--    1:1 with users (role = 'dentist'). Name is stored as structured
--    parts — the view layer builds whatever display format is needed
--    (e.g. "Dr. Cruz, L., DMD" or "Dr. Lena Cruz").
--    clinic_id ties each dentist to a clinic — Phase 3 readiness.
-- =====================================================================
CREATE TABLE dentists (
    id              INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    user_id         INT UNSIGNED        NOT NULL,
    clinic_id       INT UNSIGNED        NOT NULL,
    first_name      VARCHAR(80)         NOT NULL,
    middle_name     VARCHAR(80)         NULL,
    last_name       VARCHAR(80)         NOT NULL,
    suffix          VARCHAR(20)         NULL,        -- Jr., Sr., III, etc.
    -- e.g. "General Dentistry", "Orthodontics", "Pediatric Dentistry".
    specialty       VARCHAR(120)        NULL,
    -- Credential line appended after name: "DMD", "DMD, MOrth", etc.
    credentials     VARCHAR(120)        NULL,
    bio             TEXT                NULL,
    is_active       TINYINT(1)          NOT NULL DEFAULT 1,
    created_at      DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_dentists_user (user_id),
    KEY ix_dentists_clinic (clinic_id, is_active),
    CONSTRAINT fk_dentists_user
        FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_dentists_clinic
        FOREIGN KEY (clinic_id) REFERENCES clinics(id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- 6. staff
--    Profile table for users with role = 'admin'. Mirrors patients and
--    dentists in shape so all "person" roles have a consistent profile
--    structure. If hygienist/assistant roles are added later, they would
--    also use this table.
--
--    Note: admin elevation is NOT controlled by this table. The
--    decision lives on users.role, checked in PHP middleware. This
--    table just holds the person — name, phone, job title.
-- =====================================================================
CREATE TABLE staff (
    id              INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    user_id         INT UNSIGNED        NOT NULL,
    clinic_id       INT UNSIGNED        NOT NULL,
    first_name      VARCHAR(80)         NOT NULL,
    middle_name     VARCHAR(80)         NULL,
    last_name       VARCHAR(80)         NOT NULL,
    suffix          VARCHAR(20)         NULL,
    phone           VARCHAR(40)         NULL,
    -- Free-form display title shown in admin UIs and (where relevant)
    -- patient-facing surfaces. e.g. "Office Manager", "Lead Hygienist".
    -- Distinct from users.role, which is the access-control identity.
    job_title       VARCHAR(120)        NULL,
    is_active       TINYINT(1)          NOT NULL DEFAULT 1,
    created_at      DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_staff_user (user_id),
    KEY ix_staff_clinic (clinic_id, is_active),
    CONSTRAINT fk_staff_user
        FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_staff_clinic
        FOREIGN KEY (clinic_id) REFERENCES clinics(id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- 7. services
--    The catalog the patient picks from on Step 1 of the wizard.
--    duration_minutes drives slot generation: end_time = start_time +
--    duration_minutes. Conflict detection uses range overlap so a 60-min
--    cleaning starting at 2:00 PM correctly blocks the 2:30 PM slot.
--    price uses DECIMAL(10,2) — Philippine peso, displayed without
--    decimals when whole (handled in PHP, not the schema).
--    0.00 = explicitly free. NULL = "price varies / starts at X".
--    online_bookable = 0: catalog / walk-in use only; hidden from wizard.
-- =====================================================================
CREATE TABLE services (
    id                  INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    clinic_id           INT UNSIGNED        NOT NULL,
    name                VARCHAR(120)        NOT NULL,
    description         VARCHAR(500)        NULL,
    -- NULL = "price varies / consultation needed".
    -- 0.00 = explicitly free (e.g. check-up, consultation).
    price               DECIMAL(10,2)       NULL,
    -- Appointment length in minutes. Drives conflict detection:
    -- a booked slot blocks [start_time, start_time + duration_minutes).
    -- Use multiples of 15 for clean slot-boundary alignment.
    duration_minutes    SMALLINT UNSIGNED   NOT NULL DEFAULT 30,
    -- 1 = visible in the patient booking wizard (default).
    -- 0 = catalog / walk-in / admin use only; hidden from online booking.
    online_bookable     TINYINT(1)          NOT NULL DEFAULT 1,
    -- Filename only — relative to /public/assets/site/service-icons/.
    icon_filename       VARCHAR(80)         NULL,
    is_active           TINYINT(1)          NOT NULL DEFAULT 1,
    -- Display order on the wizard / services page (admin-controlled).
    sort_order          SMALLINT UNSIGNED   NOT NULL DEFAULT 100,
    created_at          DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY ix_services_clinic_active (clinic_id, is_active, online_bookable),
    CONSTRAINT fk_services_clinic
        FOREIGN KEY (clinic_id) REFERENCES clinics(id)
        ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- 8. dentist_services
--    Many-to-many: which dentists perform which services. In Phase 1
--    Dr. Paciente performs everything, but the table exists from day 1
--    so Step 2 of the wizard can filter dentists by selected service
--    once specialists are added (see interview Q17).
-- =====================================================================
CREATE TABLE dentist_services (
    dentist_id      INT UNSIGNED        NOT NULL,
    service_id      INT UNSIGNED        NOT NULL,
    PRIMARY KEY (dentist_id, service_id),
    KEY ix_dservices_service (service_id),
    CONSTRAINT fk_dservices_dentist
        FOREIGN KEY (dentist_id) REFERENCES dentists(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_dservices_service
        FOREIGN KEY (service_id) REFERENCES services(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- 9. dentist_schedules
--    Weekly recurring availability. One row per (dentist, day-of-week)
--    block. Uses ISO-style 0=Sunday ... 6=Saturday to match PHP's
--    date('w') return value — no off-by-one bugs.
-- =====================================================================
CREATE TABLE dentist_schedules (
    id              INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    dentist_id      INT UNSIGNED        NOT NULL,
    -- 0 = Sunday, 1 = Monday, ..., 6 = Saturday.
    day_of_week     TINYINT UNSIGNED    NOT NULL,
    start_time      TIME                NOT NULL,
    end_time        TIME                NOT NULL,
    PRIMARY KEY (id),
    KEY ix_dsched_dentist_day (dentist_id, day_of_week),
    CONSTRAINT fk_dsched_dentist
        FOREIGN KEY (dentist_id) REFERENCES dentists(id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT chk_dsched_dow
        CHECK (day_of_week BETWEEN 0 AND 6),
    CONSTRAINT chk_dsched_times
        CHECK (start_time < end_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- 10. appointments
--    The backbone of the system. Every booked, cancelled, or completed
--    visit is one row.
--
--    appointment_date and start_time are stored as separate columns
--    (rather than a single DATETIME) because:
--      - the booking algorithm reasons about "all appointments on
--        date X" — having a date column makes the index efficient
--      - displaying the slot to the patient never needs a TZ math op
--      - Asia/Manila has no DST so there's no ambiguity to worry about
--
--    end_time is not stored as a column — the conflict check JOINs
--    services to get duration_minutes and computes overlap in PHP.
--    This keeps the appointments table lean and avoids a derived-value
--    column that must be kept in sync. updated_at is maintained
--    automatically by MySQL ON UPDATE CURRENT_TIMESTAMP.
-- =====================================================================
CREATE TABLE appointments (
    id                  INT UNSIGNED        NOT NULL AUTO_INCREMENT,
    clinic_id           INT UNSIGNED        NOT NULL,
    patient_id          INT UNSIGNED        NOT NULL,
    dentist_id          INT UNSIGNED        NOT NULL,
    service_id          INT UNSIGNED        NOT NULL,
    appointment_date    DATE                NOT NULL,
    -- start_time is NULL for queued walk-ins (patient waiting, no fixed slot).
    -- arrived_at records when the walk-in patient physically arrived; used to
    -- position queued cards between scheduled appointments in today's list.
    start_time          TIME                NULL,
    arrived_at          DATETIME            NULL,
    status              ENUM(
                            'pending',
                            'confirmed',
                            'completed',
                            'cancelled',
                            'no_show',
                            'declined'
                        )                   NOT NULL DEFAULT 'pending',
    -- Patient's optional notes from the Review step (Step 4).
    notes               TEXT                NULL,
    -- Human-readable reference shown on the confirmation screen
    -- and in emails. Format: APT-YYYYMMDD-HHMM-{CC}{DD}
    -- where CC = clinic_id and DD = dentist_id, both zero-padded to 2 digits.
    -- e.g. APT-20260503-1400-0101. Deterministic — derived from the
    -- appointment's own date, time, clinic, and dentist, so it is
    -- unique by the same guarantee that prevents slot double-booking.
    reference_code      VARCHAR(30)         NOT NULL,
    -- Audit trail. cancelled_by_user_id helps distinguish
    -- patient cancellations from admin-driven ones.
    cancelled_at        DATETIME            NULL,
    confirmed_by_user_id INT UNSIGNED       NULL,
    cancelled_by_user_id INT UNSIGNED       NULL,
    completed_by_user_id INT UNSIGNED       NULL,
    -- Optional reason provided by the patient when cancelling.
    cancel_reason       VARCHAR(500)        NULL,
    -- Populated when a dentist declines a pending booking.
    declined_at         DATETIME            NULL,
    -- Optional reason provided by the dentist when declining.
    decline_reason      VARCHAR(500)        NULL,
    -- Clinical notes written by the dentist when marking completed.
    -- Kept separate from patient-facing `notes` so each party's
    -- input is preserved and displayed independently.
    clinical_notes      TEXT                NULL,
    -- Origin of the booking. 'online' = patient self-booked via the wizard.
    -- 'walkin' = admin created the booking on behalf of a walk-in patient.
    -- Stored for future reporting; not surfaced visually in Phase 1.
    source              ENUM('online','walkin') NOT NULL DEFAULT 'online',
    -- Emergency flag. Set by admin at walk-in booking or on any existing
    -- appointment. Dentists can also toggle it (peer review). Shown as a
    -- red left-border on appointment cards in all views.
    is_emergency        TINYINT(1)          NOT NULL DEFAULT 0,
    reminder_sent       TINYINT(1)          NOT NULL DEFAULT 0,
    completed_at        DATETIME            NULL,
    created_at          DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          DATETIME            NOT NULL DEFAULT CURRENT_TIMESTAMP
                                            ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_appt_reference (reference_code),
    -- The slot-availability + conflict-detection workhorse index.
    KEY ix_appt_dentist_date (dentist_id, appointment_date, status),
    KEY ix_appt_patient_date (patient_id, appointment_date),
    KEY ix_appt_clinic_date  (clinic_id, appointment_date),
    CONSTRAINT fk_appt_clinic
        FOREIGN KEY (clinic_id) REFERENCES clinics(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_appt_patient
        FOREIGN KEY (patient_id) REFERENCES patients(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_appt_dentist
        FOREIGN KEY (dentist_id) REFERENCES dentists(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_appt_service
        FOREIGN KEY (service_id) REFERENCES services(id)
        ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_appt_confirmed_by
        FOREIGN KEY (confirmed_by_user_id) REFERENCES users(id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_appt_cancelled_by
        FOREIGN KEY (cancelled_by_user_id) REFERENCES users(id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_appt_completed_by
        FOREIGN KEY (completed_by_user_id) REFERENCES users(id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- 11. password_resets
--    Stores one-time tokens for account setup (walk-in claim flow) and
--    future forgot-password flows. One active token per user — any
--    existing token for that user_id is replaced on re-issue.
--
--    token_hash: SHA-256 hex of the raw token sent to the user.
--    expires_at: 48 hours after creation for setup links.
--    used_at: set when the token is consumed; prevents replay.
-- =====================================================================
CREATE TABLE password_resets (
    id          INT UNSIGNED    NOT NULL AUTO_INCREMENT,
    user_id     INT UNSIGNED    NOT NULL,
    token_hash  VARCHAR(64)     NOT NULL,
    expires_at  DATETIME        NOT NULL,
    used_at     DATETIME        NULL,
    created_at  DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    UNIQUE KEY uq_pr_token (token_hash),
    KEY ix_pr_user (user_id),
    CONSTRAINT fk_pr_user
        FOREIGN KEY (user_id) REFERENCES users(id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- =====================================================================
--                              SEED DATA
-- =====================================================================
-- =====================================================================

-- ---- 1. The clinic ------------------------------------------------
INSERT INTO clinics (id, name, address, phone, email, slot_interval,
                    booking_lead_minutes, booking_window_days, hours_text)
VALUES (
    1,
    'Paciente Dental POD',
    '4408 Calatagan Street, Barangay Palanan, Makati City',
    '(+63) 920 983 1342',
    NULL,             -- email (not set yet)
    30,   -- slot_interval: 30-minute slots
    60,   -- booking_lead_minutes: cannot book within 60 min of now
    60,   -- booking_window_days: can book up to 60 days ahead
    '1:00 PM – 5:00 PM (weekdays except Wednesday); 11:00 AM – 5:00 PM (weekends)'
);


-- ---- 1b. Clinic weekly hours ----------------------------------------
-- Matches the current implicit schedule encoded in hours_text and the
-- hardcoded Wednesday-closed check that was in BookingController.php:
--   Sun:            11:00 – 17:00
--   Mon/Tue/Thu/Fri: 13:00 – 17:00
--   Wed:            (closed — no row)
--   Sat:            11:00 – 17:00
--
-- The admin can change these at any time via the admin dashboard.
-- Changes take effect immediately for new patient bookings.
-- 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat
INSERT INTO clinic_hours (clinic_id, day_of_week, open_time, close_time) VALUES
    (1, 0, '11:00:00', '17:00:00'),  -- Sunday
    (1, 1, '13:00:00', '17:00:00'),  -- Monday
    (1, 2, '13:00:00', '17:00:00'),  -- Tuesday
    -- Wednesday: closed (no row)
    (1, 4, '13:00:00', '17:00:00'),  -- Thursday
    (1, 5, '13:00:00', '17:00:00'),  -- Friday
    (1, 6, '11:00:00', '17:00:00');  -- Saturday

-- ---- 2. User accounts -----------------------------------------------
-- Passwords hashed with password_hash(..., PASSWORD_DEFAULT).
-- admin123    → Sonny Paciente     (admin,   user_id 1)
-- dentist123  → Dr. Bernadette     (dentist, user_id 2)
-- dentist123  → Dr. Sean Paciente  (dentist, user_id 3)
-- angel123    → Angeles Martinez   (patient, user_id 4)

INSERT INTO users (id, email, password_hash, role) VALUES
    (1, 'sonny.p@pdp.com',
        '$2y$10$AnaxCEvPO9ukaMlUP/3bUOPOkhfSrxTQdjoI0rmolu/FPePVk3CXu', 'admin'),
    (2, 'b.paciente@pdp.com',
        '$2y$10$ht0kAPRgo.CUPf.8D9bGReavmdiuAVyMErxq2zm90JF742Ldc3ZhO', 'dentist'),
    (3, 's.paciente@pdp.com',
        '$2y$10$ht0kAPRgo.CUPf.8D9bGReavmdiuAVyMErxq2zm90JF742Ldc3ZhO', 'dentist'),
    (4, 'angeles.martinezjr@gmail.com',
        '$2y$10$u0wHIlNAX6O1Fpl.w3MHEeXZK/SDPt6c3GbT3I4dx36ltPGrDrEBi', 'patient');

-- ---- 3. Admin profile (matches user_id = 1) -------------------------
INSERT INTO staff (id, user_id, clinic_id, first_name, last_name, job_title, is_active)
VALUES (
    1, 1, 1,
    'Sonny', 'Paciente',
    'Office Administrator',
    1
);

-- ---- 3b. Patient seed account -------------------------------------
-- Angeles Martinez Jr. — a ready-made patient for testing the booking
-- flow without having to register a new account each time.
-- Login: angeles.martinezjr@gmail.com / angel123
INSERT INTO patients (id, user_id, first_name, last_name, suffix, phone, dob)
VALUES (
    1,
    4,
    'Angeles',
    'Martinez',
    'Jr.',
    '639959765681',
    '1983-01-28'
);

-- ---- 4. Dentists ----------------------------------------------------
INSERT INTO dentists (id, user_id, clinic_id, first_name, last_name, specialty, credentials, is_active)
VALUES
    (1, 2, 1, 'Bernadette', 'Paciente', 'Orthodontics',     'DMD', 1),
    (2, 3, 1, 'Sean C.',    'Paciente', 'General Dentistry', 'DMD', 1);

-- ---- 5. Services catalog ------------------------------------------
-- 11 services. duration_minutes is used for range-overlap conflict
-- detection: a booked slot blocks [start_time, start_time + duration).
-- price = 0.00 → "Free". price > 0 → "Starts at ₱X,XXX" in wizard.
-- online_bookable = 0 → walk-in / admin catalog only (Dental X-ray).
-- Both dentists pick up all 11 services via the bulk INSERT below.
INSERT INTO services
    (id, clinic_id, name, description, price, duration_minutes,
     online_bookable, icon_filename, is_active, sort_order)
VALUES
    (1,  1, 'Routine Check-up',
        'General oral health examination. Ideal if you haven''t visited us in a while or just want a clean bill of health.',
        0.00,     30, 1, '013-dental-checkup.png',   1, 10),

    (2,  1, 'Treatment Consultation',
        'Free consultation for specific treatments — braces, veneers, crowns, bridges, or dentures. Come in with a goal, leave with a plan.',
        0.00,     30, 1, '001-tooth.png',            1, 20),

    (3,  1, 'Prophylaxis (Cleaning)',
        'Routine cleaning, scaling, and polishing.',
        1000.00,  60, 1, '005-tooth-1.png',          1, 30),

    (4,  1, 'Dental Filling',
        'Tooth-coloured composite restoration. Price is per tooth.',
        1000.00,  60, 1, '007-tooth-filling.png',    1, 40),

    (5,  1, 'Tooth Extraction',
        'Safe removal of damaged or impacted teeth.',
        1000.00,  30, 1, '015-tooth-extraction.png', 1, 50),

    (6,  1, 'Teeth Whitening',
        'In-clinic whitening session — visible results in one visit.',
        15000.00, 60, 1, '012-tooth-whitening.png',  1, 60),

    (7,  1, 'Orthodontic Follow-up',
        'Follow-up visits for patients currently in orthodontic treatment — braces adjustments and retainer checks. For first-time patients, please book a Treatment Consultation first.',
        500.00,   30, 1, NULL,                       1, 70),

    (8,  1, 'Root Canal Treatment',
        'Removal of infected pulp tissue to save a damaged tooth. Number of sessions may vary depending on the tooth.',
        3500.00,  90, 1, NULL,                       1, 80),

    (9,  1, 'Fluoride Treatment',
        'Topical fluoride application to strengthen enamel and prevent decay. Recommended for children and cavity-prone adults.',
        500.00,   30, 1, NULL,                       1, 90),

    (10, 1, 'Pit & Fissure Sealants',
        'Protective coating applied to the chewing surfaces of molars to prevent cavities. Especially recommended for children and teenagers.',
        500.00,   30, 1, NULL,                       1, 100),

    (11, 1, 'Dental X-ray',
        'Diagnostic radiograph used to assess tooth and bone condition. Usually taken as part of a consultation or treatment.',
        150.00,   15, 0, NULL,                       1, 110);

-- ---- 6. Both dentists perform every service -------------------------
INSERT INTO dentist_services (dentist_id, service_id)
SELECT 1, id FROM services;

INSERT INTO dentist_services (dentist_id, service_id)
SELECT 2, id FROM services;

-- ---- 7. Weekly schedules --------------------------------------------
-- Mirrors the promo site's stated hours. Wednesday is closed (no row).
-- 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat.
-- Dr. Bernadette Paciente (dentist_id = 1)
INSERT INTO dentist_schedules (dentist_id, day_of_week, start_time, end_time) VALUES
    (1, 0, '11:00:00', '17:00:00'),
    (1, 1, '13:00:00', '17:00:00'),
    (1, 2, '13:00:00', '17:00:00'),
    (1, 4, '13:00:00', '17:00:00'),
    (1, 5, '13:00:00', '17:00:00'),
    (1, 6, '11:00:00', '17:00:00');

-- Dr. Sean C. Paciente (dentist_id = 2) — same hours for now
INSERT INTO dentist_schedules (dentist_id, day_of_week, start_time, end_time) VALUES
    (2, 0, '11:00:00', '17:00:00'),
    (2, 1, '13:00:00', '17:00:00'),
    (2, 2, '13:00:00', '17:00:00'),
    (2, 4, '13:00:00', '17:00:00'),
    (2, 5, '13:00:00', '17:00:00'),
    (2, 6, '11:00:00', '17:00:00');

-- =====================================================================
-- End of schema.
-- After loading, verify with:
--   USE dbPacienteDentalPod;
--   SHOW TABLES;
--   SELECT name, price FROM services ORDER BY sort_order;
--   SELECT day_of_week, start_time, end_time FROM dentist_schedules;
-- =====================================================================

-- =====================================================================
-- MIGRATION: snapshot 45 → snapshot 46
-- Run this block on any existing database that was set up from snapshot 45.
-- Safe to skip if re-running the full schema from scratch (DROP DATABASE).
-- =====================================================================

-- Step 1: Add new columns to services
ALTER TABLE services
    ADD COLUMN duration_minutes  SMALLINT UNSIGNED NOT NULL DEFAULT 30
        AFTER price,
    ADD COLUMN online_bookable   TINYINT(1)        NOT NULL DEFAULT 1
        AFTER duration_minutes;

-- Rebuild the index to include the new online_bookable column
ALTER TABLE services
    DROP INDEX ix_services_clinic_active,
    ADD  KEY   ix_services_clinic_active (clinic_id, is_active, online_bookable);

-- Step 2: Set correct durations + revised prices on the 7 existing services
UPDATE services SET duration_minutes = 30,  price = 0.00     WHERE id = 1;  -- Routine Check-up
UPDATE services SET duration_minutes = 30,  price = 0.00     WHERE id = 2;  -- Treatment Consultation
UPDATE services SET duration_minutes = 60,  price = 1000.00  WHERE id = 3;  -- Prophylaxis (Cleaning)
UPDATE services SET duration_minutes = 60,  price = 1000.00  WHERE id = 4;  -- Dental Filling
UPDATE services SET duration_minutes = 30,  price = 1000.00  WHERE id = 5;  -- Tooth Extraction
UPDATE services SET duration_minutes = 60,  price = 15000.00 WHERE id = 6;  -- Teeth Whitening
UPDATE services SET duration_minutes = 30,  price = 500.00   WHERE id = 7;  -- Orthodontic Follow-up

-- Step 3: Insert the 4 new services
INSERT INTO services
    (id, clinic_id, name, description, price, duration_minutes,
     online_bookable, icon_filename, is_active, sort_order)
VALUES
    (8,  1, 'Root Canal Treatment',
        'Removal of infected pulp tissue to save a damaged tooth. Number of sessions may vary depending on the tooth.',
        3500.00, 90, 1, NULL, 1, 80),
    (9,  1, 'Fluoride Treatment',
        'Topical fluoride application to strengthen enamel and prevent decay. Recommended for children and cavity-prone adults.',
        500.00, 30, 1, NULL, 1, 90),
    (10, 1, 'Pit & Fissure Sealants',
        'Protective coating applied to the chewing surfaces of molars to prevent cavities. Especially recommended for children and teenagers.',
        500.00, 30, 1, NULL, 1, 100),
    (11, 1, 'Dental X-ray',
        'Diagnostic radiograph used to assess tooth and bone condition. Usually taken as part of a consultation or treatment.',
        150.00, 15, 0, NULL, 1, 110);

-- Step 4: Wire the 4 new services to both dentists
INSERT IGNORE INTO dentist_services (dentist_id, service_id)
VALUES (1, 8), (1, 9), (1, 10), (1, 11),
       (2, 8), (2, 9), (2, 10), (2, 11);
