<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    /**
     * Seed the application's database.
     *
     * Reference data (clinic, clinic hours, services) always loads.
     * Demo accounts and the dentist roster load only in the local and
     * testing environments — an allowlist, not an "except production"
     * denylist (docs/decisions.md section 2).
     */
    public function run(): void
    {
        $this->call(ReferenceDataSeeder::class);

        if (app()->environment(['local', 'testing'])) {
            $this->call(DemoDataSeeder::class);
        }
    }
}
