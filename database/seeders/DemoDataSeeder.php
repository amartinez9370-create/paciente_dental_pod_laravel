<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use RuntimeException;

/**
 * Demo accounts and the dentist roster. Loads only in the local and
 * testing environments — an allowlist, enforced here as well as in
 * DatabaseSeeder (docs/decisions.md section 2), so running this seeder
 * directly (e.g. `db:seed --class=DemoDataSeeder`) is just as safe as
 * going through DatabaseSeeder.
 *
 * Accounts are the four Phase 1 users (kept with their Phase 1 ids and,
 * for the patient, their Phase 1 profile details — see the note below)
 * plus one demo staff account added after them. Dentist profiles, their
 * schedules and their service links are demo-only because production
 * dentists are created in the admin UI, not seeded.
 *
 * Phase 1 parity: docs/reference/schema.sql seed sections 2, 3, 3b, 4,
 * 6 and 7. Passwords are re-hashed with Hash::make() — the Phase 1
 * hash strings are never copied in (CLAUDE.md: seed data is fake only,
 * passwords hashed with Hash::make).
 *
 * Exception: the demo patient (user 4 / patient 1) intentionally keeps
 * the real Phase 1 contact details (email, phone, DOB) at the project
 * owner's request, for testing notifications end-to-end. The same
 * details are already present in docs/reference/schema.sql. Replace
 * both before this repository is shared beyond the project owner.
 */
class DemoDataSeeder extends Seeder
{
    /**
     * Seed demo users, profiles, dentist schedules and service links.
     */
    public function run(): void
    {
        if (! app()->environment(['local', 'testing'])) {
            throw new RuntimeException('Demo data can only be seeded in local or testing environments.');
        }

        // So this seeder can run on its own; ReferenceDataSeeder only
        // inserts into empty tables, so calling it again is harmless.
        $this->call(ReferenceDataSeeder::class);

        // Insert-if-empty, guarded on users: a reseed must not throw or
        // duplicate the demo rows below, which all key off the Phase 1
        // user ids inserted here.
        if (DB::table('users')->doesntExist()) {
            DB::table('users')->insert([
                ['id' => 1, 'email' => 'sonny.p@pdp.com', 'password' => Hash::make('admin123'), 'role' => 'admin'],
                ['id' => 2, 'email' => 'b.paciente@pdp.com', 'password' => Hash::make('dentist123'), 'role' => 'dentist'],
                ['id' => 3, 'email' => 's.paciente@pdp.com', 'password' => Hash::make('dentist123'), 'role' => 'dentist'],
                ['id' => 4, 'email' => 'angeles.martinezjr@gmail.com', 'password' => Hash::make('angel123'), 'role' => 'patient'],
                ['id' => 5, 'email' => 'staff@pdp.com', 'password' => Hash::make('staff123'), 'role' => 'staff'],
            ]);

            // Staff profiles: id 1 is the admin (user 1), id 2 is the demo
            // staff account (user 5) added after the Phase 1 four.
            DB::table('staff')->insert([
                [
                    'id' => 1, 'user_id' => 1, 'clinic_id' => 1,
                    'first_name' => 'Sonny', 'last_name' => 'Paciente',
                    'job_title' => 'Office Administrator', 'is_active' => 1,
                ],
                [
                    'id' => 2, 'user_id' => 5, 'clinic_id' => 1,
                    'first_name' => 'Demo', 'last_name' => 'Staff',
                    'job_title' => 'Front Desk', 'is_active' => 1,
                ],
            ]);

            // Angeles Martinez Jr. — a ready-made patient for testing the
            // request flow without registering a new account each time.
            // Login: angeles.martinezjr@gmail.com / angel123
            DB::table('patients')->insert([
                'id' => 1, 'user_id' => 4,
                'first_name' => 'Angeles', 'last_name' => 'Martinez', 'suffix' => 'Jr.',
                'phone' => '639959765681', 'dob' => '1983-01-28',
            ]);

            DB::table('dentists')->insert([
                [
                    'id' => 1, 'user_id' => 2, 'clinic_id' => 1,
                    'first_name' => 'Bernadette', 'last_name' => 'Paciente',
                    'specialty' => 'Orthodontics', 'credentials' => 'DMD', 'is_active' => 1,
                ],
                [
                    'id' => 2, 'user_id' => 3, 'clinic_id' => 1,
                    'first_name' => 'Sean C.', 'last_name' => 'Paciente',
                    'specialty' => 'General Dentistry', 'credentials' => 'DMD', 'is_active' => 1,
                ],
            ]);

            // Both dentists perform every service.
            $serviceIds = DB::table('services')->pluck('id');
            $dentistServices = [];
            foreach ([1, 2] as $dentistId) {
                foreach ($serviceIds as $serviceId) {
                    $dentistServices[] = ['dentist_id' => $dentistId, 'service_id' => $serviceId];
                }
            }
            DB::table('dentist_services')->insert($dentistServices);

            // Weekly schedules mirror the clinic hours. Wednesday closed (no row).
            // Same hours for both dentists for now.
            $weeklyHours = [
                ['day_of_week' => 0, 'start_time' => '11:00:00', 'end_time' => '17:00:00'],
                ['day_of_week' => 1, 'start_time' => '13:00:00', 'end_time' => '17:00:00'],
                ['day_of_week' => 2, 'start_time' => '13:00:00', 'end_time' => '17:00:00'],
                ['day_of_week' => 4, 'start_time' => '13:00:00', 'end_time' => '17:00:00'],
                ['day_of_week' => 5, 'start_time' => '13:00:00', 'end_time' => '17:00:00'],
                ['day_of_week' => 6, 'start_time' => '11:00:00', 'end_time' => '17:00:00'],
            ];
            $dentistSchedules = [];
            foreach ([1, 2] as $dentistId) {
                foreach ($weeklyHours as $hours) {
                    $dentistSchedules[] = array_merge(['dentist_id' => $dentistId], $hours);
                }
            }
            DB::table('dentist_schedules')->insert($dentistSchedules);
        }
    }
}
