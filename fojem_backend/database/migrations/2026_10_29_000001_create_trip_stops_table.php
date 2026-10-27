<?php

use App\Models\Trip;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * BlaBlaCar-style meeting points: the driver sets every place where
 * passengers board or leave (departure, intermediate stops, arrival), each
 * with a precise address, a time and a price from the departure. Passengers
 * travel to those points; the driver never detours to fetch them.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('trip_stops', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->foreignUuid('trip_id')->constrained('trips')->cascadeOnDelete();
            // 0 = departure, last = arrival.
            $table->unsignedSmallInteger('position');
            // Short label shown in lists ("Rufisque"), full address for the
            // passenger to find the exact spot.
            $table->string('name', 120);
            $table->string('address', 255)->nullable();
            $table->double('lat');
            $table->double('lng');
            $table->timestamp('scheduled_at')->nullable();
            // Price per seat from the departure to this stop: a segment
            // i → j costs price_from_origin[j] - price_from_origin[i].
            $table->decimal('price_from_origin', 10, 2)->default(0);
            $table->timestamps();

            $table->unique(['trip_id', 'position']);
        });

        DB::statement('ALTER TABLE trip_stops ADD COLUMN location_geom geography(Point, 4326)');
        DB::statement('CREATE INDEX trip_stops_location_geom_idx ON trip_stops USING GIST (location_geom)');

        Schema::table('bookings', function (Blueprint $table) {
            $table->foreignUuid('boarding_stop_id')->nullable()->after('trip_id')
                ->constrained('trip_stops')->nullOnDelete();
            $table->foreignUuid('alighting_stop_id')->nullable()->after('boarding_stop_id')
                ->constrained('trip_stops')->nullOnDelete();
        });

        $this->backfillExistingTrips();
    }

    public function down(): void
    {
        Schema::table('bookings', function (Blueprint $table) {
            $table->dropConstrainedForeignId('boarding_stop_id');
            $table->dropConstrainedForeignId('alighting_stop_id');
        });
        Schema::dropIfExists('trip_stops');
    }

    /**
     * Existing trips become departure → waypoints → arrival, with prices
     * pro rata of the straight-line distance and bookings spanning the
     * whole trip (which is what they paid for).
     */
    private function backfillExistingTrips(): void
    {
        $trips = DB::table('trips')
            ->select([
                'id', 'origin_name', 'destination_name', 'waypoints', 'scheduled_at', 'created_at', 'price_per_seat',
                DB::raw('ST_Y(origin_geom::geometry) as origin_lat'),
                DB::raw('ST_X(origin_geom::geometry) as origin_lng'),
                DB::raw('ST_Y(destination_geom::geometry) as destination_lat'),
                DB::raw('ST_X(destination_geom::geometry) as destination_lng'),
            ])
            ->get();

        foreach ($trips as $trip) {
            // Unnamed legacy trips: nearest known city, as the Trip model
            // already does when displaying them.
            $points = [[
                'name' => $trip->origin_name ?: Trip::closestCity((float) $trip->origin_lat, (float) $trip->origin_lng),
                'lat' => (float) $trip->origin_lat,
                'lng' => (float) $trip->origin_lng,
            ]];
            foreach (json_decode($trip->waypoints ?? '[]', true) ?: [] as $wp) {
                if (isset($wp['lat'], $wp['lng'])) {
                    $points[] = ['name' => $wp['name'] ?? 'Étape', 'lat' => (float) $wp['lat'], 'lng' => (float) $wp['lng']];
                }
            }
            $points[] = [
                'name' => $trip->destination_name ?: Trip::closestCity((float) $trip->destination_lat, (float) $trip->destination_lng),
                'lat' => (float) $trip->destination_lat,
                'lng' => (float) $trip->destination_lng,
            ];

            $cumulative = [0.0];
            for ($i = 1; $i < count($points); $i++) {
                $cumulative[$i] = $cumulative[$i - 1] + $this->haversineKm($points[$i - 1], $points[$i]);
            }
            $total = max(end($cumulative), 0.001);
            $departure = $trip->scheduled_at ?? $trip->created_at;
            $last = count($points) - 1;
            $stopIds = [];

            foreach ($points as $i => $point) {
                $id = (string) Str::uuid7();
                $stopIds[$i] = $id;
                $price = $i === $last ? (float) $trip->price_per_seat : round($trip->price_per_seat * $cumulative[$i] / $total / 50) * 50;
                DB::table('trip_stops')->insert([
                    'id' => $id,
                    'trip_id' => $trip->id,
                    'position' => $i,
                    'name' => mb_substr($point['name'], 0, 120),
                    'lat' => $point['lat'],
                    'lng' => $point['lng'],
                    'location_geom' => DB::raw(sprintf(
                        'ST_SetSRID(ST_MakePoint(%s, %s), 4326)::geography',
                        number_format($point['lng'], 8, '.', ''),
                        number_format($point['lat'], 8, '.', ''),
                    )),
                    // Intermediate times are unknown for legacy trips.
                    'scheduled_at' => $i === 0 ? $departure : null,
                    'price_from_origin' => $price,
                    'created_at' => now(),
                    'updated_at' => now(),
                ]);
            }

            DB::table('bookings')->where('trip_id', $trip->id)->update([
                'boarding_stop_id' => $stopIds[0],
                'alighting_stop_id' => $stopIds[$last],
            ]);
        }
    }

    private function haversineKm(array $a, array $b): float
    {
        $dLat = deg2rad($b['lat'] - $a['lat']);
        $dLng = deg2rad($b['lng'] - $a['lng']);
        $h = sin($dLat / 2) ** 2 + cos(deg2rad($a['lat'])) * cos(deg2rad($b['lat'])) * sin($dLng / 2) ** 2;

        return 2 * 6371 * asin(min(1.0, sqrt($h)));
    }
};
