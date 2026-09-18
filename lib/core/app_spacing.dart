import 'package:flutter/widgets.dart';

// ---------------------------------------------------------------------------
// Spacing scale
// ---------------------------------------------------------------------------
// Rule of thumb: one step tighter than Material defaults.
// Use these constants instead of raw numeric literals for vertical spacing.

const double kSpaceXs = 2; // hair gaps inside a row
const double kSpaceSm = 4; // subtitle → value inside a tile
const double kSpaceMd = 6; // row-internal separators
const double kSpaceLg = 8; // section-internal gaps
const double kSpaceXl = 12; // between cards / major sections
const double kSpaceXxl = 16; // screen body padding (was 24)

/// Bottom inset for scrollables that sit under a FloatingActionButton, so the
/// last row isn't hidden behind it (FAB is ~56px + margin).
const double kFabSafeBottom = 80;

/// Canonical corner radius for cards/surfaces (matches the CardTheme).
const double kCardRadius = 16;

// ---------------------------------------------------------------------------
// Pre-built EdgeInsets
// ---------------------------------------------------------------------------

/// Standard screen body padding: 16 horizontal, 8 vertical.
const EdgeInsets kScreenPadding =
    EdgeInsets.symmetric(horizontal: 16, vertical: kSpaceLg);

/// Screen body padding for lists under a FAB: standard top/sides, extra bottom
/// so the last item clears the floating action button.
const EdgeInsets kScreenPaddingWithFab =
    EdgeInsets.fromLTRB(16, kSpaceLg, 16, kFabSafeBottom);

/// Standard card internal padding: 12 all-around.
const EdgeInsets kCardPadding = EdgeInsets.all(kSpaceXl);

/// Standard dialog body padding: 16 all-around.
const EdgeInsets kDialogPadding = EdgeInsets.all(kSpaceXxl);

/// Standard ListTile content padding: 12 horizontal, 4 vertical.
const EdgeInsets kTileContentPadding =
    EdgeInsets.symmetric(horizontal: 12, vertical: kSpaceSm);

// ---------------------------------------------------------------------------
// Pre-built vertical gap widgets
// ---------------------------------------------------------------------------

const Widget kGapXs = SizedBox(height: kSpaceXs);
const Widget kGapSm = SizedBox(height: kSpaceSm);
const Widget kGapMd = SizedBox(height: kSpaceMd);
const Widget kGapLg = SizedBox(height: kSpaceLg);
const Widget kGapXl = SizedBox(height: kSpaceXl);
const Widget kGapXxl = SizedBox(height: kSpaceXxl);

// ---------------------------------------------------------------------------
// Breathing room
// ---------------------------------------------------------------------------
// The scale above is deliberately tight, which is right for long lists and
// wrong for the places a screen needs a visual entry point. These are the
// exceptions: use them around the one element that should dominate a screen
// (a hero balance, a section that starts a new idea), not everywhere.

/// Gap between a screen's hero element and the content under it.
const double kSpaceSection = 20;

/// Gap that separates two unrelated ideas on the same screen.
const double kSpaceBlock = 28;

const Widget kGapSection = SizedBox(height: kSpaceSection);
const Widget kGapBlock = SizedBox(height: kSpaceBlock);

/// Padding for a card that holds a headline number, as opposed to a list row.
const EdgeInsets kHeroCardPadding = EdgeInsets.all(kSpaceSection);

/// Max line length for readable prose (empty states, explanations). Beyond
/// ~70 characters the eye loses the start of the next line.
const double kProseMaxWidth = 560;

/// Max width for a single column of content (forms, review sheets).
const double kColumnMaxWidth = 720;

/// Max width for a data-dense page body on a wide screen. Wider than this and
/// a row's label and its amount end up a screen apart.
const double kPageMaxWidth = 1180;
