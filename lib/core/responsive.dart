import 'package:flutter/material.dart';

enum FormFactor { mobile, tablet, desktop }

class Breakpoints {
  static const double tablet = 600.0;
  static const double desktop = 1024.0;
}

extension FormFactorContext on BuildContext {
  FormFactor get formFactor {
    final width = MediaQuery.sizeOf(this).width;
    if (width >= Breakpoints.desktop) return FormFactor.desktop;
    if (width >= Breakpoints.tablet) return FormFactor.tablet;
    return FormFactor.mobile;
  }
}
