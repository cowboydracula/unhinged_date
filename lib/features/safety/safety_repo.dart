// lib/features/safety/safety_repo.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Safety / blocking utilities (client only writes/reads *own* list).
/// No "who blocked me" reads here; server feed handles that.
class SafetyRepo {
  SafetyRepo(this._db);
  final FirebaseFirestore _db;

  /// Block [subjectUid] by [me].
  Future<void> blockUser(String me, String subjectUid) async {
    await _db
        .collection('blocks')
        .doc(me)
        .collection('blocked')
        .doc(subjectUid)
        .set({
          'blockerUid': me,
          'subjectUid': subjectUid,
          'createdAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  /// Unblock [subjectUid] by [me].
  Future<void> unblockUser(String me, String subjectUid) async {
    await _db
        .collection('blocks')
        .doc(me)
        .collection('blocked')
        .doc(subjectUid)
        .delete();
  }

  /// Live stream of UIDs I have blocked (owner-only).
  Stream<Set<String>> blockedByMeStream(String me) {
    return _db
        .collection('blocks')
        .doc(me)
        .collection('blocked')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toSet());
  }
}
