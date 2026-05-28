import 'package:flutter/material.dart';
import 'team_search_screen.dart';
import 'seat_search_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  static const List<Widget> _screens = [
    TeamSearchScreen(),
    SeatSearchScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Office Aschi'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            style: IconButton.styleFrom(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
            ),
            onPressed: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const SettingsScreen(),
                  transitionsBuilder: (_, animation, __, child) {
                    return SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(1, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeInOut,
                      )),
                      child: child,
                    );
                  },
                  transitionDuration: const Duration(milliseconds: 300),
                  reverseTransitionDuration: const Duration(milliseconds: 300),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Teams',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_seat_outlined),
            selectedIcon: Icon(Icons.event_seat),
            label: 'Seat Search',
          ),
        ],
      ),
    );
  }
}
