<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Notification;
use Illuminate\Http\Request;

class NotificationController extends Controller
{
    /**
     * List authenticated user's notifications (newest first).
     */
    public function index(Request $request)
    {
        $query = Notification::where('user_id', $request->user()->id)
            ->orderByDesc('created_at');

        if ($request->boolean('unread_only')) {
            $query->whereNull('read_at');
        }

        return response()->json($query->paginate($request->integer('per_page', 30)));
    }

    /**
     * Mark a single notification as read.
     */
    public function markRead(Request $request, Notification $notification)
    {
        if ($notification->user_id !== $request->user()->id) {
            return response()->json(['message' => 'Non autorisé.'], 403);
        }

        $notification->update(['read_at' => now()]);

        return response()->json(['notification' => $notification]);
    }

    /**
     * Mark ALL unread notifications as read in a single sweep.
     */
    public function markAllRead(Request $request)
    {
        $count = Notification::where('user_id', $request->user()->id)
            ->whereNull('read_at')
            ->update(['read_at' => now()]);

        return response()->json(['marked' => $count]);
    }

    /**
     * Count unread notifications — used by the badge on the nav bar.
     */
    public function unreadCount(Request $request)
    {
        $count = Notification::where('user_id', $request->user()->id)
            ->whereNull('read_at')
            ->count();

        return response()->json(['unread_count' => $count]);
    }

    /**
     * Register/update the device FCM token for push notifications.
     */
    public function registerFcmToken(Request $request)
    {
        $request->validate(['fcm_token' => 'required|string|max:512']);

        $request->user()->update(['fcm_token' => $request->input('fcm_token')]);

        return response()->json(['message' => 'Token enregistré.']);
    }

    /**
     * Notify a user about a new chat message.
     */
    public function sendChatNotification(Request $request)
    {
        $request->validate([
            'recipient_id' => 'required|uuid|exists:users,id',
            'message' => 'required|string|max:1000',
            'conversation_id' => 'nullable|string',
        ]);

        $recipient = \App\Models\User::findOrFail($request->input('recipient_id'));
        $sender = $request->user();

        if ($recipient->id === $sender->id) {
            return response()->json(['message' => 'Cannot send notification to yourself.'], 422);
        }

        $notification = app(\App\Services\NotificationService::class)->chatMessage(
            $recipient,
            $sender,
            $request->input('message'),
            $request->input('conversation_id'),
        );

        return response()->json(['notification' => $notification]);
    }
}
