import 'package:flutter/material.dart';

import '../../core/app_spacing.dart';

/// Placeholder blocks shown while data loads.
///
/// Replaces the centered `CircularProgressIndicator` that used to sit in every
/// `AsyncValue.when(loading: …)`: a spinner throws the layout away and rebuilds
/// it a moment later, so every screen visibly jumps on load. A skeleton keeps
/// the shape of what is coming, so the screen settles instead of snapping.
///
/// The pulse is a slow opacity fade, not a diagonal gradient sweep — a sweep
/// draws the eye to the loading state itself, which is the one thing here that
/// isn't content. It respects `MediaQuery.disableAnimations`, so a viewer with
/// reduced motion enabled gets a still block.
class Skeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
  });

  /// A circle, for a leading avatar or icon placeholder.
  const Skeleton.circle({super.key, double size = 36})
      : width = size,
        height = size,
        radius = size / 2;

  /// A full card-sized block.
  const Skeleton.card({super.key, this.height = 92})
      : width = double.infinity,
        radius = kCardRadius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    duration: const Duration(milliseconds: 1100),
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.onSurface.withValues(alpha: 0.07);
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    final block = Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );

    if (reduceMotion) return block;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: block,
    );
  }
}

/// A placeholder that matches the shape of a list of rows: leading dot, two
/// lines of text, trailing amount.
class SkeletonList extends StatelessWidget {
  final int rows;
  final bool showLeading;
  final EdgeInsets padding;

  const SkeletonList({
    super.key,
    this.rows = 6,
    this.showLeading = true,
    this.padding = kScreenPadding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows; i++) ...[
            Row(
              children: [
                if (showLeading) ...[
                  const Skeleton.circle(size: 10),
                  const SizedBox(width: kSpaceXl),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Rows alternate width so the block doesn't read as a
                      // table of identical bars.
                      Skeleton(width: i.isEven ? 168 : 132, height: 13),
                      kGapSm,
                      const Skeleton(width: 78, height: 10),
                    ],
                  ),
                ),
                const SizedBox(width: kSpaceXl),
                Skeleton(width: i.isEven ? 84 : 68, height: 13),
              ],
            ),
            if (i < rows - 1) kGapSection,
          ],
        ],
      ),
    );
  }
}

/// A placeholder for a card that leads with a headline number.
class SkeletonHeroCard extends StatelessWidget {
  const SkeletonHeroCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: kHeroCardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Skeleton(width: 96, height: 11),
            kGapXl,
            const Skeleton(width: 210, height: 32, radius: 8),
            kGapSection,
            Row(
              children: const [
                Expanded(child: Skeleton(height: 11)),
                SizedBox(width: kSpaceSection),
                Expanded(child: Skeleton(height: 11)),
                SizedBox(width: kSpaceSection),
                Expanded(child: Skeleton(height: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A placeholder for a screen made of cards rather than rows (accounts, goals,
/// expense groups).
class SkeletonCards extends StatelessWidget {
  final int cards;
  final double height;
  final EdgeInsets padding;

  const SkeletonCards({
    super.key,
    this.cards = 3,
    this.height = 96,
    this.padding = kScreenPadding,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        children: [
          for (var i = 0; i < cards; i++) ...[
            Skeleton.card(height: height),
            if (i < cards - 1) kGapXl,
          ],
        ],
      ),
    );
  }
}
