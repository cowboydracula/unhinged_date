import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'models.dart';

final _db = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

class ProfileRepo {
  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection('profiles');

  Future<Profile?> getMyProfile() async {
    final uid = _auth.currentUser!.uid;
    final doc = await _col.doc(uid).get();
    if (!doc.exists) return null;
    return Profile.fromDoc(doc.id, doc.data()!);
  }

  Future<void> upsertMyProfile(Profile p) async {
    final uid = _auth.currentUser!.uid;
    await _col.doc(uid).set(p.toMap(), SetOptions(merge: true));
  }

  Stream<Profile?> watchProfile(String uid) {
    return _col
        .doc(uid)
        .snapshots()
        .map((d) => d.exists ? Profile.fromDoc(d.id, d.data()!) : null);
  }

  Future<void> setHideMode(bool hide) async {
    final uid = _auth.currentUser!.uid;
    await _col.doc(uid).set({'hideMode': hide}, SetOptions(merge: true));
  }
}
