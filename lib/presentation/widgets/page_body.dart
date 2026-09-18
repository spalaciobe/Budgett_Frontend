import 'package:flutter/material.dart';

import '../../core/app_spacing.dart';
import '../../core/responsive.dart';

/// Caps how wide a screen's content is allowed to get, and decides where the
/// leftover width goes.
///
/// Both extremes are wrong. Uncapped, a row's label and its amount end up a
/// screen apart. Capped and pinned left, every pixel of slack piles up in one
/// block on the right, which reads as a layout that stopped halfway — the
/// complaint that produced this version.
///
/// So: left-aligned while the slack is small enough to pass for a margin, and
/// centred once it isn't. On a 1440px laptop the content fills the width and
/// nothing moves; on a 1920px monitor the leftover ~320px becomes two calm
/// margins instead of one conspicuous void.
///
/// Width is a content decision, so pass the one that matches what's inside:
/// [kColumnMaxWidth] for a form or a single column of prose, [kPageMaxWidth]
/// for a grid or a table.
class PageBody extends StatelessWidget {
  final Widget child;

  /// Maximum content width on tablet and desktop. Mobile always fills.
  final double maxWidth;

  final EdgeInsets? padding;

  const PageBody({
    super.key,
    required this.child,
    this.maxWidth = kPageMaxWidth,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final body = padding == null
        ? child
        : Padding(padding: padding!, child: child);

    if (context.formFactor == FormFactor.mobile) return body;

    return LayoutBuilder(
      builder: (context, constraints) {
        final slack = constraints.maxWidth - maxWidth;
        // Below this, splitting the slack would produce two margins too thin
        // to read as deliberate, and shifting the content off the navigation's
        // left edge costs more than it gains.
        final centred = slack > 240;

        return Align(
          alignment: centred ? Alignment.topCenter : Alignment.topLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: body,
          ),
        );
      },
    );
  }
}

/// Two panes on a wide screen, stacked on a narrow one.
///
/// This is what makes a wide screen its own layout rather than a stretched
/// phone: the summary that sat *above* a list on mobile moves *beside* it, so
/// the list stays narrow enough to read a row in one glance and the spare
/// horizontal space carries information instead of emptiness.
///
/// On mobile and tablet the aside goes back on top, where it reads as the
/// screen's header.
class TwoPaneLayout extends StatelessWidget {
  /// The scrolling body — a list, usually.
  final Widget main;

  /// The supporting pane: a summary, filters, a chart.
  final Widget aside;

  /// Width of the aside on desktop.
  final double asideWidth;

  /// Gap between the panes, side by side.
  final double gap;

  /// Gap between the panes once they stack, below desktop. Separate from [gap]
  /// because the two do different work: side by side it separates columns and
  /// needs the room, stacked it only separates a summary from the list under
  /// it, where the same figure pushes the list down the screen.
  final double? stackedGap;

  const TwoPaneLayout({
    super.key,
    required this.main,
    required this.aside,
    this.asideWidth = 340,
    this.gap = kSpaceSection,
    this.stackedGap,
  });

  @override
  Widget build(BuildContext context) {
    // Both branches size to their content, so this can sit inside the
    // screen's existing scroll view and the page keeps one scrollbar.
    if (context.formFactor != FormFactor.desktop) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          aside,
          SizedBox(height: stackedGap ?? gap),
          main,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: main),
        SizedBox(width: gap),
        SizedBox(width: asideWidth, child: aside),
      ],
    );
  }
}

/// A responsive grid of equal-width cards that stops growing instead of
/// stretching: columns are added as the screen widens, and each card stays
/// within [maxItemWidth].
///
/// The old two-column grid divided whatever width it was given, so at 1440px
/// each card was ~700px wide to hold a seven-character name.
class ContentGrid extends StatelessWidget {
  final List<Widget> children;
  final double maxItemWidth;
  final double spacing;

  const ContentGrid({
    super.key,
    required this.children,
    this.maxItemWidth = 420,
    this.spacing = kSpaceXl,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final columns = (available / maxItemWidth).floor().clamp(1, 4);
        if (columns == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1) SizedBox(height: spacing),
              ],
            ],
          );
        }

        final itemWidth =
            (available - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}
