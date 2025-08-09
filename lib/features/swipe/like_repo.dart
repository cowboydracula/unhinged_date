import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final _db = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

class LikeRepo {
  Future<void> likeUser(String toUid) async {
    final me = _auth.currentUser!.uid;
    await _db.collection('likes').add({
      'fromUid': me,
      'toUid': toUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<Set<String>> myLikedUids() async {
    final me = _auth.currentUser!.uid;
    final qs = await _db
        .collection('likes')
        .where('fromUid', isEqualTo: me)
        .get();
    return qs.docs.map((d) => d.data()['toUid'] as String).toSet();
  }
}
