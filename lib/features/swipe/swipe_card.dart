// lib/features/swipe/swipe_card.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A lightweight Tinder-style swipe card.
/// Parent should remove the card from the deck when onLike/onPass fire.
class SwipeCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onLike;
  final VoidCallback onPass;
  final double swipeThreshold; // horizontal px to trigger
  final double maxAngle; // degrees

  const SwipeCard({
    super.key,
    required this.child,
    required this.onLike,
    required this.onPass,
    this.swipeThreshold = 120,
    this.maxAngle = 15,
  });

  @override
  State<SwipeCard> createState() => _SwipeCardState();
}

class _SwipeCardState extends State<SwipeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  Offset _offset = Offset.zero; // drag offset
  bool _animatingBack = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 220),
          )
          ..addListener(() {
            if (_animatingBack) {
              setState(() {
                _offset = Offset.lerp(_offset, Offset.zero, _controller.value)!;
              });
            }
          })
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && _animatingBack) {
              _animatingBack = false;
              _controller.reset();
              setState(() => _offset = Offset.zero);
            }
          });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateBack() {
    _animatingBack = true;
    _controller.forward(from: 0);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    setState(() => _offset += d.delta);
  }

  void _onPanEnd(DragEndDetails d) {
    final dx = _offset.dx;
    if (dx > widget.swipeThreshold) {
      widget.onLike(); // parent removes this card
      return;
    }
    if (dx < -widget.swipeThreshold) {
      widget.onPass();
      return;
    }
    _animateBack();
  }

  @override
  Widget build(BuildContext context) {
    final angle = (_offset.dx / 300) * (widget.maxAngle * math.pi / 180);
    final opacity = (_offset.dx.abs() / widget.swipeThreshold)
        .clamp(0, 1)
        .toDouble();
    final isLike = _offset.dx > 0;

    return GestureDetector(
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: Transform.translate(
        offset: _offset,
        child: Transform.rotate(
          angle: angle,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Material(
                  elevation: 2,
                  borderRadius: BorderRadius.circular(16),
                  child: widget.child,
                ),
              ),
              // LIKE / NOPE ribbons
              Positioned(
                top: 24,
                left: 24,
                child: Opacity(
                  opacity: isLike ? opacity : 0,
                  child: _Ribbon(text: 'LIKE', color: Colors.green),
                ),
              ),
              Positioned(
                top: 24,
                right: 24,
                child: Opacity(
                  opacity: !isLike ? opacity : 0,
                  child: _Ribbon(text: 'NOPE', color: Colors.red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Ribbon extends StatelessWidget {
  final String text;
  final Color color;
  const _Ribbon({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -12 * math.pi / 180,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 3),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white.withOpacity(0.75),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}
