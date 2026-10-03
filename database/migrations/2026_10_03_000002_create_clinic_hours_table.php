<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * Phase 1 parity: docs/reference/schema.sql section 2. Weekly recurring
     * open hours. One row per open day; no row means the clinic is closed
     * that day. This is the authoritative, machine-readable source of
     * truth for clinic hours — clinics.hours_text is a display blurb only.
     * No timestamps (docs/decisions.md section 2).
     */
    public function up(): void
    {
        Schema::create('clinic_hours', function (Blueprint $table) {
            $table->id();
            $table->foreignId('clinic_id');
            // 0 = Sunday, 1 = Monday, ..., 6 = Saturday (PHP date('w') convention).
            $table->unsignedTinyInteger('day_of_week');
            $table->time('open_time');
            $table->time('close_time');

            $table->unique(['clinic_id', 'day_of_week'], 'uq_clinic_hours_day');
            $table->index('clinic_id', 'ix_clinic_hours_clinic');

            $table->foreign('clinic_id', 'fk_clinic_hours_clinic')
                ->references('id')->on('clinics')
                ->cascadeOnUpdate()->cascadeOnDelete();
        });

        DB::statement('ALTER TABLE clinic_hours ADD CONSTRAINT chk_clinic_hours_dow CHECK (day_of_week BETWEEN 0 AND 6)');
        DB::statement('ALTER TABLE clinic_hours ADD CONSTRAINT chk_clinic_hours_times CHECK (open_time < close_time)');
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('clinic_hours');
    }
};
