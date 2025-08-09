// lib/features/chat/chat_screen.dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final String matchId;
  final String? peerUid; // optional; if null we infer from match

  const ChatScreen({super.key, required this.matchId, this.peerUid});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send(String matchId, String text) async {
    final body = text.trim();
    if (body.isEmpty) return;
    setState(() => _sending = true);
    try {
      final me = _auth.currentUser!.uid;
      final msgCol = _db
          .collection('matches')
          .doc(matchId)
          .collection('messages');
      await msgCol.add({
        'senderUid': me,
        'body': body,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _db.collection('matches').doc(matchId).update({
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
      _controller.clear();
      _jumpToBottom();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to send: $e')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _jumpToBottom() {
    // schedule after build to ensure list dimensions are known
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final me = _auth.currentUser!.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _db.collection('matches').doc(widget.matchId).snapshots(),
      builder: (context, matchSnap) {
        if (matchSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (matchSnap.hasError) {
          return Scaffold(
            body: Center(child: Text('Error: ${matchSnap.error}')),
          );
        }
        if (!matchSnap.hasData || !matchSnap.data!.exists) {
          return const Scaffold(body: Center(child: Text('Chat not found')));
        }

        final match = matchSnap.data!.data()!;
        final participants = List<String>.from(
          match['participants'] ?? const [],
        );
        final peerUid =
            widget.peerUid ??
            participants.firstWhere((p) => p != me, orElse: () => '');

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _db.collection('profiles').doc(peerUid).snapshots(),
          builder: (context, profSnap) {
            final prof = profSnap.data?.data() ?? {};
            final name = (prof['displayName'] ?? 'Unknown') as String;
            final photos = (prof['photos'] is List)
                ? List<String>.from(prof['photos'])
                : const <String>[];
            final avatarUrl = photos.isNotEmpty ? photos.first : null;

            return Scaffold(
              appBar: AppBar(
                titleSpacing: 0,
                title: Row(
                  children: [
                    _AvatarSmall(url: avatarUrl, name: name),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              body: Column(
                children: [
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _db
                          .collection('matches')
                          .doc(widget.matchId)
                          .collection('messages')
                          .orderBy('createdAt')
                          .snapshots(),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final docs = snap.data!.docs;
                        // auto scroll when new messages arrive
                        WidgetsBinding.instance.addPostFrameCallback(
                          (_) => _jumpToBottom(),
                        );

                        return ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          itemCount: docs.length,
                          itemBuilder: (context, i) {
                            final m = docs[i].data();
                            final from = (m['senderUid'] ?? '') as String;
                            final body = (m['body'] ?? '') as String;
                            final ts = (m['createdAt'] as Timestamp?);
                            final when = ts?.toDate() ?? DateTime.now();
                            final isMe = from == me;
                            return _MessageBubble(
                              text: body,
                              time: DateFormat.jm().format(when),
                              isMe: isMe,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _controller,
                              textInputAction: TextInputAction.send,
                              minLines: 1,
                              maxLines: 5,
                              decoration: InputDecoration(
                                hintText: 'Message',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                              onSubmitted: (_) => _sending
                                  ? null
                                  : _send(widget.matchId, _controller.text),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _sending
                                ? null
                                : () => _send(widget.matchId, _controller.text),
                            icon: const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AvatarSmall extends StatelessWidget {
  final String? url;
  final String name;
  const _AvatarSmall({required this.url, required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    if (url == null) {
      return CircleAvatar(radius: 16, child: Text(initial));
    }
    return CircleAvatar(
      radius: 16,
      backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => Center(child: Text(initial)),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final String time;
  final bool isMe;

  const _MessageBubble({
    required this.text,
    required this.time,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isMe
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceVariant;
    final fg = isMe
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(text, style: TextStyle(color: fg)),
            const SizedBox(height: 4),
            Text(
              time,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: fg.withOpacity(0.8)),
            ),
          ],
        ),
      ),
    );
  }
}
