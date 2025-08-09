// lib/features/swipe/feed_repo.dart
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../profile/models.dart';

final _auth = FirebaseAuth.instance;
// <<< REGION MUST MATCH setGlobalOptions() above >>>
final _functions = FirebaseFunctions.instanceFor(region: 'us-central1');

class FeedRepo {
  Map<String, dynamic>? _cursor;

  Future<({List<Profile> cards, bool hasMore})> nextPage({
    int limit = 25,
  }) async {
    final appProject = Firebase.app().options.projectId;
    // Handy log to catch project mismatches
    // ignore: avoid_print
    print('FeedRepo calling getFeed on project=$appProject region=us-central1');

    final me = _auth.currentUser?.uid;
    if (me == null) return (cards: <Profile>[], hasMore: false);

    try {
      final callable = _functions.httpsCallable('getFeed');
      final resp = await callable.call({
        'limit': limit,
        if (_cursor != null) 'cursor': _cursor,
      });
      final data = (resp.data as Map).cast<String, dynamic>();

      final items = (data['items'] as List<dynamic>? ?? const [])
          .cast<Map>()
          .map((m) => m.cast<String, dynamic>())
          .toList();

      final cards = <Profile>[];
      for (final m in items) {
        final id = (m['id'] ?? '') as String;
        final map = Map<String, dynamic>.from(m)..remove('id');
        cards.add(Profile.fromDoc(id, map));
      }

      _cursor = (data['nextCursor'] as Map?)?.cast<String, dynamic>();
      final hasMore = (data['hasMore'] as bool?) ?? false;
      return (cards: cards, hasMore: hasMore);
    } on FirebaseFunctionsException catch (e) {
      // If NOT_FOUND or UNIMPLEMENTED, surface a clear hint
      // ignore: avoid_print
      print('getFeed callable failed: ${e.code} ${e.message}');
      rethrow;
    }
  }

  void reset() => _cursor = null;
}
