<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * Phase 1 parity: docs/reference/schema.sql section 11. Kept as its
     * own custom table (docs/decisions.md section 2) because the
     * walk-in claim flow needs it; the skeleton's password_reset_tokens
     * table is dropped instead. One active token per user — any
     * existing token for that user_id is replaced on re-issue.
     * token_hash is the SHA-256 hex of the raw token sent to the user.
     * created_at only — no updated_at (section 2).
     */
    public function up(): void
    {
        Schema::create('password_resets', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id');
            $table->string('token_hash', 64);
            $table->dateTime('expires_at');
            $table->dateTime('used_at')->nullable();
            $table->dateTime('created_at')->useCurrent();

            $table->unique('token_hash', 'uq_pr_token');
            $table->index('user_id', 'ix_pr_user');

            $table->foreign('user_id', 'fk_pr_user')
                ->references('id')->on('users')
                ->cascadeOnUpdate()->cascadeOnDelete();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('password_resets');
    }
};
