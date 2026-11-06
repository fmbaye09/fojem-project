<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;

/**
 * Pièces jointes du chat. Les messages eux-mêmes vivent dans Firestore ;
 * le backend n'héberge que leurs fichiers : messages vocaux, photos et
 * documents.
 */
class ChatController extends Controller
{
    /** Photos et documents : 10 Mo, la limite d'upload du serveur. */
    public function uploadAttachment(Request $request)
    {
        $request->validate([
            'file' => ['required', 'file', 'mimes:jpg,jpeg,png,webp,heic,heif,pdf,doc,docx,xls,xlsx,ppt,pptx,txt', 'max:10240'],
        ]);

        $file = $request->file('file');
        $isImage = str_starts_with((string) $file->getMimeType(), 'image/');
        $path = $file->store('chat-attachments', 'public');

        return response()->json([
            'url' => $request->schemeAndHttpHost().'/storage/'.$path,
            'kind' => $isImage ? 'image' : 'file',
            // Nom affiché dans la bulle ; le fichier est stocké sous un nom aléatoire.
            'name' => mb_substr(basename($file->getClientOriginalName()), 0, 120),
            'size' => $file->getSize(),
        ], 201);
    }

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
