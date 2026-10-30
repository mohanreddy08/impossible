import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Opening a page: it fades in while rising a few pixels (and the reverse when going back). Light on purpose (one opacity + one
/// translate, no blur or scaling), so it stays smooth on low-end phones. Skipped when "reduce motion" is on.
class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const SoftPageTransitionsBuilder();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 280);
  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 220);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Tk.primary,
        brightness: Brightness.light,
      ).copyWith(
        primary: Tk.primary,
        onPrimary: Tk.onPrimary,
        secondary: Tk.primaryDark,
        surface: Tk.surface,
        onSurface: Tk.text,
        error: Tk.danger,
      );
  const base = TextStyle(color: Tk.text, height: 1.35);
  final text = TextTheme(
    headlineMedium: base.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
    titleLarge: base.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
    titleMedium: base.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
    bodyLarge: base.copyWith(fontSize: 16),
    bodyMedium: base.copyWith(fontSize: 15),
    bodySmall: base.copyWith(fontSize: 13, color: Tk.textMuted),
    labelLarge: base.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
  );
  final shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Tk.rButton),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Tk.page,
    textTheme: text,
    visualDensity: VisualDensity.standard,
    splashFactory: InkRipple.splashFactory,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, Tk.minTouch),
        shape: shape,
        textStyle: text.labelLarge,
        backgroundColor: Tk.primary,
        foregroundColor: Colors.white,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, Tk.minTouch),
        shape: shape,
        side: const BorderSide(color: Tk.border, width: 1.5),
        foregroundColor: Tk.primaryDark,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: Tk.primary,
        textStyle: text.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tk.rButton),
        borderSide: const BorderSide(color: Tk.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tk.rButton),
        borderSide: const BorderSide(color: Tk.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tk.rButton),
        borderSide: const BorderSide(color: Tk.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tk.rButton),
        borderSide: const BorderSide(color: Tk.danger, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Tk.rButton),
        borderSide: const BorderSide(color: Tk.danger, width: 2),
      ),
      errorStyle: const TextStyle(
        color: Tk.danger,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerTheme: const DividerThemeData(color: Tk.border, space: 1),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: shape,
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: SoftPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}
