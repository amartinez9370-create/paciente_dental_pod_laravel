<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * Phase 1 parity: docs/reference/schema.sql section 4. 1:1 with
     * users (role = 'patient'). guardian_patient_id is a self-referencing
     * FK for the guardian/dependent model (docs/decisions.md section 9):
     * NULL means the patient is their own account holder (or a walk-in);
     * set means the row is a dependent of the referenced patients row.
     */
    public function up(): void
    {
        Schema::create('patients', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id');
            $table->string('first_name', 80);
            $table->string('middle_name', 80)->nullable();
            $table->string('last_name', 80);
            $table->string('suffix', 20)->nullable();
            $table->string('phone', 40);
            $table->date('dob')->nullable();
            $table->unsignedBigInteger('guardian_patient_id')->nullable();
            // Relationship label for dependent patients (e.g. 'Child', 'Spouse/Partner').
            $table->string('relationship', 80)->nullable();
            // Free-form text. Becomes structured fields in Phase 2 (EMR).
            $table->text('medical_notes')->nullable();
            $table->dateTime('created_at')->useCurrent();
            $table->dateTime('updated_at')->useCurrent()->useCurrentOnUpdate();

            $table->unique('user_id', 'uq_patients_user');

            $table->foreign('user_id', 'fk_patients_user')
                ->references('id')->on('users')
                ->cascadeOnUpdate()->cascadeOnDelete();
            $table->foreign('guardian_patient_id', 'fk_patients_guardian')
                ->references('id')->on('patients')
                ->cascadeOnUpdate()->restrictOnDelete();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('patients');
    }
};
