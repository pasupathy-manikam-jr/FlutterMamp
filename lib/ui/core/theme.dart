import 'package:flutter/material.dart';

import '../../domain/models/server_status.dart';

/// App-wide theming. A restrained, macOS-native-feeling palette.
class AppTheme {
  static ThemeData light() {
    const seed = Color(0xFF3A7BD5);
    final scheme = ColorScheme.fromSeed(seedColor: seed);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF2F2F7),
      visualDensity: VisualDensity.compact,
      fontFamily: '.AppleSystemUIFont',
    );
  }

  static ThemeData dark() {
    const seed = Color(0xFF3A7BD5);
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      visualDensity: VisualDensity.compact,
      fontFamily: '.AppleSystemUIFont',
    );
  }
}

/// Maps a [ServerStatus] to the traffic-light color MAMP uses.
Color statusColor(ServerStatus status) {
  switch (status) {
    case ServerStatus.running:
      return const Color(0xFF34C759); // green
    case ServerStatus.starting:
    case ServerStatus.stopping:
      return const Color(0xFFFF9F0A); // amber
    case ServerStatus.error:
      return const Color(0xFFFF3B30); // red
    case ServerStatus.stopped:
      return const Color(0xFF8E8E93); // grey
  }
}
