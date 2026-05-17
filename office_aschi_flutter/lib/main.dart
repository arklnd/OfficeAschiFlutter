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

Future<void> setThemeMode(ThemeMode mode) async {
  themeNotifier.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('themeMode', mode.name);
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
            return MaterialApp(
              navigatorKey: navigatorKey,
              title: 'Office Aschi',
              debugShowCheckedModeBanner: false,
              themeMode: themeMode,
              theme: ThemeData(
                colorScheme:
                    lightDynamic ??
                    ColorScheme.fromSeed(seedColor: Colors.deepPurple),
                useMaterial3: true,
                cardTheme: CardThemeData(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              darkTheme: ThemeData(
                colorScheme:
                    darkDynamic ??
                    ColorScheme.fromSeed(
                      seedColor: Colors.deepPurple,
                      brightness: Brightness.dark,
                    ),
                useMaterial3: true,
                cardTheme: CardThemeData(
                  elevation: 0,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
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
