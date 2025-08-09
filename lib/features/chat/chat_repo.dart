import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

final _db = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

class ChatRepo {
  Stream<QuerySnapshot<Map<String, dynamic>>> matchesStream() {
    final me = _auth.currentUser!.uid;
    return _db
        .collection('matches')
        .where('participants', arrayContains: me)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messagesStream(String matchId) {
    return _db
        .collection('matches')
        .doc(matchId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots();
  }

  Future<void> sendMessage(String matchId, String text) async {
    final me = _auth.currentUser!.uid;
    final msgCol = _db
        .collection('matches')
        .doc(matchId)
        .collection('messages');
    await msgCol.add({
      'senderUid': me,
      'body': text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    await _db.collection('matches').doc(matchId).update({
      'lastMessageAt': FieldValue.serverTimestamp(),
    });
  }
}
