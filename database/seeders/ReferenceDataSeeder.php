<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;

/**
 * Data every environment needs to run the clinic: the clinic itself,
 * its weekly hours, and the services catalog. Always loaded, including
 * in production (docs/decisions.md section 2).
 *
 * Each table is seeded only when it is empty. This is insert-if-empty,
 * not upsert: admins edit clinic hours and service prices in the UI,
 * and a reseed must never overwrite their changes.
 *
 * Phase 1 parity: docs/reference/schema.sql seed sections 1, 1b and 5.
 */
class ReferenceDataSeeder extends Seeder
{
    /**
     * Seed the clinic, clinic hours and services catalog.
     */
    public function run(): void
    {
        if (DB::table('clinics')->doesntExist()) {
            DB::table('clinics')->insert([
                'id' => 1,
                'name' => 'Paciente Dental POD',
                'address' => '4408 Calatagan Street, Barangay Palanan, Makati City',
                'phone' => '(+63) 920 983 1342',
                'email' => null,
                'slot_interval' => 30,
                'booking_lead_minutes' => 60,
                'booking_window_days' => 60,
                'hours_text' => '1:00 PM – 5:00 PM (weekdays except Wednesday); 11:00 AM – 5:00 PM (weekends)',
            ]);
        }

        // 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat. Wednesday closed (no row).
        if (DB::table('clinic_hours')->doesntExist()) {
            DB::table('clinic_hours')->insert([
                ['clinic_id' => 1, 'day_of_week' => 0, 'open_time' => '11:00:00', 'close_time' => '17:00:00'],
                ['clinic_id' => 1, 'day_of_week' => 1, 'open_time' => '13:00:00', 'close_time' => '17:00:00'],
                ['clinic_id' => 1, 'day_of_week' => 2, 'open_time' => '13:00:00', 'close_time' => '17:00:00'],
                ['clinic_id' => 1, 'day_of_week' => 4, 'open_time' => '13:00:00', 'close_time' => '17:00:00'],
                ['clinic_id' => 1, 'day_of_week' => 5, 'open_time' => '13:00:00', 'close_time' => '17:00:00'],
                ['clinic_id' => 1, 'day_of_week' => 6, 'open_time' => '11:00:00', 'close_time' => '17:00:00'],
            ]);
        }

        // price = 0.00 -> "Free". price > 0 -> "Starts at ₱X,XXX" in the wizard.
        // online_bookable = 0 -> walk-in / admin catalog only (Dental X-ray).
        if (DB::table('services')->doesntExist()) {
            DB::table('services')->insert([
                [
                    'id' => 1, 'clinic_id' => 1, 'name' => 'Routine Check-up',
                    'description' => "General oral health examination. Ideal if you haven't visited us in a while or just want a clean bill of health.",
                    'price' => 0.00, 'duration_minutes' => 30, 'online_bookable' => 1,
                    'icon_filename' => '013-dental-checkup.png', 'is_active' => 1, 'sort_order' => 10,
                ],
                [
                    'id' => 2, 'clinic_id' => 1, 'name' => 'Treatment Consultation',
                    'description' => 'Free consultation for specific treatments — braces, veneers, crowns, bridges, or dentures. Come in with a goal, leave with a plan.',
                    'price' => 0.00, 'duration_minutes' => 30, 'online_bookable' => 1,
                    'icon_filename' => '001-tooth.png', 'is_active' => 1, 'sort_order' => 20,
                ],
                [
                    'id' => 3, 'clinic_id' => 1, 'name' => 'Prophylaxis (Cleaning)',
                    'description' => 'Routine cleaning, scaling, and polishing.',
                    'price' => 1000.00, 'duration_minutes' => 60, 'online_bookable' => 1,
                    'icon_filename' => '005-tooth-1.png', 'is_active' => 1, 'sort_order' => 30,
                ],
                [
                    'id' => 4, 'clinic_id' => 1, 'name' => 'Dental Filling',
                    'description' => 'Tooth-coloured composite restoration. Price is per tooth.',
                    'price' => 1000.00, 'duration_minutes' => 60, 'online_bookable' => 1,
                    'icon_filename' => '007-tooth-filling.png', 'is_active' => 1, 'sort_order' => 40,
                ],
                [
                    'id' => 5, 'clinic_id' => 1, 'name' => 'Tooth Extraction',
                    'description' => 'Safe removal of damaged or impacted teeth.',
                    'price' => 1000.00, 'duration_minutes' => 30, 'online_bookable' => 1,
                    'icon_filename' => '015-tooth-extraction.png', 'is_active' => 1, 'sort_order' => 50,
                ],
                [
                    'id' => 6, 'clinic_id' => 1, 'name' => 'Teeth Whitening',
                    'description' => 'In-clinic whitening session — visible results in one visit.',
                    'price' => 15000.00, 'duration_minutes' => 60, 'online_bookable' => 1,
                    'icon_filename' => '012-tooth-whitening.png', 'is_active' => 1, 'sort_order' => 60,
                ],
                [
                    'id' => 7, 'clinic_id' => 1, 'name' => 'Orthodontic Follow-up',
                    'description' => 'Follow-up visits for patients currently in orthodontic treatment — braces adjustments and retainer checks. For first-time patients, please book a Treatment Consultation first.',
                    'price' => 500.00, 'duration_minutes' => 30, 'online_bookable' => 1,
                    'icon_filename' => null, 'is_active' => 1, 'sort_order' => 70,
                ],
                [
                    'id' => 8, 'clinic_id' => 1, 'name' => 'Root Canal Treatment',
                    'description' => 'Removal of infected pulp tissue to save a damaged tooth. Number of sessions may vary depending on the tooth.',
                    'price' => 3500.00, 'duration_minutes' => 90, 'online_bookable' => 1,
                    'icon_filename' => null, 'is_active' => 1, 'sort_order' => 80,
                ],
                [
                    'id' => 9, 'clinic_id' => 1, 'name' => 'Fluoride Treatment',
                    'description' => 'Topical fluoride application to strengthen enamel and prevent decay. Recommended for children and cavity-prone adults.',
                    'price' => 500.00, 'duration_minutes' => 30, 'online_bookable' => 1,
                    'icon_filename' => null, 'is_active' => 1, 'sort_order' => 90,
                ],
                [
                    'id' => 10, 'clinic_id' => 1, 'name' => 'Pit & Fissure Sealants',
                    'description' => 'Protective coating applied to the chewing surfaces of molars to prevent cavities. Especially recommended for children and teenagers.',
                    'price' => 500.00, 'duration_minutes' => 30, 'online_bookable' => 1,
                    'icon_filename' => null, 'is_active' => 1, 'sort_order' => 100,
                ],
                [
                    'id' => 11, 'clinic_id' => 1, 'name' => 'Dental X-ray',
                    'description' => 'Diagnostic radiograph used to assess tooth and bone condition. Usually taken as part of a consultation or treatment.',
                    'price' => 150.00, 'duration_minutes' => 15, 'online_bookable' => 0,
                    'icon_filename' => null, 'is_active' => 1, 'sort_order' => 110,
                ],
            ]);
        }
    }
}
