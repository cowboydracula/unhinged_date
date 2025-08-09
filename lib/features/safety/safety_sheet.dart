// lib/features/safety/safety_sheet.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Quick actions for safety & privacy:
/// - Hide me from discovery
/// - Block user (also auto-unmatches via your Cloud Function)
/// - Unmatch only
/// - Report user with a reason
class SafetySheet extends StatefulWidget {
  final String targetUid;
  final String? matchId;
  final String? targetName;

  const SafetySheet({
    super.key,
    required this.targetUid,
    this.matchId,
    this.targetName,
  });

  @override
  State<SafetySheet> createState() => _SafetySheetState();
}

class _SafetySheetState extends State<SafetySheet> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  bool _busy = false;

  String get me => _auth.currentUser!.uid;

  Future<void> _toggleHide(bool value) async {
    setState(() => _busy = true);
    try {
      await _db.collection('profiles').doc(me).set({
        'hideMode': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              value ? 'Hidden from discovery' : 'Visible in discovery',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _blockUser() async {
    final ok = await _confirm(
      title: 'Block ${widget.targetName ?? 'this user'}?',
      message:
          'They won’t be able to find or message you. This also unmatches you.',
      confirmText: 'Block',
      confirmStyle: ElevatedButton.styleFrom(backgroundColor: Colors.red),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await _db.doc('blocks/$me/blocked/${widget.targetUid}').set({
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        Navigator.of(context).maybePop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User blocked')));
      }
      // Your onBlockCreate Cloud Function will remove the match if it exists.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Block failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unmatch() async {
    final ok = await _confirm(
      title: 'Unmatch and end chat?',
      message:
          'This removes the conversation for both of you. You can block instead if you want to prevent future contact.',
      confirmText: 'Unmatch',
      confirmStyle: ElevatedButton.styleFrom(backgroundColor: Colors.red),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final id = await _resolveMatchId();
      if (id == null) throw 'No match found';
      await _db.collection('matches').doc(id).delete();
      if (mounted) {
        Navigator.of(context).maybePop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Unmatched')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Unmatch failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _resolveMatchId() async {
    if (widget.matchId != null && widget.matchId!.isNotEmpty) {
      return widget.matchId;
    }
    // Try deterministic id first (a_b)
    final a = [me, widget.targetUid]..sort();
    final guess = '${a.first}_${a.last}';
    final gDoc = await _db.collection('matches').doc(guess).get();
    if (gDoc.exists) return guess;

    // Fallback: search for a match containing both participants
    final qs = await _db
        .collection('matches')
        .where('participants', arrayContains: me)
        .limit(20)
        .get();
    for (final d in qs.docs) {
      final parts = List<String>.from(d['participants'] ?? const []);
      if (parts.contains(widget.targetUid)) return d.id;
    }
    return null;
  }

  Future<void> _reportUser() async {
    final reason = await _askReportReason();
    if (reason == null || reason.trim().isEmpty) return;

    setState(() => _busy = true);
    try {
      await _db.collection('reports').add({
        'actorUid': me,
        'subjectUid': widget.targetUid,
        'reason': reason.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Report sent')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Report failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmText,
    ButtonStyle? confirmStyle,
  }) async {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: confirmStyle,
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  Future<String?> _askReportReason() async {
    final controller = TextEditingController();
    String? picked = 'Harassment';
    return showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Report user'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: picked,
                items: const [
                  DropdownMenuItem(
                    value: 'Harassment',
                    child: Text('Harassment'),
                  ),
                  DropdownMenuItem(
                    value: 'Hate speech',
                    child: Text('Hate speech'),
                  ),
                  DropdownMenuItem(
                    value: 'Spam or scams',
                    child: Text('Spam or scams'),
                  ),
                  DropdownMenuItem(
                    value: 'Inappropriate content',
                    child: Text('Inappropriate content'),
                  ),
                  DropdownMenuItem(
                    value: 'Impersonation',
                    child: Text('Impersonation'),
                  ),
                  DropdownMenuItem(value: 'Other', child: Text('Other')),
                ],
                onChanged: (v) {
                  picked = v;
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  hintText: 'Add details (optional, required if "Other")',
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final reason = picked == 'Other'
                    ? (controller.text.trim().isEmpty
                          ? null
                          : controller.text.trim())
                    : picked;
                Navigator.pop(context, reason);
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final myProfileStream = _db.collection('profiles').doc(me).snapshots();

    return AbsorbPointer(
      absorbing: _busy,
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: myProfileStream,
        builder: (context, snap) {
          final hide = (snap.data?.data()?['hideMode'] ?? false) as bool;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Hide me from discovery'),
                    subtitle: const Text(
                      'You’ll still be able to chat with existing matches',
                    ),
                    trailing: Switch.adaptive(
                      value: hide,
                      onChanged: (v) => _toggleHide(v),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.block),
                    title: Text('Block ${widget.targetName ?? 'user'}'),
                    subtitle: const Text(
                      'Prevents messages and removes from your feed',
                    ),
                    onTap: _blockUser,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.link_off),
                    title: const Text('Unmatch'),
                    subtitle: const Text('Remove the chat without blocking'),
                    onTap: _unmatch,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.flag_outlined),
                    title: const Text('Report'),
                    subtitle: const Text('Send a report to moderators'),
                    onTap: _reportUser,
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Helper to present the sheet.
/// Usage:
/// await showSafetySheet(context, targetUid: 'peerUid', matchId: 'a_b', targetName: 'Alex');
Future<void> showSafetySheet(
  BuildContext context, {
  required String targetUid,
  String? matchId,
  String? targetName,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => SafetySheet(
      targetUid: targetUid,
      matchId: matchId,
      targetName: targetName,
    ),
  );
}
