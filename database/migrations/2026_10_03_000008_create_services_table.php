<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * Phase 1 parity: docs/reference/schema.sql section 7, already
     * folded forward to include duration_minutes and online_bookable
     * (the trailing "snapshot 45 to 46" block in schema.sql is skipped;
     * docs/decisions.md section 2). price uses DECIMAL(10,2) — peso,
     * displayed without decimals when whole, "Free" for zero (handled in
     * PHP). duration_minutes drives slot generation and conflict
     * detection. online_bookable = 0 hides a service from the wizard.
     */
    public function up(): void
    {
        Schema::create('services', function (Blueprint $table) {
            $table->id();
            $table->foreignId('clinic_id');
            $table->string('name', 120);
            $table->string('description', 500)->nullable();
            // NULL = "price varies / consultation needed". 0.00 = "Free".
            $table->decimal('price', 10, 2)->nullable();
            // Drives conflict detection: a booked slot blocks
            // [start_time, start_time + duration_minutes).
            $table->unsignedSmallInteger('duration_minutes')->default(30);
            // 1 = visible in the patient wizard. 0 = catalog / walk-in /
            // admin use only; hidden from online booking.
            $table->boolean('online_bookable')->default(true);
            // Filename only — relative to /public/assets/site/service-icons/.
            $table->string('icon_filename', 80)->nullable();
            $table->boolean('is_active')->default(true);
            // Display order on the wizard / services page (admin-controlled).
            $table->unsignedSmallInteger('sort_order')->default(100);
            $table->dateTime('created_at')->useCurrent();
            $table->dateTime('updated_at')->useCurrent()->useCurrentOnUpdate();

            $table->index(['clinic_id', 'is_active', 'online_bookable'], 'ix_services_clinic_active');

            $table->foreign('clinic_id', 'fk_services_clinic')
                ->references('id')->on('clinics')
                ->cascadeOnUpdate()->restrictOnDelete();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('services');
    }
};
