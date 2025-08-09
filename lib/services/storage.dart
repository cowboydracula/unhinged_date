// lib/services/storage.dart
import 'dart:io' show File;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  final _storage = FirebaseStorage.instance;

  // Upload from ImagePicker XFile -> returns https URL
  Future<String> uploadXFile(XFile x) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('Not signed in');

    final ext = _extFromName(x.name); // best-effort extension
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
    final path = 'profiles/$uid/photos/$fileName';
    final ref = _storage.ref().child(path);

    final meta = SettableMetadata(contentType: _guessContentType(ext));

    UploadTask task;
    if (kIsWeb) {
      final bytes = await x.readAsBytes();
      task = ref.putData(bytes, meta);
    } else {
      task = ref.putFile(File(x.path), meta);
    }

    // IMPORTANT: await the *same* ref we just uploaded to
    final snap = await task.whenComplete(() {});
    // Throws "no object exists" if you used a different ref or upload failed
    final url = await snap.ref.getDownloadURL();
    return url;
  }

  Future<void> deleteByUrl(String url) async {
    final ref = _storage.refFromURL(url);
    await ref.delete();
  }

  String _extFromName(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'png';
    if (n.endsWith('.webp')) return 'webp';
    if (n.endsWith('.heic')) return 'heic';
    if (n.endsWith('.heif')) return 'heif';
    if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'jpg';
    return 'jpg';
  }

  String _guessContentType(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      default:
        return 'image/jpeg';
    }
  }
}
