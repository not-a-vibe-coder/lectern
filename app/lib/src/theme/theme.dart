import 'package:flutter/material.dart';
import 'package:sui_wallet_web/sui_wallet_web.dart' show SuiWalletPickerTheme;

import 'tokens.dart';

/// Font families bundled in assets/fonts.
abstract final class Fonts {
  static const display = 'Newsreader';
  static const ui = 'Atkinson';
  static const mono = 'JetBrainsMono';
}

/// Text styles that sit outside the Material text theme.
abstract final class LecternType {
  /// Course codes, set like library call numbers.
  static const code = TextStyle(
    fontFamily: Fonts.mono,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    height: 20 / 15,
    letterSpacing: 0.4,
    color: LecternColors.ink,
  );

  /// Sizes, dates in tables, blob IDs.
  static const mono = TextStyle(
    fontFamily: Fonts.mono,
    fontWeight: FontWeight.w400,
    fontSize: 13,
    height: 18 / 13,
    color: LecternColors.ink2,
  );

  /// Small upper-case labels above headings.
  static const eyebrow = TextStyle(
    fontFamily: Fonts.mono,
    fontWeight: FontWeight.w600,
    fontSize: 12,
    height: 16 / 12,
    letterSpacing: 1.0,
    color: LecternColors.blue,
  );
}

