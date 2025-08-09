import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final _db = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

class SafetyRepo {
  Future<void> block(String subjectUid, {String? reason}) async {
    final me = _auth.currentUser!.uid;
    await _db.doc('blocks/$me/blocked/$subjectUid').set({
      'createdAt': FieldValue.serverTimestamp(),
      if (reason != null) 'reason': reason,
    });
  }

  Future<void> report(String subjectUid, String reason) async {
    final me = _auth.currentUser!.uid;
    await _db.collection('reports').add({
      'actorUid': me,
      'subjectUid': subjectUid,
      'reason': reason,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Set<String>> myBlocked() async {
    final me = _auth.currentUser!.uid;
    final qs = await _db
        .collection('blocks')
        .doc(me)
        .collection('blocked')
        .get();
    return qs.docs.map((d) => d.id).toSet();
  }

  // Optional: who blocked me (to fully filter)
  Future<Set<String>> whoBlockedMe() async {
    final me = _auth.currentUser!.uid;
    final qs = await _db
        .collectionGroup('blocked')
        .where(FieldPath.documentId, isEqualTo: me)
        .get();
    return qs.docs.map((d) => d.reference.parent.parent!.id).toSet();
  }
}
