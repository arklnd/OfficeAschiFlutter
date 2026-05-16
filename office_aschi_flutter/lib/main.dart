import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
