import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'background_update.dart';
import 'team_search_screen.dart';
import 'team_detail_screen.dart';
import 'settings_screen.dart';
import 'update_service.dart';

/// Global navigator key – used to show dialogs from notification taps.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);
final ValueNotifier<bool> dynamicColorNotifier = ValueNotifier(true);

Future<void> setThemeMode(ThemeMode mode) async {
  themeNotifier.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('themeMode', mode.name);
}

Future<void> setDynamicColor(bool enabled) async {
  dynamicColorNotifier.value = enabled;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('dynamicColor', enabled);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('themeMode');
  if (saved != null) {
    themeNotifier.value = ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.system,
    );
  }
  dynamicColorNotifier.value = prefs.getBool('dynamicColor') ?? true;
  await BackgroundUpdateManager.init();
  await BackgroundUpdateManager.syncWithPreference();
  await DownloadManager.instance.initNotifications();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            return ValueListenableBuilder<bool>(
              valueListenable: dynamicColorNotifier,
              builder: (context, useDynamic, _) {
                final effectiveLight = useDynamic ? lightDynamic : null;
                final effectiveDark = useDynamic ? darkDynamic : null;
                final lightScheme =
                    effectiveLight ??
                    ColorScheme.fromSeed(seedColor: Colors.deepPurple);
                final darkScheme =
                    effectiveDark ??
                    ColorScheme.fromSeed(
                      seedColor: Colors.deepPurple,
                      brightness: Brightness.dark,
                    );
                return MaterialApp(
                  navigatorKey: navigatorKey,
                  title: 'Office Aschi',
                  debugShowCheckedModeBanner: false,
                  themeMode: themeMode,
                  theme: _buildTheme(lightScheme),
                  darkTheme: _buildTheme(darkScheme),
                  builder: (context, child) {
                    final api = ApiService();
                    Widget content = Column(
                      children: [
                        _HealthBanner(api: api),
                        Expanded(child: child ?? const SizedBox.shrink()),
                      ],
                    );
                    if (kDebugMode) {
                      content = Banner(
                        message: 'debug build',
                        location: BannerLocation.topStart,
                        child: content,
                      );
                    }
                    return content;
                  },
                  home: const TeamSearchScreen(),
                  onGenerateRoute: (settings) {
                    if (settings.name == '/settings') {
                      return MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      );
                    }
                    if (settings.name != null &&
                        settings.name!.startsWith('/team/')) {
                      final id = int.tryParse(
                        settings.name!.replaceFirst('/team/', ''),
                      );
                      if (id != null) {
                        return MaterialPageRoute(
                          builder: (_) => TeamDetailScreen(teamId: id),
                        );
                      }
                    }
                    return MaterialPageRoute(
                      builder: (_) => const TeamSearchScreen(),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  static ThemeData _buildTheme(ColorScheme colorScheme) {
    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerLow,
        shadowColor: colorScheme.shadow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        surfaceTintColor: colorScheme.surfaceTint,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        labelStyle: const TextStyle(fontSize: 11),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      dividerTheme: const DividerThemeData(space: 1),
      switchTheme: SwitchThemeData(
        thumbIcon: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Icon(Icons.check, size: 16);
          }
          return null;
        }),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 3,
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: colorScheme.secondaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      searchBarTheme: SearchBarThemeData(
        elevation: WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(
          colorScheme.surfaceContainerHigh,
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: colorScheme.surfaceContainerHighest,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _HealthBanner extends StatelessWidget {
  final ApiService api;
  const _HealthBanner({required this.api});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([api.backendDown, api.noInternet]),
      builder: (context, _) {
        if (!api.backendDown.value) return const SizedBox.shrink();
        final isNoInternet = api.noInternet.value;
        final cs = Theme.of(context).colorScheme;
        return Material(
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              bottom: 8,
              left: 16,
              right: 16,
            ),
            color: isNoInternet ? cs.errorContainer : cs.errorContainer,
            child: Row(
              children: [
                Icon(
                  isNoInternet ? Icons.wifi_off : Icons.cloud_off,
                  size: 18,
                  color: cs.onErrorContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isNoInternet
                        ? 'No internet connection'
                        : 'Backend server is unavailable',
                    style: TextStyle(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
