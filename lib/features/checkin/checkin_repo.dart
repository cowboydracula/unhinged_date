import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final _db = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

class CheckinRepo {
  Future<void> writeToday({String? note}) async {
    final me = _auth.currentUser!.uid;
    final day = DateTime.now().toIso8601String().substring(0, 10);
    await _db.doc('profiles/$me/checkins/$day').set({
      if (note != null) 'note': note,
    }, SetOptions(merge: true));
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> watch() {
    final me = _auth.currentUser!.uid;
    return _db
        .collection('profiles')
        .doc(me)
        .collection('checkins')
        .orderBy(FieldPath.documentId)
        .limitToLast(30)
        .snapshots();
  }
}
