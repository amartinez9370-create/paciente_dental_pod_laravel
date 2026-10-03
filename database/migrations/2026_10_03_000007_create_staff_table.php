<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * Phase 1 parity: docs/reference/schema.sql section 6, with the
     * stale comment corrected (docs/decisions.md section 2): this table
     * holds profiles for users with role 'admin' AND role 'staff', not
     * just 'admin'. Mirrors patients and dentists in shape. Admin
     * elevation is not controlled here — that decision lives on
     * users.role, checked in PHP middleware; this table just holds the
     * person (name, phone, job title).
     */
    public function up(): void
    {
        Schema::create('staff', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id');
            $table->foreignId('clinic_id');
            $table->string('first_name', 80);
            $table->string('middle_name', 80)->nullable();
            $table->string('last_name', 80);
            $table->string('suffix', 20)->nullable();
            $table->string('phone', 40)->nullable();
            // Free-form display title shown in admin UIs. Distinct from
            // users.role, which is the access-control identity.
            $table->string('job_title', 120)->nullable();
            $table->boolean('is_active')->default(true);
            $table->dateTime('created_at')->useCurrent();
            $table->dateTime('updated_at')->useCurrent()->useCurrentOnUpdate();

            $table->unique('user_id', 'uq_staff_user');
            $table->index(['clinic_id', 'is_active'], 'ix_staff_clinic');

            $table->foreign('user_id', 'fk_staff_user')
                ->references('id')->on('users')
                ->cascadeOnUpdate()->cascadeOnDelete();
            $table->foreign('clinic_id', 'fk_staff_clinic')
                ->references('id')->on('clinics')
                ->cascadeOnUpdate()->restrictOnDelete();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('staff');
    }
};
