// lib/features/swipe/swipe_card.dart
import 'package:flutter/material.dart';

class SwipeCard extends StatelessWidget {
  const SwipeCard({
    super.key,
    required this.uid,
    required this.name,
    required this.photos,
    required this.bio,
    required this.soberSince,
    required this.onLike,
    required this.onPass,
    required this.onBlock,
  });

  final String uid;
  final String name;
  final List<String> photos;
  final String bio;
  final DateTime? soberSince;

  final VoidCallback onLike;
  final VoidCallback onPass;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayName = name.isEmpty ? '—' : name;
    final streakDays = soberSince == null
        ? null
        : DateTime.now().difference(soberSince!).inDays;

    return Card(
      color: scheme.surface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Photos
          AspectRatio(
            aspectRatio: 3 / 4,
            child: photos.isEmpty
                ? Container(
                    color: scheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Icons.person, size: 64)),
                  )
                : _PhotoPager(photos: photos),
          ),

          // Info + actions
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name + streak
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        displayName,
                        style: Theme.of(context).textTheme.titleLarge,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (streakDays != null)
                      Row(
                        children: [
                          const Icon(Icons.emoji_events_outlined, size: 18),
                          const SizedBox(width: 4),
                          Text(
                            '${streakDays}d sober',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (bio.isNotEmpty)
                  Text(
                    bio,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                const SizedBox(height: 10),
                _ActionsRow(onLike: onLike, onPass: onPass, onBlock: onBlock),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoPager extends StatefulWidget {
  const _PhotoPager({required this.photos});
  final List<String> photos;

  @override
  State<_PhotoPager> createState() => _PhotoPagerState();
}

class _PhotoPagerState extends State<_PhotoPager> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: photos.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => Image.network(photos[i], fit: BoxFit.cover),
        ),
        if (photos.length > 1)
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: _Dots(count: photos.length, index: _index),
          ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 16 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
        );
      }),
    );
  }
}

class _ActionsRow extends StatelessWidget {
  const _ActionsRow({
    required this.onLike,
    required this.onPass,
    required this.onBlock,
  });

  final VoidCallback onLike;
  final VoidCallback onPass;
  final VoidCallback onBlock;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget pill({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
    }) {
      return Expanded(
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            foregroundColor: scheme.onSurface,
            side: BorderSide(color: scheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        pill(icon: Icons.clear_rounded, label: 'Pass', onTap: onPass),
        const SizedBox(width: 8),
        pill(icon: Icons.favorite_border, label: 'Like', onTap: onLike),
        const SizedBox(width: 8),
        pill(icon: Icons.block, label: 'Block', onTap: onBlock),
      ],
    );
  }
}
