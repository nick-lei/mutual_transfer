import 'package:flutter/material.dart';

const ink = Color(0xFF17233A);
const muted = Color(0xFF62718A);
const blue = Color(0xFF2463EB);
const blueTint = Color(0xFFEAF0FF);
const canvas = Color(0xFFF5F7FC);
const shell = Color(0xFFEDF2FC);
const line = Color(0xFFE0E7F2);
const green = Color(0xFF147D5A);
const mint = Color(0xFFE7F6EF);
const danger = Color(0xFFB83D4E);
const amber = Color(0xFF986111);
const uiMotion = Duration(milliseconds: 180);

ThemeData nearLinkTheme({bool android = false}) {
  final font = android ? 'Roboto' : 'Microsoft YaHei UI';
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: line),
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: font,
    fontFamilyFallback: android ? null : const ['Microsoft YaHei', 'Segoe UI'],
    scaffoldBackgroundColor: canvas,
    bottomSheetTheme: android
        ? const BottomSheetThemeData(
            backgroundColor: Colors.white,
            modalBackgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
          )
        : null,
    colorScheme: ColorScheme.fromSeed(seedColor: blue).copyWith(
      primary: blue,
      onPrimary: Colors.white,
      surface: Colors.white,
      onSurface: ink,
      onSurfaceVariant: muted,
      error: danger,
      outline: muted,
      outlineVariant: line,
      surfaceTint: Colors.transparent,
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.35,
        color: ink,
      ),
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.4,
        color: ink,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.5,
        color: ink,
      ),
      bodyLarge: TextStyle(fontSize: 15, height: 1.6, color: ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: ink),
      bodySmall: TextStyle(fontSize: 12, height: 1.5, color: muted),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    dividerColor: line,
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(
        color: ink,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(fontSize: 12, color: Colors.white),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF8FAFE),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      hintStyle: const TextStyle(fontSize: 13, color: muted),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: blue, width: android ? 1.5 : 2),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: danger),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: android ? Colors.white : null,
        backgroundColor: android ? blue : null,
        disabledForegroundColor: android ? muted : null,
        disabledBackgroundColor: android ? line : null,
        minimumSize: Size(0, android ? 48 : 44),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        shape: shape,
        textStyle: TextStyle(
          fontFamily: font,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, android ? 48 : 44),
        foregroundColor: ink,
        side: const BorderSide(color: line),
        shape: shape,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        textStyle: TextStyle(
          fontFamily: font,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: Size(0, android ? 48 : 40),
        shape: shape,
        textStyle: TextStyle(
          fontFamily: font,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: muted,
        iconSize: 20,
        minimumSize: Size.square(android ? 48 : 40),
        padding: const EdgeInsets.all(10),
        shape: shape,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: blueTint,
      labelStyle: TextStyle(fontFamily: font, fontSize: 13, color: muted),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      showCheckmark: false,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: blue,
      linearTrackColor: blueTint,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: blue,
      selectionColor: blue.withValues(alpha: .18),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: ink,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(
        fontFamily: font,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: ink,
      ),
      contentTextStyle: TextStyle(
        fontFamily: font,
        fontSize: 14,
        height: 1.6,
        color: muted,
      ),
    ),
  );
}
