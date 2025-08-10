import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Content-only profile screen for the current user.
/// (Shown inside HomeShell tab.)
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Not signed in'));
    }

    final profileStream = FirebaseFirestore.instance
        .collection('profiles')
        .doc(uid)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: profileStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        if (!snap.hasData || !snap.data!.exists) {
          return const Center(child: Text('No profile yet'));
        }

        final d = snap.data!.data()!;
        final name = (d['displayName'] ?? '') as String;
        final bio = (d['bio'] ?? '') as String? ?? '';
        final pronouns = (d['pronouns'] ?? '') as String? ?? '';
        final program = (d['program'] ?? 'None') as String? ?? 'None';
        final soberDateStr = (d['soberDate'] ?? '') as String? ?? '';
        final interests = (d['interests'] is List)
            ? (d['interests'] as List).cast<String>()
            : const <String>[];
        final photos = (d['photos'] is List)
            ? (d['photos'] as List).cast<String>()
            : const <String>[];
        // 1) After you read other profile fields (right where you read `bio`, `program`, etc.)
        final distanceUnit =
            (d['distanceUnit'] ?? 'km') as String; // 'km' or 'mi'
        final maxDistanceKm = (d['maxDistanceKm'] ?? 100);
        final prettyDistance = distanceUnit == 'mi'
            ? '${(maxDistanceKm * 0.621371).round()} mi'
            : '$maxDistanceKm km';

        int? soberDays;
        if (soberDateStr.isNotEmpty) {
          final dt = DateTime.tryParse(soberDateStr);
          if (dt != null) {
            soberDays = DateTime.now().difference(dt).inDays;
          }
        }

        // Prompts stream (limit 3, ordered)
        final promptsStream = FirebaseFirestore.instance
            .collection('profiles')
            .doc(uid)
            .collection('prompts')
            .orderBy('order')
            .limit(3)
            .snapshots();

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: promptsStream,
          builder: (context, psnap) {
            final items = <_PromptItem>[];
            if (psnap.hasData) {
              for (final doc in psnap.data!.docs) {
                final m = doc.data();
                final prompt = (m['prompt'] ?? '') as String;
                final answer = (m['answer'] ?? '') as String;
                if (prompt.isNotEmpty && answer.isNotEmpty) {
                  items.add(_PromptItem(prompt: prompt, answer: answer));
                }
              }
            }

            final restPhotos = photos.length > 1
                ? photos.sublist(1)
                : <String>[];

            // Build blocks: header, then interleave photos + prompt cards.
            final blocks = <Widget>[
              _Header(
                name: name.isEmpty ? 'Unnamed' : name,
                pronouns: pronouns.isEmpty ? null : pronouns,
                photoUrl: photos.isNotEmpty ? photos.first : null,
                program: program,
                soberDays: soberDays,
              ),
              const SizedBox(height: 16),
              if (bio.isNotEmpty)
                Text(bio, style: Theme.of(context).textTheme.bodyLarge),
              if (bio.isNotEmpty) const SizedBox(height: 16),
              if (interests.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: interests.map((s) => Chip(label: Text(s))).toList(),
                ),
              if (interests.isNotEmpty) const SizedBox(height: 16),
            ];

            blocks.addAll([
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Search distance: $prettyDistance',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ]);

            final maxLen = (restPhotos.length > items.length)
                ? restPhotos.length
                : items.length;
            for (var i = 0; i < maxLen; i++) {
              if (i < restPhotos.length) {
                blocks.add(_BigPhoto(restPhotos[i]));
                blocks.add(const SizedBox(height: 12));
              }
              if (i < items.length) {
                blocks.add(_PromptCard(item: items[i]));
                blocks.add(const SizedBox(height: 12));
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                16,
                56,
                16,
                120,
              ), // ↑ increased top from 24 → 48
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: blocks,
              ),
            );
          },
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final String name;
  final String? pronouns;
  final String? photoUrl;
  final String program;
  final int? soberDays;

  const _Header({
    required this.name,
    required this.pronouns,
    required this.photoUrl,
    required this.program,
    required this.soberDays,
  });

  @override
  Widget build(BuildContext context) {
    // Give the avatar an explicit size so it has bounded constraints inside Row.
    const double avatarSize = 96;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: avatarSize,
          height: avatarSize,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: photoUrl == null
                ? Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.person, size: 36),
                  )
                : Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    // Nice-to-have: lightweight placeholder
                    loadingBuilder: (c, child, progress) => progress == null
                        ? child
                        : const ColoredBox(color: Colors.black12),
                    errorBuilder: (c, e, s) => const ColoredBox(
                      color: Colors.black12,
                      child: Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (pronouns != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      pronouns!,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (program.isNotEmpty && program != 'None')
                    Chip(label: Text(program)),
                  if (soberDays != null) ...[
                    const SizedBox(width: 6),
                    Chip(label: Text('$soberDays days sober')),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BigPhoto extends StatelessWidget {
  final String url;
  const _BigPhoto(this.url);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 4 / 5,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          loadingBuilder: (c, child, progress) => progress == null
              ? child
              : const ColoredBox(color: Colors.black12),
          errorBuilder: (c, e, s) => const ColoredBox(
            color: Colors.black12,
            child: Center(child: Icon(Icons.broken_image)),
          ),
        ),
      ),
    );
  }
}

class _PromptItem {
  final String prompt;
  final String answer;
  _PromptItem({required this.prompt, required this.answer});
}

class _PromptCard extends StatelessWidget {
  final _PromptItem item;
  const _PromptCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.prompt, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Text(item.answer),
          ],
        ),
      ),
    );
  }
}
