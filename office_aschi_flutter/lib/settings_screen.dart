import 'package:flutter/material.dart';
import 'main.dart' show themeNotifier;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeNotifier,
        builder: (context, mode, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            children: [
              // Appearance section
              Text(
                'Appearance',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    _ThemeTile(
                      icon: Icons.brightness_auto,
                      title: 'System',
                      subtitle: 'Follow device theme',
                      selected: mode == ThemeMode.system,
                      onTap: () => themeNotifier.value = ThemeMode.system,
                    ),
                    const Divider(height: 1, indent: 56),
                    _ThemeTile(
                      icon: Icons.light_mode,
                      title: 'Light',
                      subtitle: 'Always use light theme',
                      selected: mode == ThemeMode.light,
                      onTap: () => themeNotifier.value = ThemeMode.light,
                    ),
                    const Divider(height: 1, indent: 56),
                    _ThemeTile(
                      icon: Icons.dark_mode,
                      title: 'Dark',
                      subtitle: 'Always use dark theme',
                      selected: mode == ThemeMode.dark,
                      onTap: () => themeNotifier.value = ThemeMode.dark,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // About section
              Text(
                'About',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        Icons.info_outline,
                        color: cs.onSurfaceVariant,
                      ),
                      title: const Text('Office Aschi'),
                      subtitle: const Text('v1.0.0'),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: Icon(Icons.code, color: cs.onSurfaceVariant),
                      title: const Text('Built with Flutter'),
                      subtitle: const Text('Cross-platform seat booking'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? cs.primary : cs.onSurfaceVariant),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          color: selected ? cs.primary : null,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_circle, color: cs.primary)
          : const SizedBox.shrink(),
      onTap: onTap,
    );
  }
}
