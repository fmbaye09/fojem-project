<?php

use App\Http\Controllers\Api\Admin\AdminAuthController;
use App\Http\Controllers\Api\Admin\AdminRoleController;
use App\Http\Controllers\Api\Admin\AdminUserController;
use App\Http\Controllers\Api\Admin\DisputeController as AdminDisputeController;
use App\Http\Controllers\Api\Admin\DriverController as AdminDriverController;
use App\Http\Controllers\Api\Admin\OverviewController;
use App\Http\Controllers\Api\Admin\PayoutRequestController;
use App\Http\Controllers\Api\Admin\PlatformSettingController;
use App\Http\Controllers\Api\Admin\SosAlertController as AdminSosAlertController;
use App\Http\Controllers\Api\Admin\StatsController;
use App\Http\Controllers\Api\Admin\TransactionController;
use App\Http\Controllers\Api\Admin\TripController as AdminTripController;
use App\Http\Controllers\Api\Admin\UserController as AdminUserManagementController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BookingController;
use App\Http\Controllers\Api\ChatController;
use App\Http\Controllers\Api\DisputeController;
use App\Http\Controllers\Api\DriverController;
use App\Http\Controllers\Api\DriverDocumentController;
use App\Http\Controllers\Api\IdentityVerificationController;
use App\Http\Controllers\Api\MatchingController;
use App\Http\Controllers\Api\NotificationController;
use App\Http\Controllers\Api\ProfileController;
use App\Http\Controllers\Api\ReviewController;
use App\Http\Controllers\Api\RideRequestController;
use App\Http\Controllers\Api\SosAlertController;
use App\Http\Controllers\Api\TripController;
use App\Http\Controllers\Api\UserController;
use App\Http\Controllers\Api\VehicleController;
use App\Http\Controllers\Api\WalletController;
use Illuminate\Support\Facades\Route;

Route::prefix('auth')->group(function () {
    Route::middleware('throttle:10,1')->group(function () {
        Route::post('register', [AuthController::class, 'register']);
        Route::post('login', [AuthController::class, 'login']);
    });

    Route::middleware('auth:sanctum')->group(function () {
        Route::post('logout', [AuthController::class, 'logout']);
        Route::get('me', [AuthController::class, 'me']);
        Route::post('become-driver', [AuthController::class, 'becomeDriver']);
    });
});

// Public trip search does not require auth so both apps can show results
// before login, but every other trip/booking action does.
Route::get('trips/search', [TripController::class, 'search']);

Route::middleware('auth:sanctum')->group(function () {
    Route::patch('profile', [ProfileController::class, 'update']);
    Route::post('profile/photo', [ProfileController::class, 'updatePhoto']);
    Route::get('profile/identity', [IdentityVerificationController::class, 'show']);
    Route::post('profile/identity', [IdentityVerificationController::class, 'submit']);

    Route::get('driver/onboarding', [DriverDocumentController::class, 'getOnboarding']);
    Route::post('driver/onboarding', [DriverDocumentController::class, 'submitOnboarding']);
    Route::post('driver/documents', [DriverDocumentController::class, 'store']);
    Route::get('driver/documents', [DriverDocumentController::class, 'index']);
    Route::patch('driver/vehicle-info', [DriverController::class, 'updateVehicleInfo']);

    Route::post('vehicles', [VehicleController::class, 'store']);
    Route::get('vehicles', [VehicleController::class, 'index']);
    Route::get('vehicles/{vehicle}', [VehicleController::class, 'show']);

    Route::post('trips', [TripController::class, 'store']);
    Route::get('trips/mine', [TripController::class, 'mine']);
    Route::get('trips/{trip}', [TripController::class, 'show']);
    Route::post('trips/{trip}/cancel', [TripController::class, 'cancel']);
    Route::post('trips/{trip}/start', [TripController::class, 'start']);
    Route::post('trips/{trip}/complete', [TripController::class, 'complete']);
    Route::post('trips/{trip}/location', [TripController::class, 'updateLocation']);
    Route::get('trips/{trip}/nearby-ride-requests', [RideRequestController::class, 'nearTrip']);
    Route::get('trips/{trip}/bookings', [BookingController::class, 'forTrip']);

    Route::post('ride-requests', [RideRequestController::class, 'store']);
    Route::get('ride-requests/mine', [RideRequestController::class, 'mine']);
    Route::post('ride-requests/{rideRequest}/cancel', [RideRequestController::class, 'cancel']);
    Route::get('ride-requests/{rideRequest}/matches', [MatchingController::class, 'bestMatches']);

    Route::post('bookings', [BookingController::class, 'store']);
    Route::get('bookings/mine', [BookingController::class, 'mine']);
    Route::get('bookings/received', [BookingController::class, 'received']);
    Route::get('bookings/{booking}', [BookingController::class, 'show']);
    Route::post('bookings/{booking}/accept', [BookingController::class, 'accept']);
    Route::post('bookings/{booking}/reject', [BookingController::class, 'reject']);
    Route::post('bookings/{booking}/cancel', [BookingController::class, 'cancel']);
    Route::post('trips/{trip}/board-passenger', [BookingController::class, 'boardPassenger']);
    Route::post('bookings/{booking}/board', [BookingController::class, 'board']);
    Route::post('bookings/{booking}/complete', [BookingController::class, 'complete']);

    Route::get('wallet', [WalletController::class, 'show']);
    Route::get('wallet/transactions', [WalletController::class, 'transactions']);

    Route::post('reviews', [ReviewController::class, 'store']);

    Route::post('sos-alerts', [SosAlertController::class, 'store']);

    Route::post('disputes', [DisputeController::class, 'store']);
    Route::get('disputes/mine', [DisputeController::class, 'mine']);

    Route::get('users/{user}', [UserController::class, 'show']);
    Route::get('drivers/{userId}', [DriverController::class, 'show']);

    Route::get('notifications', [NotificationController::class, 'index']);
    Route::get('notifications/unread-count', [NotificationController::class, 'unreadCount']);
    Route::post('notifications/mark-all-read', [NotificationController::class, 'markAllRead']);
    Route::post('notifications/{notification}/read', [NotificationController::class, 'markRead']);
    Route::post('notifications/chat-message', [NotificationController::class, 'sendChatNotification']);
    Route::post('chat/voice', [ChatController::class, 'uploadVoice']);
    Route::post('fcm-token', [NotificationController::class, 'registerFcmToken']);
});

