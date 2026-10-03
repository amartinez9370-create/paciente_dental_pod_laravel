<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     *
     * Phase 1 parity: docs/reference/schema.sql section 8. Many-to-many:
     * which dentists perform which services. Exists from day 1 so the
     * wizard can filter dentists by selected service once specialists
     * are added. No id, no timestamps.
     */
    public function up(): void
    {
        Schema::create('dentist_services', function (Blueprint $table) {
            $table->foreignId('dentist_id');
            $table->foreignId('service_id');

            $table->primary(['dentist_id', 'service_id']);
            $table->index('service_id', 'ix_dservices_service');

            $table->foreign('dentist_id', 'fk_dservices_dentist')
                ->references('id')->on('dentists')
                ->cascadeOnUpdate()->cascadeOnDelete();
            $table->foreign('service_id', 'fk_dservices_service')
                ->references('id')->on('services')
                ->cascadeOnUpdate()->cascadeOnDelete();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('dentist_services');
    }
};
