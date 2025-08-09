// lib/features/profile/profile_repo.dart
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'models.dart';

/// Repository for reading/writing user profiles and managing photos.
class ProfileRepo {
  ProfileRepo({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseStorage? storage,
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;

  String get _uid => _auth.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> _doc([String? uid]) =>
      _db.collection('profiles').doc(uid ?? _uid);

  /// Ensure a minimal profile exists for the current user.
  Future<void> ensureProfile() async {
    final u = _auth.currentUser!;
    await _doc().set({
      'displayName': u.displayName ?? 'New User',
      'bio': FieldValue.delete(),
      'photos': FieldValue.delete(),
      'program': 'None',
      'showStreak': false,
      'hideMode': false,
      'interests': <String>[],
      'minAge': 21,
      'maxAge': 60,
      'maxDistanceKm': 100,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Read my profile once. Returns null if it doesn't exist.
  Future<Profile?> getMyProfile() async {
    final snap = await _doc().get();
    if (!snap.exists) return null;
    return Profile.fromDoc(snap.id, snap.data()!);
  }

  /// Read another user's profile once.
  Future<Profile?> getProfile(String uid) async {
    final snap = await _doc(uid).get();
    if (!snap.exists) return null;
    return Profile.fromDoc(snap.id, snap.data()!);
  }

  /// Watch a profile (mine or someone else's).
  Stream<Profile?> watchProfile(String uid) {
    return _doc(uid).snapshots().map(
      (d) => d.exists ? Profile.fromDoc(d.id, d.data()!) : null,
    );
  }

  /// Upsert *my* profile from a model.
  Future<void> upsertMyProfile(Profile p) async {
    final data = p.toMap()
      ..addAll({
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt':
            FieldValue.serverTimestamp(), // set-once; merge keeps existing
      });
    await _doc().set(data, SetOptions(merge: true));
  }

  /// Patch fields on *my* profile.
  Future<void> updateMy(Map<String, dynamic> data) async {
    await _doc().set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Toggle discovery visibility.
  Future<void> setHideMode(bool hide) => updateMy({'hideMode': hide});

  // -------------------- Photos --------------------

  /// Upload a photo file to Storage and add its URL to my profile.
  Future<String> uploadPhotoAndAttach(File file, {String? filename}) async {
    final name =
        filename ??
        '${DateTime.now().millisecondsSinceEpoch}_${file.path.split(Platform.pathSeparator).last}';
    final ref = _storage.ref('userPhotos/$_uid/$name');

    final task = await ref.putFile(file);
    final url = await task.ref.getDownloadURL();

    await _doc().set({
      'photos': FieldValue.arrayUnion([url]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return url;
  }

  /// Remove a photo URL from my profile and best-effort delete from Storage.
  Future<void> removePhoto(String url) async {
    await _doc().set({
      'photos': FieldValue.arrayRemove([url]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // Best-effort: delete the underlying object if it's in our bucket
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {
      // ignore (e.g., external URL or already deleted)
    }
  }
}
