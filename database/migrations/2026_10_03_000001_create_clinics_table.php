<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * Phase 1 parity: docs/reference/schema.sql section 1. One row in
     * Phase 1. clinic_id is carried by every booking-related table so a
     * future second branch is a data move, not a schema migration.
     */
    public function up(): void
    {
        Schema::create('clinics', function (Blueprint $table) {
            $table->id();
            $table->string('name', 120);
            $table->string('address', 255);
            $table->string('phone', 40)->nullable();
            $table->string('email', 150)->nullable();
            // Step size (minutes) between slot start times offered to patients.
            $table->unsignedSmallInteger('slot_interval')->default(30);
            // Minimum minutes before a slot start that a patient can still book it.
            $table->unsignedSmallInteger('booking_lead_minutes')->default(60);
            // How many days ahead patients can book (calendar max date).
            $table->unsignedSmallInteger('booking_window_days')->default(60);
            // Free-form opening hours blurb shown on patient-facing pages.
            // The authoritative weekly schedule lives in clinic_hours.
            $table->string('hours_text', 255)->nullable();
            $table->boolean('is_active')->default(true);
            $table->dateTime('created_at')->useCurrent();
            $table->dateTime('updated_at')->useCurrent()->useCurrentOnUpdate();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('clinics');
    }
};
