<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * Phase 1 parity: docs/reference/schema.sql section 3, with the
     * changes in docs/decisions.md section 2:
     *   - password_hash renamed to password.
     *   - role ENUM gains 'staff'.
     *   - remember_token added (section 10, resolved); email_verified_at
     *     is not added — walk-in sentinel emails can't be verified and
     *     Phase 1 had no verification flow.
     *
     * Pure auth table. Names live on the profile tables (patients,
     * dentists, staff), so there is no name column here.
     */
    public function up(): void
    {
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            $table->string('email', 150);
            $table->string('password', 255);
            // Admin elevation is enforced in PHP middleware against this column.
            $table->enum('role', ['patient', 'dentist', 'staff', 'admin'])->default('patient');
            $table->boolean('is_active')->default(true);
            $table->dateTime('last_login_at')->nullable();
            $table->rememberToken();
            $table->dateTime('created_at')->useCurrent();
            $table->dateTime('updated_at')->useCurrent()->useCurrentOnUpdate();

            $table->unique('email', 'uq_users_email');
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('users');
    }
};
