// lib/features/swipe/swipe_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'feed_repo.dart';
import '../profile/models.dart';
import '../safety/safety_repo.dart';
import 'swipe_card.dart';

class SwipeScreen extends StatefulWidget {
  const SwipeScreen({super.key});

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final _feed = FeedRepo();
  final _safety = SafetyRepo(FirebaseFirestore.instance);

  final _cards = <Profile>[];

  bool _loading = true;
  bool _busy = false;
  bool _hasMore = true;

  String get _me => _auth.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() => _loading = true);
    _cards.clear();
    final page = await _feed.nextPage(limit: 20);
    _cards.addAll(page.cards);
    _hasMore = page.hasMore;
    setState(() => _loading = false);
  }

  Future<void> _loadMoreIfNeeded() async {
    if (_busy || !_hasMore) return;
    setState(() => _busy = true);
    final page = await _feed.nextPage(limit: 20);
    _cards.addAll(page.cards);
    _hasMore = page.hasMore;
    setState(() => _busy = false);
  }

  Future<void> _likeUser(String otherUid) async {
    setState(() => _busy = true);
    try {
      await _db.collection('likes').add({
        'fromUid': _me,
        'toUid': otherUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _cards.removeWhere((p) => p.uid == otherUid);
      if (_cards.length < 5) await _loadMoreIfNeeded();
      _snack('You liked a profile');
    } catch (e) {
      _snack('Like failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _passUser(String otherUid) async {
    _cards.removeWhere((p) => p.uid == otherUid);
    if (_cards.length < 5) await _loadMoreIfNeeded();
    setState(() {});
  }

  Future<void> _blockUser(String otherUid) async {
    setState(() => _busy = true);
    try {
      await _safety.blockUser(_me, otherUid);
      _cards.removeWhere((p) => p.uid == otherUid);
      _snack('User blocked');
    } catch (e) {
      _snack('Block failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        actions: [
          IconButton(
            onPressed: _busy
                ? null
                : () async {
                    _feed.reset();
                    await _loadInitial();
                  },
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _cards.isEmpty
          ? const _EmptyView()
          : PageView.builder(
              itemCount: _cards.length,
              controller: PageController(viewportFraction: 0.95),
              onPageChanged: (i) async {
                // Pre-load more when we're near the end
                if (_hasMore && i >= _cards.length - 3) {
                  await _loadMoreIfNeeded();
                }
              },
              itemBuilder: (context, index) {
                final p = _cards[index];
                return SwipeCard(
                  key: ValueKey(p.uid),
                  uid: p.uid,
                  name: p.displayName,
                  bio: p.bio ?? '',
                  photos: p.photos ?? const <String>[],
                  soberSince: p.soberDate,
                  onLike: () => _likeUser(p.uid),
                  onPass: () => _passUser(p.uid),
                  onBlock: () => _blockUser(p.uid),
                );
              },
            ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people_outline, size: 56),
            const SizedBox(height: 12),
            Text(
              'No more profiles right now',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try again later.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
