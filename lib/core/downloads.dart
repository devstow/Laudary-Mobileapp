import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Puts downloaded documents (receipt PDFs) where the user can actually find them, and opens them.
///
/// Android: the app's private cache/temp directory is invisible to the user and other apps, and
/// `file://` URLs can't be handed to a viewer at all (FileUriExposedException / no handler) — which
/// is why "Download" used to end in a toast with an internal path and no file to open. The native
/// side (android/.../MainActivity.kt, channel `smartwash/downloads`) writes the bytes into the public
/// **Downloads/SmartWash** folder through MediaStore (no storage permission needed on Android 10+;
/// app-scoped external storage shared via FileProvider on 7–9) and opens the resulting content URI
/// in the user's PDF viewer with a read grant.
///
/// Other platforms: temp directory + the platform opener (url_launcher), as before.
class Downloads {
  Downloads._();

  static const MethodChannel _channel = MethodChannel('smartwash/downloads');

  /// Saves [bytes] as [name] and returns where it went ([SavedFile.path] is what to show the user).
  static Future<SavedFile> save(String name, Uint8List bytes, {String mime = 'application/pdf'}) async {
    if (!kIsWeb && Platform.isAndroid) {
      final res = await _channel.invokeMapMethod<String, String>('saveToDownloads', {
        'name': name,
        'mime': mime,
        'bytes': bytes,
      });
      if (res == null || res['uri'] == null) throw StateError('The download could not be saved.');
      return SavedFile(uri: res['uri']!, path: res['path'] ?? name);
    }
    final file = File('${Directory.systemTemp.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return SavedFile(uri: Uri.file(file.path).toString(), path: file.path);
  }

  /// Opens a saved file in an external viewer. False when no app can show it (the file is still saved).
  static Future<bool> open(SavedFile file, {String mime = 'application/pdf'}) async {
    if (!kIsWeb && Platform.isAndroid) {
      return await _channel.invokeMethod<bool>('openFile', {'uri': file.uri, 'mime': mime}) ?? false;
    }
    final uri = Uri.parse(file.uri);
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class SavedFile {
  const SavedFile({required this.uri, required this.path});

  /// Opaque handle for [Downloads.open] (a `content://` URI on Android).
  final String uri;

  /// Human-readable location, e.g. `Download/SmartWash/Receipt-RCT-000012.pdf`.
  final String path;
}