TextTheme _textTheme() {
  const display = Fonts.display;
  const ui = Fonts.ui;
  return const TextTheme(
    displayLarge: TextStyle(
      fontFamily: display,
      fontWeight: FontWeight.w600,
      fontSize: 48,
      height: 52 / 48,
      letterSpacing: -0.8,
      color: LecternColors.ink,
    ),
    displayMedium: TextStyle(
      fontFamily: display,
      fontWeight: FontWeight.w600,
      fontSize: 38,
      height: 44 / 38,
      letterSpacing: -0.5,
      color: LecternColors.ink,
    ),
    displaySmall: TextStyle(
      fontFamily: display,
      fontWeight: FontWeight.w600,
      fontSize: 30,
      height: 36 / 30,
      letterSpacing: -0.3,
      color: LecternColors.ink,
    ),
    headlineMedium: TextStyle(
      fontFamily: display,
      fontWeight: FontWeight.w600,
      fontSize: 26,
      height: 32 / 26,
      letterSpacing: -0.2,
      color: LecternColors.ink,
    ),
    headlineSmall: TextStyle(
      fontFamily: display,
      fontWeight: FontWeight.w600,
      fontSize: 22,
      height: 28 / 22,
      color: LecternColors.ink,
    ),
    titleLarge: TextStyle(
      fontFamily: display,
      fontWeight: FontWeight.w500,
      fontSize: 20,
      height: 26 / 20,
      color: LecternColors.ink,
    ),
    titleMedium: TextStyle(
      fontFamily: ui,
      fontWeight: FontWeight.w700,
      fontSize: 17,
      height: 24 / 17,
      color: LecternColors.ink,
    ),
    titleSmall: TextStyle(
      fontFamily: ui,
      fontWeight: FontWeight.w700,
      fontSize: 15,
      height: 20 / 15,
      color: LecternColors.ink,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    bodyLarge: TextStyle(
      fontFamily: ui,
      fontSize: 17,
      height: 26 / 17,
      color: LecternColors.ink,
    ),
    bodyMedium: TextStyle(
      fontFamily: ui,
      fontSize: 15,
      height: 22 / 15,
      color: LecternColors.ink,
    ),
    bodySmall: TextStyle(
      fontFamily: ui,
      fontSize: 13,
      height: 18 / 13,
      color: LecternColors.ink3,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    labelLarge: TextStyle(
      fontFamily: ui,
      fontWeight: FontWeight.w700,
      fontSize: 15,
      height: 20 / 15,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    labelMedium: TextStyle(
      fontFamily: ui,
      fontWeight: FontWeight.w700,
      fontSize: 13,
      height: 16 / 13,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
    labelSmall: TextStyle(
      fontFamily: Fonts.mono,
      fontWeight: FontWeight.w600,
      fontSize: 12,
      height: 16 / 12,
      letterSpacing: 0.8,
    ),
  );
}

/// A 3 px ink ring drawn outside the control when it has keyboard focus.
BorderSide? _focusSide(Set<WidgetState> states, {BorderSide? otherwise}) {
  if (states.contains(WidgetState.focused)) {
    return const BorderSide(
      color: LecternColors.ink,
      width: 3,
      strokeAlign: BorderSide.strokeAlignOutside,
    );
  }
  return otherwise;
}

ThemeData buildTheme() {
  final text = _textTheme();
  const shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
  );
  final scheme =
      ColorScheme.fromSeed(
        seedColor: LecternColors.blue,
        brightness: Brightness.light,
      ).copyWith(
        primary: LecternColors.blue,
        onPrimary: Colors.white,
        secondary: LecternColors.ink,
        onSecondary: LecternColors.paper,
        surface: LecternColors.paper,
        onSurface: LecternColors.ink,
        onSurfaceVariant: LecternColors.ink2,
        surfaceContainerLowest: LecternColors.surface,
        surfaceContainerLow: LecternColors.surface,
        surfaceContainer: LecternColors.surface,
        surfaceContainerHigh: LecternColors.surface,
        surfaceContainerHighest: LecternColors.sunk,
        outline: LecternColors.control,
        outlineVariant: LecternColors.rule,
        error: LecternColors.danger,
        onError: Colors.white,
      );

  ButtonStyle base(Color fg, {Color? bg, BorderSide? side}) => ButtonStyle(
    minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    ),
    shape: const WidgetStatePropertyAll(shape),
    textStyle: WidgetStatePropertyAll(text.labelLarge),
    side: WidgetStateProperty.resolveWith(
      (states) => _focusSide(states, otherwise: side),
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.disabled) ? LecternColors.ink3 : fg,
    ),
    backgroundColor: bg == null
        ? null
        : WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return LecternColors.sunk;
            }
            if (states.contains(WidgetState.pressed)) {
              return bg == LecternColors.blue ? LecternColors.bluePressed : bg;
            }
            return bg;
          }),
    overlayColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return fg.withValues(alpha: 0.14);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return fg.withValues(alpha: 0.08);
      }
      return null;
    }),
    elevation: const WidgetStatePropertyAll(0),
    visualDensity: VisualDensity.standard,
    tapTargetSize: MaterialTapTargetSize.padded,
  );

  OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(Radii.md)),
    borderSide: BorderSide(color: color, width: width),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: LecternColors.paper,
    canvasColor: LecternColors.paper,
    fontFamily: Fonts.ui,
    textTheme: text,
    dividerTheme: const DividerThemeData(
      color: LecternColors.rule,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: base(Colors.white, bg: LecternColors.blue),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: base(Colors.white, bg: LecternColors.blue),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: base(
        LecternColors.ink,
        bg: LecternColors.surface,
        side: const BorderSide(color: LecternColors.control, width: 1.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: base(LecternColors.blue).copyWith(
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        foregroundColor: const WidgetStatePropertyAll(LecternColors.ink),
        side: WidgetStateProperty.resolveWith((s) => _focusSide(s)),
        shape: const WidgetStatePropertyAll(shape),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: LecternColors.surface,
      isDense: false,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: text.titleSmall!.copyWith(color: LecternColors.ink2),
      floatingLabelStyle: text.titleSmall!.copyWith(color: LecternColors.ink),
      hintStyle: text.bodyMedium!.copyWith(color: LecternColors.ink3),
      helperStyle: text.bodySmall,
      errorStyle: text.bodySmall!.copyWith(
        color: LecternColors.danger,
        fontWeight: FontWeight.w700,
      ),
      errorMaxLines: 3,
      helperMaxLines: 3,
      border: border(LecternColors.control, 1.5),
      enabledBorder: border(LecternColors.control, 1.5),
      focusedBorder: border(LecternColors.blue, 2.5),
      errorBorder: border(LecternColors.danger, 1.5),
      focusedErrorBorder: border(LecternColors.danger, 2.5),
      disabledBorder: border(LecternColors.rule, 1.5),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: LecternColors.surface,
      selectedColor: LecternColors.ink,
      disabledColor: LecternColors.sunk,
      checkmarkColor: LecternColors.paper,
      labelStyle: text.labelMedium!.copyWith(color: LecternColors.ink),
      secondaryLabelStyle: text.labelMedium!.copyWith(
        color: LecternColors.paper,
      ),
      // Keyboard focus: an ink ring, or a highlighter ring on the selected
      // (ink-filled) chip so it stays visible.
      side: WidgetStateBorderSide.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(
            color: states.contains(WidgetState.selected)
                ? LecternColors.highlighter
                : LecternColors.ink,
            width: 3,
          );
        }
        return const BorderSide(color: LecternColors.control);
      }),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.pill)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      showCheckmark: false,
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: LecternColors.control, width: 2),
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? LecternColors.blue : null,
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? null : LecternColors.control,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: LecternColors.blue,
      linearTrackColor: LecternColors.blueTint,
      circularTrackColor: LecternColors.blueTint,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: LecternColors.ink,
      contentTextStyle: text.bodyMedium!.copyWith(color: LecternColors.paper),
      actionTextColor: LecternColors.highlighter,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: LecternColors.paper,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.lg)),
      ),
      titleTextStyle: text.headlineSmall,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: LecternColors.paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: LecternColors.ruleStrong,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: LecternColors.surface,
      surfaceTintColor: Colors.transparent,
      textStyle: text.bodyMedium,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(Radii.md)),
        side: BorderSide(color: LecternColors.rule),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: const BoxDecoration(
        color: LecternColors.ink,
        borderRadius: BorderRadius.all(Radius.circular(Radii.sm)),
      ),
      textStyle: text.bodySmall!.copyWith(color: LecternColors.paper),
      waitDuration: const Duration(milliseconds: 400),
      exitDuration: Duration.zero,
    ),
    focusColor: LecternColors.blue.withValues(alpha: 0.12),
    hoverColor: LecternColors.ink.withValues(alpha: 0.04),
    splashFactory: InkRipple.splashFactory,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: [
      // The shared wallet picker, dressed in Lectern's paper and ink.
      SuiWalletPickerTheme(
        tileColor: LecternColors.surface,
        tileHoverColor: LecternColors.blueTint,
        tileBorderColor: LecternColors.control,
        tileSelectedBorderColor: LecternColors.blue,
        tileRadius: const BorderRadius.all(Radius.circular(Radii.md)),
        focusColor: LecternColors.blue,
        progressColor: LecternColors.blue,
        titleStyle: text.headlineSmall,
        nameStyle: text.titleMedium,
        bodyStyle: text.bodyMedium!.copyWith(color: LecternColors.ink2),
        errorStyle: text.bodyMedium!.copyWith(color: LecternColors.danger),
        errorBackgroundColor: LecternColors.dangerTint,
        linkStyle: text.bodyMedium!.copyWith(
          color: LecternColors.blue,
          decoration: TextDecoration.underline,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}
