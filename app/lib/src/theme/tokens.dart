import 'package:flutter/material.dart';

/// Colour tokens.
abstract final class LecternColors {
  /// Notebook paper, the page background.
  static const paper = Color(0xFFFBFAF5);
  static const surface = Color(0xFFFFFFFF);
  static const sunk = Color(0xFFF1F0EA);

  /// Ruled lines and hairline dividers (decorative only).
  static const rule = Color(0xFFD5DCEB);
  static const ruleStrong = Color(0xFF9AA6C4);

  /// Borders of inputs and other controls (3:1 or better on paper).
  static const control = Color(0xFF7A839B);

  /// Blue-black ink and two quieter inks for secondary text.
  static const ink = Color(0xFF141A2E);
  static const ink2 = Color(0xFF444B60);
  static const ink3 = Color(0xFF5E6578);

  /// Ballpoint blue: the one action colour.
  static const blue = Color(0xFF2437C2);
  static const bluePressed = Color(0xFF1B2A99);
  static const blueTint = Color(0xFFE9ECF8);

  /// Highlighter: marks what is new and what matched a search.
  static const highlighter = Color(0xFFFFE45E);
  static const highlighterSoft = Color(0xFFFFF3B0);

  /// The red margin line of an exercise book. Decorative hairline only.
  static const margin = Color(0xFFE07A73);

  static const danger = Color(0xFFB3261E);
  static const dangerTint = Color(0xFFFBEAE8);
  static const success = Color(0xFF1E6E46);
  static const successTint = Color(0xFFE6F2EB);
  static const warn = Color(0xFF7A4F00);
  static const warnTint = Color(0xFFFFF4D6);

  /// Item type tags: text colour on a tint.
  static const lectureInk = blue;
  static const lectureTint = blueTint;
  static const pastInk = Color(0xFF8A3412);
  static const pastTint = Color(0xFFFBEDE3);
  static const assignmentInk = success;
  static const assignmentTint = successTint;
  static const otherInk = ink2;
  static const otherTint = sunk;
}

abstract final class Space {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
  static const xxxl = 64.0;
}

abstract final class Radii {
  static const sm = 4.0;
  static const md = 6.0;
  static const lg = 10.0;
  static const pill = 999.0;
}

/// Motion tokens. Curves are Emil Kowalski's strong variants: things that
/// enter or leave decelerate hard, so the first frames move the most.
abstract final class Motion {
  /// Press feedback going down, and coming back up.
  static const pressIn = Duration(milliseconds: 100);
  static const pressOut = Duration(milliseconds: 160);

  /// Colour and opacity feedback (hover, focus).
  static const micro = Duration(milliseconds: 100);

  /// Small things appearing: menus, popovers, tooltips.
  static const short = Duration(milliseconds: 150);

  /// Sheets and dialogs entering; they leave faster ([exit]).
  static const enter = Duration(milliseconds: 260);
  static const exit = Duration(milliseconds: 180);

  /// Page cross-fades.
  static const page = Duration(milliseconds: 160);
  static const pageExit = Duration(milliseconds: 120);

  static const easeOut = Cubic(0.23, 1, 0.32, 1);
  static const easeInOut = Cubic(0.77, 0, 0.175, 1);
  static const drawer = Cubic(0.32, 0.72, 0, 1);
  static const curve = easeOut;

  /// True when the system asks for reduced motion.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Durations collapse to zero when the system asks for reduced motion.
  static Duration of(BuildContext context, Duration d) =>
      reduced(context) ? Duration.zero : d;

  /// Sheets rise on the drawer curve and leave quickly. Reduced motion: none.
  static AnimationStyle sheet(BuildContext context) => reduced(context)
      ? AnimationStyle.noAnimation
      : AnimationStyle(
          duration: enter,
          reverseDuration: exit,
          curve: drawer,
          reverseCurve: easeOut.flipped,
        );

  /// Dialogs fade and settle; modals stay centred (they have no trigger).
  static AnimationStyle dialog(BuildContext context) => reduced(context)
      ? AnimationStyle.noAnimation
      : AnimationStyle(
          duration: const Duration(milliseconds: 200),
          reverseDuration: const Duration(milliseconds: 140),
          curve: easeOut,
          reverseCurve: easeOut.flipped,
        );

  /// Menus grow from their trigger, fast.
  static AnimationStyle menu(BuildContext context) => reduced(context)
      ? AnimationStyle.noAnimation
      : AnimationStyle(
          duration: short,
          reverseDuration: const Duration(milliseconds: 100),
          curve: easeOut,
        );
}

abstract final class Elevation {
  /// The only shadow: floating sheets, dialogs and menus.
  static const floating = [
    BoxShadow(color: Color(0x1F141A2E), blurRadius: 24, offset: Offset(0, 8)),
  ];
}

/// Layout breakpoints, in logical pixels.
abstract final class Breakpoints {
  static const medium = 600.0;
  static const expanded = 1024.0;
  static const contentMax = 1120.0;
  static const readingMax = 720.0;

  static double gutter(double width) => width >= expanded
      ? 32
      : width >= medium
      ? 24
      : 16;
}
