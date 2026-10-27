<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

/**
 * Pièces jointes du chat. Les messages eux-mêmes vivent dans Firestore ;
 * le backend n'héberge que les fichiers audio des messages vocaux.
 */
class ChatController extends Controller
{
    /** Messages vocaux : 5 Mo couvrent largement 2 minutes d'AAC. */
    public function uploadVoice(Request $request)
    {
        $request->validate([
            // Un .m4a est souvent détecté comme « video/mp4 » : le conteneur est le même.
            'audio' => ['required', 'file', 'mimetypes:audio/mp4,audio/x-m4a,audio/m4a,audio/aac,audio/mpeg,video/mp4', 'max:5120'],
            'duration_ms' => ['required', 'integer', 'min:1', 'max:300000'],
        ]);

        $path = $request->file('audio')->store('chat-voice', 'public');

        return response()->json([
            'url' => $request->schemeAndHttpHost().'/storage/'.$path,
            'duration_ms' => $request->integer('duration_ms'),
        ], 201);
    }
}
