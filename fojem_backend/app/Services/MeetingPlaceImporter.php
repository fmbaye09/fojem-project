<?php

namespace App\Services;

use App\Models\MeetingPlace;

/**
 * Met à jour les lieux de rendez-vous d'OpenStreetMap pour tout le Sénégal.
 * Le serveur public est souvent saturé : on réessaie en espaçant les essais.
 */
class MeetingPlaceImporter
{
    public function __construct(private readonly OverpassService $overpass)
    {
    }

    /** @return array{imported: int, removed: int}|null null si le serveur n'a jamais répondu */
    public function import(int $attempts = 4, int $firstWaitSeconds = 30): ?array
    {
        $places = null;
        for ($i = 0; $i < $attempts && $places === null; $i++) {
            if ($i > 0) {
                sleep($firstWaitSeconds * 2 ** ($i - 1));
            }
            $places = $this->overpass->placesIn(OverpassService::SENEGAL_BBOX);
        }
        // Une réponse vide ressemble plus à une panne qu'à un pays sans stations.
        if ($places === null || $places === []) {
            return null;
        }

        $ids = [];
        foreach ($places as $place) {
            MeetingPlace::updateOrCreate(['osm_id' => $place['osm_id']], $place);
            $ids[] = $place['osm_id'];
        }
        $removed = MeetingPlace::whereNotIn('osm_id', $ids)->delete();

        return ['imported' => count($ids), 'removed' => $removed];
    }
}
