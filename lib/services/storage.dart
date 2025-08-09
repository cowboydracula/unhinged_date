// lib/services/storage.dart
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Thin wrapper around Firebase Storage for user photo uploads and deletes.
/// Paths use: `userPhotos/{uid}/{filename}`
///
/// Storage rules (recommended):
/// ```
/// rules_version = '2';
/// service firebase.storage {
///   match /b/{bucket}/o {
///     match /userPhotos/{uid}/{file} {
///       allow read: if true; // or restrict further later
///       allow write: if request.auth != null && request.auth.uid == uid;
///     }
///   }
/// }
/// ```
class StorageService {
  StorageService({FirebaseStorage? storage, FirebaseAuth? auth})
    : _storage = storage ?? FirebaseStorage.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseStorage _storage;
  final FirebaseAuth _auth;

  String get _uid {
    final u = _auth.currentUser;
    if (u == null) {
      throw StateError('Not signed in');
    }
    return u.uid;
  }

  /// Upload an [XFile] (e.g., from image_picker) to `userPhotos/{uid}/...`
  /// Returns the download URL.
  Future<String> uploadXFile(XFile xfile, {String? filename}) async {
    // Prefer putFile if we have a path; it's memory-friendly for large images.
    if (xfile.path.isNotEmpty) {
      return uploadFile(
        File(xfile.path),
        filename: filename ?? _defaultName(xfile.name),
      );
    }
    // Fallback to bytes
    final bytes = await xfile.readAsBytes();
    return uploadBytes(bytes, filename: filename ?? _defaultName(xfile.name));
  }

  /// Upload a local [File] to Storage and return the download URL.
  Future<String> uploadFile(
    File file, {
    String? filename,
    SettableMetadata? metadata,
  }) async {
    final name = filename ?? _defaultName(_basename(file.path));
    final ref = _storage.ref('userPhotos/$_uid/$name');

    final meta =
        metadata ?? SettableMetadata(contentType: _inferContentType(name));

    final task = await ref.putFile(file, meta);
    return task.ref.getDownloadURL();
  }

  /// Upload raw [Uint8List] bytes and return the download URL.
  Future<String> uploadBytes(
    Uint8List data, {
    String filename = 'upload.jpg',
    SettableMetadata? metadata,
  }) async {
    final name = _defaultName(filename);
    final ref = _storage.ref('userPhotos/$_uid/$name');

    final meta =
        metadata ?? SettableMetadata(contentType: _inferContentType(name));

    final task = await ref.putData(data, meta);
    return task.ref.getDownloadURL();
  }

  /// Remove an object by its HTTPS download [url]. No-op if not found.
  Future<void> deleteByUrl(String url) async {
    try {
      final ref = _storage.refFromURL(url);
      await ref.delete();
    } catch (_) {
      // ignore (already deleted, wrong bucket, or token URL not from our project)
    }
  }

  /// List files under `userPhotos/{uid}` (useful for admin tools or cleanup).
  Future<ListResult> listMyPhotos({int? maxResults, String? pageToken}) {
    final ref = _storage.ref('userPhotos/$_uid');
    return ref.list(ListOptions(maxResults: maxResults, pageToken: pageToken));
  }

  // -------------------- helpers --------------------

  String _defaultName(String originalName) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(1 << 32).toRadixString(16);
    final base = _stripExt(_basename(originalName));
    final ext = _extname(originalName).toLowerCase();
    final safeBase = base.isEmpty
        ? 'photo'
        : base.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final safeExt = ext.isEmpty ? '.jpg' : ext;
    return '${ts}_$rand\_$safeBase$safeExt';
  }

  String _basename(String path) {
    final i = path.lastIndexOf(Platform.pathSeparator);
    if (i == -1) return path;
    return path.substring(i + 1);
  }

  String _extname(String filename) {
    final i = filename.lastIndexOf('.');
    if (i == -1 || i == filename.length - 1) return '';
    return filename.substring(i);
  }

  String _stripExt(String filename) {
    final i = filename.lastIndexOf('.');
    if (i == -1) return filename;
    return filename.substring(0, i);
  }

  String _inferContentType(String filename) {
    final ext = _extname(filename).toLowerCase();
    switch (ext) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.heic':
      case '.heif':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }
}
