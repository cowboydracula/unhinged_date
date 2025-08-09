// lib/features/swipe/swipe_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'swipe_card.dart';
import '../safety/safety_sheet.dart';

class SwipeScreen extends StatefulWidget {
  const SwipeScreen({super.key});

  @override
  State<SwipeScreen> createState() => _SwipeScreenState();
}

class _SwipeScreenState extends State<SwipeScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final List<DocumentSnapshot<Map<String, dynamic>>> _deck = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;

  bool _loading = false;
  bool _initialLoaded = false;

  // Exclusion sets
  final Set<String> _liked = {};
  final Set<String> _matched = {};
  final Set<String> _blocked = {};
  final Set<String> _blockedMe = {};

  String get _me => _auth.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() {
      _loading = true;
      _initialLoaded = false;
      _cursor = null;
      _deck.clear();
      _liked.clear();
      _matched.clear();
      _blocked.clear();
      _blockedMe.clear();
    });
    await _loadExclusions();
    await _loadMore();
    if (mounted) {
      setState(() {
        _loading = false;
        _initialLoaded = true;
      });
    }
  }

  Future<void> _loadExclusions() async {
    // likes I’ve sent
    final likes = await _db
        .collection('likes')
        .where('fromUid', isEqualTo: _me)
        .get();
    _liked.addAll(likes.docs.map((d) => d['toUid'] as String));

    // matches I’m in
    final matches = await _db
        .collection('matches')
        .where('participants', arrayContains: _me)
        .get();
    for (final m in matches.docs) {
      final parts = List<String>.from(m['participants'] ?? const <String>[]);
      for (final p in parts) {
        if (p != _me) _matched.add(p);
      }
    }

    // people I blocked
    final blocked = await _db
        .collection('blocks')
        .doc(_me)
        .collection('blocked')
        .get();
    _blocked.addAll(blocked.docs.map((d) => d.id));

    // who blocked me (collectionGroup search by doc id = my uid)
    final blockedMe = await _db
        .collectionGroup('blocked')
        .where(FieldPath.documentId, isEqualTo: _me)
        .get();
    for (final d in blockedMe.docs) {
      final owner = d.reference.parent.parent; // /blocks/{owner}/blocked/{me}
      if (owner != null) _blockedMe.add(owner.id);
    }
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      const page = 32; // overfetch; we filter client-side
      Query<Map<String, dynamic>> q = _db
          .collection('profiles')
          .where('hideMode', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(page);

      if (_cursor != null) q = q.startAfterDocument(_cursor!);

      final snap = await q.get();
      if (snap.docs.isNotEmpty) _cursor = snap.docs.last;

      final blacklist = <String>{
        _me,
        ..._liked,
        ..._matched,
        ..._blocked,
        ..._blockedMe,
      };

      final filtered = snap.docs
          .where((d) => !blacklist.contains(d.id))
          .toList();
      _deck.addAll(filtered);
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load profiles: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _likeTop() async {
    if (_deck.isEmpty) return;
    final top = _deck.removeAt(0);
    setState(() {});
    try {
      await _db.collection('likes').add({
        'fromUid': _me,
        'toUid': top.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _liked.add(top.id);
      if (_deck.length < 4) _loadMore();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to like: $e')));
    }
  }

  void _passTop() {
    if (_deck.isEmpty) return;
    _deck.removeAt(0);
    setState(() {});
    if (_deck.length < 4) _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final cards = _deck.take(4).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unhinged'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refreshAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _initialLoaded && cards.isEmpty
          ? _EmptyDiscover(onRefresh: _refreshAll)
          : Stack(
              alignment: Alignment.center,
              children: [
                if (!_initialLoaded)
                  const Center(child: CircularProgressIndicator()),
                ...List.generate(cards.length, (i) {
                  // 0 is topmost
                  final doc = cards[i];
                  final z = cards.length - 1 - i;
                  return Positioned.fill(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: z * 8.0,
                        left: z * 6.0,
                        right: z * 6.0,
                      ),
                      child: SwipeCard(
                        onLike: _likeTop,
                        onPass: _passTop,
                        child: _ProfileCard(
                          me: _me,
                          uid: doc.id,
                          data: doc.data()!,
                          onMore: () => showSafetySheet(
                            context,
                            targetUid: doc.id,
                            targetName:
                                (doc['displayName'] ?? 'User') as String,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: _Actions(
                    onPass: _passTop,
                    onLike: _likeTop,
                    disabled: _deck.isEmpty,
                  ),
                ),
              ],
            ),
    );
  }
}

class _Actions extends StatelessWidget {
  final VoidCallback onPass;
  final VoidCallback onLike;
  final bool disabled;
  const _Actions({
    required this.onPass,
    required this.onLike,
    required this.disabled,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton.filledTonal(
          onPressed: disabled ? null : onPass,
          icon: const Icon(Icons.close),
          iconSize: 28,
          style: IconButton.styleFrom(padding: const EdgeInsets.all(14)),
        ),
        const SizedBox(width: 24),
        IconButton.filled(
          onPressed: disabled ? null : onLike,
          icon: const Icon(Icons.favorite),
          iconSize: 28,
          style: IconButton.styleFrom(padding: const EdgeInsets.all(14)),
        ),
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final String me;
  final String uid;
  final Map<String, dynamic> data;
  final VoidCallback onMore;

  const _ProfileCard({
    required this.me,
    required this.uid,
    required this.data,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final name = (data['displayName'] ?? 'Unknown') as String;
    final photos = (data['photos'] is List)
        ? List<String>.from(data['photos'])
        : const <String>[];
    final bio = (data['bio'] ?? '') as String;

    final dobStr = data['dob'] as String?;
    final soberStr = data['soberDate'] as String?;
    final showStreak = (data['showStreak'] ?? false) as bool;
    final program = (data['program'] ?? 'None') as String;

    final age = _ageFromDob(dobStr);
    final streak = showStreak ? _streakFrom(soberStr) : null;

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: photos.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: photos.first,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        child: const Center(
                          child: Icon(Icons.person, size: 96),
                        ),
                      ),
              ),
              Positioned(
                right: 6,
                top: 6,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.more_vert, color: Colors.white),
                    onPressed: onMore,
                  ),
                ),
              ),
            ],
          ),
        ),
        ListTile(
          title: Text(
            [name, if (age != null) '$age'].join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (bio.isNotEmpty)
                Text(bio, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (program != 'None') ...[
                    const Icon(Icons.emoji_events_outlined, size: 16),
                    const SizedBox(width: 4),
                    Text(program),
                    const SizedBox(width: 12),
                  ],
                  if (streak != null) ...[
                    const Icon(Icons.local_fire_department_outlined, size: 16),
                    const SizedBox(width: 4),
                    Text('Sober $streak'),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  int? _ageFromDob(String? iso) {
    if (iso == null) return null;
    final dob = DateTime.tryParse(iso);
    if (dob == null) return null;
    final now = DateTime.now();
    int years = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      years -= 1;
    }
    return years.clamp(0, 150);
  }

  String? _streakFrom(String? iso) {
    if (iso == null) return null;
    final start = DateTime.tryParse(iso);
    if (start == null) return null;
    final now = DateTime.now();
    final totalDays = now.difference(start).inDays;
    if (totalDays < 0) return null;
    final years = totalDays ~/ 365;
    final months = (totalDays % 365) ~/ 30;
    if (years > 0) {
      return months > 0 ? '${years}y ${months}m' : '${years}y';
    }
    if (months > 0) return '${months}m';
    return '${totalDays}d';
  }
}

class _EmptyDiscover extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyDiscover({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sentiment_satisfied_alt_outlined, size: 72),
            const SizedBox(height: 12),
            Text(
              'You’re all caught up',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'No more profiles nearby. Try again later or adjust your preferences.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}
