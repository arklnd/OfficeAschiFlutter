import 'package:flutter/material.dart';
import 'team_search_screen.dart';
import 'team_detail_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Office Aschi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const TeamSearchScreen(),
      onGenerateRoute: (settings) {
        if (settings.name != null && settings.name!.startsWith('/team/')) {
          final id = int.tryParse(settings.name!.replaceFirst('/team/', ''));
          if (id != null) {
            return MaterialPageRoute(
              builder: (_) => TeamDetailScreen(teamId: id),
            );
          }
        }
        return MaterialPageRoute(builder: (_) => const TeamSearchScreen());
      },
    );
  }
}
