<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Http\Requests\Reviews\StoreReviewRequest;
use App\Models\Booking;
use App\Models\Review;
use Illuminate\Support\Facades\DB;

class ReviewController extends Controller
{
    /**
     * Submit a review for a completed booking. Whichever side did not
     * write it becomes the reviewee. When the reviewee is a driver, their
     * drivers.average_rating is recalculated in the same DB transaction
     * from the mean of all their received ratings (punctuality, driving,
     * communication, safety).
     */
    public function store(StoreReviewRequest $request)
    {
        $booking = Booking::with('trip.driverProfile.user')->findOrFail($request->input('booking_id'));

        if ($booking->status !== Booking::STATUS_COMPLETED) {
            return response()->json(['message' => 'Seul un trajet termine peut etre note.'], 422);
        }

        $user = $request->user();
        $driverUserId = $booking->trip->driverProfile->user_id;

        if ($user->id === $booking->passenger_id) {
            $revieweeId = $driverUserId;
        } elseif ($user->id === $driverUserId) {
            $revieweeId = $booking->passenger_id;
        } else {
            return response()->json(['message' => 'Non autorise.'], 403);
        }

        if ($booking->review()->exists()) {
            return response()->json(['message' => 'Ce trajet a deja ete note.'], 422);
        }

        $review = DB::transaction(function () use ($request, $booking, $user, $revieweeId, $driverUserId) {
            $review = Review::create([
                'booking_id' => $booking->id,
                'reviewer_id' => $user->id,
                'reviewee_id' => $revieweeId,
                'punctuality_rating' => $request->input('punctuality_rating'),
                'driving_rating' => $request->input('driving_rating'),
                'communication_rating' => $request->input('communication_rating'),
                'safety_rating' => $request->input('safety_rating'),
                'comment' => $request->input('comment'),
            ]);

            if ($revieweeId === $driverUserId) {
                $this->recalculateDriverRating($driverUserId);
            }

            return $review;
        });

        return response()->json(['review' => $review], 201);
    }

    private function recalculateDriverRating(string $driverUserId): void
    {
        $driver = \App\Models\Driver::where('user_id', $driverUserId)->lockForUpdate()->first();

        if (! $driver) {
            return;
        }

        $average = Review::where('reviewee_id', $driverUserId)
            ->selectRaw('AVG(
                (
                    punctuality_rating
                    + COALESCE(driving_rating, punctuality_rating)
                    + communication_rating
                    + safety_rating
                ) / 4.0
            ) as avg_rating')
            ->value('avg_rating');

        $driver->update(['average_rating' => round((float) $average, 2)]);
    }
}
