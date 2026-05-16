import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'team_search_screen.dart';
import 'team_detail_screen.dart';
import 'settings_screen.dart';

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
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'Office Aschi',
          debugShowCheckedModeBanner: false,
          themeMode: themeMode,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
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
            colorScheme: ColorScheme.fromSeed(
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
            return Column(
              children: [
                _HealthBanner(api: api),
                Expanded(child: child ?? const SizedBox.shrink()),
              ],
            );
          },
          home: const TeamSearchScreen(),
          onGenerateRoute: (settings) {
            if (settings.name == '/settings') {
              return MaterialPageRoute(builder: (_) => const SettingsScreen());
            }
            if (settings.name != null && settings.name!.startsWith('/team/')) {
              final id = int.tryParse(
                settings.name!.replaceFirst('/team/', ''),
              );
              if (id != null) {
                return MaterialPageRoute(
                  builder: (_) => TeamDetailScreen(teamId: id),
                );
              }
            }
            return MaterialPageRoute(builder: (_) => const TeamSearchScreen());
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
