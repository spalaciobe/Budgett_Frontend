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

// ---------------------------------------------------------------------------
// Pre-built EdgeInsets
// ---------------------------------------------------------------------------

/// Standard screen body padding: 16 horizontal, 8 vertical.
const EdgeInsets kScreenPadding =
    EdgeInsets.symmetric(horizontal: 16, vertical: kSpaceLg);

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
