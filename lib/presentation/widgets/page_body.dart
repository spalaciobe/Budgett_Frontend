import 'package:flutter/material.dart';

import '../../core/app_spacing.dart';
import '../../core/responsive.dart';

/// Caps how wide a screen's content is allowed to get, and keeps it aligned to
/// the navigation instead of centring it.
///
/// A previous attempt at this capped the body and centred it, and was reverted
/// (`ecae618`) — correctly, because a centred column next to a left-hand
/// sidebar reads as a floating slab with a gutter on the wrong side. The
/// content is left-aligned here, so the sidebar, the screen title and the rows
/// share one left edge, and the spare width falls away on the right where
/// nothing needs it.
///
/// Width is a content decision, so pass the one that matches what's inside:
/// [kColumnMaxWidth] for a form or a single column of prose, [kPageMaxWidth]
/// for a grid or a table. Leaving a list at full width is what put a row's
/// label and its amount a screen apart.
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

    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: body,
      ),
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

  /// Gap between the panes.
  final double gap;

  const TwoPaneLayout({
    super.key,
    required this.main,
    required this.aside,
    this.asideWidth = 340,
    this.gap = kSpaceSection,
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
          SizedBox(height: gap),
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
