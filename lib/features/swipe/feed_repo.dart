import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../profile/models.dart';

/// Calls callable function `getFeed` and turns the result into Profiles.
/// Keeps a cursor (updatedAt millis), dedups by uid, and will fetch
/// multiple times per call to fill the requested page if the server
/// returns rows we end up filtering out later in the app (rare).
class FeedRepo {
  FeedRepo({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
    this.defaultPageSize = 25,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  /// Default page size used when none is provided.
  final int defaultPageSize;

  /// Cursor returned by the function (millis of last profile.updatedAt).
  int? _cursorUpdatedAt;

  /// True once the server indicates there’s no more data.
  bool _exhausted = false;

  /// Prevent overlapping fetches.
  bool _loading = false;

  /// Deduplicate cards across pages.
  final Set<String> _seenUids = <String>{};

  /// Reset paging state (e.g., pull-to-refresh).
  void reset() {
    _cursorUpdatedAt = null;
    _exhausted = false;
    _loading = false;
    _seenUids.clear();
  }

  /// Fetch next page. Returns fewer than [limit] if the server has no more.
  /// Safe to call repeatedly; if already loading, returns an empty batch.
  Future<({List<Profile> cards, bool hasMore})> nextPage({int? limit}) async {
    if (_loading) {
      return (cards: const <Profile>[], hasMore: !_exhausted);
    }
    if (_exhausted) {
      return (cards: const <Profile>[], hasMore: false);
    }

    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      throw StateError('Not signed in');
    }

    _loading = true;
    final pageLimit = _clamp(limit ?? defaultPageSize, 1, 50);

    final List<Profile> out = [];
    bool lastHasMore = true;

    // Try up to 3 pulls to fill the page if duplicates were filtered.
    // Each call advances the server-side cursor so we won’t loop forever.
    for (
      int attempts = 0;
      attempts < 3 && out.length < pageLimit && !_exhausted;
      attempts++
    ) {
      final res = await _callGetFeed(
        limit: pageLimit,
        cursorUpdatedAt: _cursorUpdatedAt,
      );

      // Advance cursor/hasMore from the server response immediately.
      _cursorUpdatedAt = res.nextCursorUpdatedAt;
      lastHasMore = res.hasMore;

      // Convert to Profiles and dedup by uid across the whole session.
      for (final m in res.cards) {
        final uid = m['uid'] as String?; // server guarantees, but be safe
        final dataRaw = m['profile'];
        if (uid == null || dataRaw is! Map) continue;

        if (_seenUids.add(uid)) {
          final data = Map<String, dynamic>.from(dataRaw);
          out.add(Profile.fromDoc(uid, data));
          if (out.length >= pageLimit) break;
        }
      }

      // If server says there’s no more, mark exhausted.
      if (!lastHasMore) {
        _exhausted = true;
      }

      // If we didn’t add anything and server says more exists, loop again
      // to move past items we filtered/deduped. Otherwise break.
      if (out.isEmpty && lastHasMore) {
        // continue; (let the loop try another batch)
      } else {
        // We either filled something or server is out of data.
        if (out.length >= pageLimit || !lastHasMore) break;
      }
    }

    _loading = false;
    return (cards: out, hasMore: !_exhausted);
  }

  // ---- internals ----

  int _clamp(int v, int lo, int hi) => v < lo ? lo : (v > hi ? hi : v);

  Future<_FeedResponse> _callGetFeed({
    required int limit,
    required int? cursorUpdatedAt,
  }) async {
    final callable = _functions.httpsCallable('getFeed');

    try {
      final resp = await callable.call<Map<String, dynamic>>({
        'limit': limit,
        'cursorUpdatedAt': cursorUpdatedAt,
      });

      final data = resp.data;
      final rawCards = (data['cards'] as List?) ?? const [];
      final next = data['nextCursorUpdatedAt'];
      final hasMore = (data['hasMore'] as bool?) ?? false;

      return _FeedResponse(
        cards: rawCards.cast<Map>(),
        nextCursorUpdatedAt: next is int ? next : null,
        hasMore: hasMore,
      );
    } on FirebaseFunctionsException catch (e) {
      // Surface rich diagnostics to your logs; the Cloud Function already logs
      // which stage failed (blockedByMe / blockedMe / liked / matches / profiles).
      // This makes it much easier to correlate client errors with server logs.
      // ignore: avoid_print
      print(
        'getFeed() failed: code=${e.code} message=${e.message} details=${e.details}',
      );
      rethrow;
    }
  }
}

class _FeedResponse {
  _FeedResponse({
    required this.cards,
    required this.nextCursorUpdatedAt,
    required this.hasMore,
  });

  final List<Map> cards;
  final int? nextCursorUpdatedAt;
  final bool hasMore;
}
