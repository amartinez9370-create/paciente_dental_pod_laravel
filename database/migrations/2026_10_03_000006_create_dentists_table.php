<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * Phase 1 parity: docs/reference/schema.sql section 5. 1:1 with
     * users (role = 'dentist'). Name is stored as structured parts; the
     * view layer builds whatever display format is needed. clinic_id
     * ties each dentist to a clinic (multi-clinic readiness).
     */
    public function up(): void
    {
        Schema::create('dentists', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id');
            $table->foreignId('clinic_id');
            $table->string('first_name', 80);
            $table->string('middle_name', 80)->nullable();
            $table->string('last_name', 80);
            $table->string('suffix', 20)->nullable(); // Jr., Sr., III, etc.
            // e.g. "General Dentistry", "Orthodontics", "Pediatric Dentistry".
            $table->string('specialty', 120)->nullable();
            // Credential line appended after name: "DMD", "DMD, MOrth", etc.
            $table->string('credentials', 120)->nullable();
            $table->text('bio')->nullable();
            $table->boolean('is_active')->default(true);
            $table->dateTime('created_at')->useCurrent();
            $table->dateTime('updated_at')->useCurrent()->useCurrentOnUpdate();

            $table->unique('user_id', 'uq_dentists_user');
            $table->index(['clinic_id', 'is_active'], 'ix_dentists_clinic');

            $table->foreign('user_id', 'fk_dentists_user')
                ->references('id')->on('users')
                ->cascadeOnUpdate()->cascadeOnDelete();
            $table->foreign('clinic_id', 'fk_dentists_clinic')
                ->references('id')->on('clinics')
                ->cascadeOnUpdate()->restrictOnDelete();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('dentists');
    }
};
