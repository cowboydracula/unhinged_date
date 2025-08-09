import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../profile/models.dart';
import '../safety/safety_repo.dart';
import '../swipe/like_repo.dart';

final _db = FirebaseFirestore.instance;
final _auth = FirebaseAuth.instance;

class FeedRepo {
  final SafetyRepo safety;
  final LikeRepo likes;
  FeedRepo({required this.safety, required this.likes});

  DocumentSnapshot? _cursor;

  Future<({List<Profile> cards, bool hasMore})> nextPage({
    int limit = 25,
  }) async {
    final me = _auth.currentUser!.uid;

    // Gather exclusion sets
    final blocked = await safety.myBlocked();
    final blockedMe = await safety.whoBlockedMe();
    final liked = await likes.myLikedUids();

    final matchesQs = await _db
        .collection('matches')
        .where('participants', arrayContains: me)
        .get();
    final matched =
        matchesQs.docs
            .expand((d) => List<String>.from(d['participants']))
            .toSet()
          ..remove(me);

    // Base query
    Query<Map<String, dynamic>> q = _db
        .collection('profiles')
        .where('hideMode', isEqualTo: false)
        .orderBy('createdAt', descending: true); // add createdAt to profile doc
    if (_cursor != null) q = q.startAfterDocument(_cursor!);
    q = q.limit(limit * 2); // overfetch, we’ll filter client-side

    final snapshot = await q.get();
    if (snapshot.docs.isNotEmpty) _cursor = snapshot.docs.last;

    final blacklist = <String>{
      me,
      ...blocked,
      ...blockedMe,
      ...liked,
      ...matched,
    };

    final cards = snapshot.docs
        .where((d) => !blacklist.contains(d.id))
        .map((d) => Profile.fromDoc(d.id, d.data()))
        .toList();

    // If too few after filtering, call nextPage() again in your UI until deck is filled or hasMore=false.
    return (
      cards: cards.take(limit).toList(),
      hasMore: snapshot.docs.length >= limit,
    );
  }

  void reset() {
    _cursor = null;
  }
}
