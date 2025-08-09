// lib/features/chat/chat_list_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final matchesQuery = FirebaseFirestore.instance
        .collection('matches')
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: matchesQuery.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return _EmptyState(onDiscover: () => context.go('/'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, i) {
              final d = docs[i];
              final participants = List<String>.from(
                d['participants'] ?? const [],
              );
              final peerUid = participants.firstWhere(
                (p) => p != uid,
                orElse: () => '',
              );
              final lastAt =
                  (d['lastMessageAt'] ?? d['createdAt']) as Timestamp?;
              final lastWhen = lastAt?.toDate();

              return _MatchTile(
                matchId: d.id,
                peerUid: peerUid,
                lastWhen: lastWhen,
                onOpen: () {
                  // Navigate to your ChatScreen route. Example with GoRouter:
                  // Define a route like GoRoute(path: '/chats/:id', builder: ...).
                  context.push('/chats/${d.id}', extra: {'peerUid': peerUid});
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _MatchTile extends StatelessWidget {
  final String matchId;
  final String peerUid;
  final DateTime? lastWhen;
  final VoidCallback onOpen;

  const _MatchTile({
    required this.matchId,
    required this.peerUid,
    required this.lastWhen,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;

    // Stream peer profile for name/photo
    final peerProfileStream = db
        .collection('profiles')
        .doc(peerUid)
        .snapshots();

    // Latest message snippet
    final lastMsgStream = db
        .collection('matches')
        .doc(matchId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: peerProfileStream,
      builder: (context, profSnap) {
        final prof = profSnap.data?.data() ?? {};
        final name = (prof['displayName'] ?? 'Unknown') as String;
        final photos = (prof['photos'] is List)
            ? List<String>.from(prof['photos'])
            : const <String>[];
        final avatarUrl = photos.isNotEmpty ? photos.first : null;

        return InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _Avatar(url: avatarUrl, fallbackText: name),
                const SizedBox(width: 12),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: lastMsgStream,
                    builder: (context, msgSnap) {
                      String subtitle = 'Say hi 👋';
                      if (msgSnap.hasData && msgSnap.data!.docs.isNotEmpty) {
                        final m = msgSnap.data!.docs.first.data();
                        final body = (m['body'] ?? '') as String;
                        subtitle = body.isEmpty ? 'Photo' : body;
                      }
                      final when = lastWhen != null
                          ? timeago.format(lastWhen!)
                          : '';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              if (when.isNotEmpty)
                                Text(
                                  when,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context).hintColor,
                                      ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: Theme.of(context).hintColor),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? url;
  final String fallbackText;
  const _Avatar({required this.url, required this.fallbackText});

  @override
  Widget build(BuildContext context) {
    final initials = fallbackText.isNotEmpty
        ? fallbackText[0].toUpperCase()
        : '?';
    if (url == null) {
      return CircleAvatar(radius: 24, child: Text(initials));
    }
    return CircleAvatar(
      radius: 24,
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Center(child: Text(initials)),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onDiscover;
  const _EmptyState({required this.onDiscover});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.forum_outlined, size: 64),
            const SizedBox(height: 12),
            Text('No chats yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Start swiping to find matches and start a conversation.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onDiscover,
              icon: const Icon(Icons.favorite_outline),
              label: const Text('Go to Discover'),
            ),
          ],
        ),
      ),
    );
  }
}