// Admin dashboard API. Entirely separate auth from the routes above: a
// distinct guard/model (AdminUser via the "admin" Sanctum guard) and every
// route requires both a valid admin token carrying the "admin" ability
// (see AdminAuthController::login()) and, per action, the matching
// admin_permissions row (EnsureAdminHasPermission / "admin.permission:<resource>,<action>").
Route::prefix('admin')->group(function () {
    Route::prefix('auth')->group(function () {
        Route::middleware('throttle:10,1')->post('login', [AdminAuthController::class, 'login']);

        Route::middleware(['auth:admin', 'abilities:admin', 'admin.active'])->group(function () {
            Route::post('logout', [AdminAuthController::class, 'logout']);
            Route::get('me', [AdminAuthController::class, 'me']);
        });
    });

    Route::middleware(['auth:admin', 'abilities:admin', 'admin.active'])->group(function () {
        // Overview and stats are read-only dashboard aggregates available to
        // any authenticated active admin - not gated behind a per-resource
        // admin_permissions row since they expose no write capability and no
        // single-resource sensitive detail beyond what each dedicated,
        // permission-gated endpoint below already exposes in full.
        Route::get('overview', [OverviewController::class, 'index']);
        Route::get('map/trips', [OverviewController::class, 'mapTrips']);
        Route::get('stats/timeseries', [StatsController::class, 'timeseries']);
        Route::get('stats/booking-acceptance-rate', [StatsController::class, 'bookingAcceptanceRate']);
        Route::get('stats/average-rating', [StatsController::class, 'averageRating']);
        Route::get('stats/transactions-breakdown', [StatsController::class, 'transactionsBreakdown']);
        Route::get('stats/new-accounts-timeseries', [StatsController::class, 'newAccountsTimeseries']);

        Route::middleware('admin.permission:users,view')->group(function () {
            Route::get('users', [AdminUserManagementController::class, 'index']);
            Route::get('drivers', [AdminDriverController::class, 'index']);
        });
        Route::patch('users/{user}/status', [AdminUserManagementController::class, 'updateStatus'])
            ->middleware('admin.permission:users,edit');
        Route::patch('users/{user}/identity-review', [AdminUserManagementController::class, 'reviewIdentity'])
            ->middleware('admin.permission:users,edit');

        Route::middleware('admin.permission:driver_documents,view')->group(function () {
            Route::get('drivers/{driver}/documents', [AdminDriverController::class, 'documents']);
            Route::get('drivers/{driver}/documents/{docId}/file', [AdminDriverController::class, 'file']);
        });
        Route::patch('drivers/{driver}/documents/{docId}/review', [AdminDriverController::class, 'reviewDocument'])
            ->middleware('admin.permission:driver_documents,edit');

        Route::middleware('admin.permission:trips,view')->group(function () {
            Route::get('trips', [AdminTripController::class, 'index']);
            Route::get('trips/{trip}', [AdminTripController::class, 'show']);
        });
        Route::post('trips/{trip}/cancel', [AdminTripController::class, 'cancel'])
            ->middleware('admin.permission:trips,edit');

        Route::middleware('admin.permission:transactions,view')
            ->get('transactions', [TransactionController::class, 'index']);

        Route::middleware('admin.permission:payout_requests,view')
            ->get('payout-requests', [PayoutRequestController::class, 'index']);
        Route::patch('payout-requests/{payoutRequest}/process', [PayoutRequestController::class, 'process'])
            ->middleware('admin.permission:payout_requests,edit');

        Route::middleware('admin.permission:sos_alerts,view')
            ->get('sos-alerts', [AdminSosAlertController::class, 'index']);
        Route::patch('sos-alerts/{sosAlert}', [AdminSosAlertController::class, 'update'])
            ->middleware('admin.permission:sos_alerts,edit');

        Route::middleware('admin.permission:disputes,view')
            ->get('disputes', [AdminDisputeController::class, 'index']);
        Route::patch('disputes/{dispute}', [AdminDisputeController::class, 'update'])
            ->middleware('admin.permission:disputes,edit');

        Route::middleware('admin.permission:admin_users,view')
            ->get('admin-users', [AdminUserController::class, 'index']);
        Route::post('admin-users', [AdminUserController::class, 'store'])
            ->middleware('admin.permission:admin_users,edit');

        Route::middleware('admin.permission:admin_users,view')
            ->get('admin-roles', [AdminRoleController::class, 'index']);

        Route::middleware('admin.permission:platform_settings,view')
            ->get('platform-settings', [PlatformSettingController::class, 'index']);
        Route::patch('platform-settings/{platformSetting}', [PlatformSettingController::class, 'update'])
            ->middleware('admin.permission:platform_settings,edit');
    });
});
