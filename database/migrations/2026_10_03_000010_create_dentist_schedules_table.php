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
     * Phase 1 parity: docs/reference/schema.sql section 9. Weekly
     * recurring availability. One row per (dentist, day-of-week) block.
     * 0=Sunday ... 6=Saturday, matching PHP's date('w'). No timestamps.
     */
    public function up(): void
    {
        Schema::create('dentist_schedules', function (Blueprint $table) {
            $table->id();
            $table->foreignId('dentist_id');
            $table->unsignedTinyInteger('day_of_week');
            $table->time('start_time');
            $table->time('end_time');

            $table->index(['dentist_id', 'day_of_week'], 'ix_dsched_dentist_day');

            $table->foreign('dentist_id', 'fk_dsched_dentist')
                ->references('id')->on('dentists')
                ->cascadeOnUpdate()->cascadeOnDelete();
        });

        DB::statement('ALTER TABLE dentist_schedules ADD CONSTRAINT chk_dsched_dow CHECK (day_of_week BETWEEN 0 AND 6)');
        DB::statement('ALTER TABLE dentist_schedules ADD CONSTRAINT chk_dsched_times CHECK (start_time < end_time)');
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('dentist_schedules');
    }
};
