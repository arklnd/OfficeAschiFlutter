import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'background_update.dart';
import 'main.dart'
    show themeNotifier, setThemeMode, dynamicColorNotifier, setDynamicColor;
import 'update_service.dart';
import 'version.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoUpdate = true;

  @override
  void initState() {
    super.initState();
    _loadAutoUpdatePref();
  }

  Future<void> _loadAutoUpdatePref() async {
    final enabled = await UpdateService.isAutoUpdateEnabled();
    if (mounted) setState(() => _autoUpdate = enabled);
  }

  Future<void> _toggleAutoUpdate(bool value) async {
    setState(() => _autoUpdate = value);
    await UpdateService.setAutoUpdateEnabled(value);
    await BackgroundUpdateManager.syncWithPreference();
  }

  static Future<void> _checkForUpdate(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    final update = await UpdateService.checkForUpdate();

    if (!context.mounted) return;
    Navigator.of(context).pop(); // dismiss spinner

    if (update != null) {
      showUpdateDialog(context, update);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You\'re already on the latest version.')),
      );
    }
  }

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
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: Text(
                  'Appearance',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: cs.primary),
                ),
              ),
              Card(
                child: Column(
                  children: [
                    _ThemeTile(
                      icon: Icons.brightness_auto,
                      title: 'System',
                      subtitle: 'Follow device theme',
                      selected: mode == ThemeMode.system,
                      onTap: () => setThemeMode(ThemeMode.system),
                    ),
                    _ThemeTile(
                      icon: Icons.light_mode,
                      title: 'Light',
                      subtitle: 'Always use light theme',
                      selected: mode == ThemeMode.light,
                      onTap: () => setThemeMode(ThemeMode.light),
                    ),
                    _ThemeTile(
                      icon: Icons.dark_mode,
                      title: 'Dark',
                      subtitle: 'Always use dark theme',
                      selected: mode == ThemeMode.dark,
                      onTap: () => setThemeMode(ThemeMode.dark),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ValueListenableBuilder<bool>(
                  valueListenable: dynamicColorNotifier,
                  builder: (context, useDynamic, _) {
                    return SwitchListTile(
                      secondary: _IconBox(icon: Icons.palette, colorScheme: cs),
                      title: const Text('Dynamic color'),
                      subtitle: const Text(
                        'Use wallpaper colors (Android 12+)',
                      ),
                      value: useDynamic,
                      onChanged: (v) => setDynamicColor(v),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
              // Updates section (Android only)
              if (!kIsWeb) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 8),
                  child: Text(
                    'Updates',
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: cs.primary),
                  ),
                ),
                Card(
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: _IconBox(
                          icon: Icons.update,
                          colorScheme: cs,
                        ),
                        title: const Text('Automatic update check'),
                        subtitle: const Text(
                          'Check for updates when the app opens or using background updates.',
                        ),
                        value: _autoUpdate,
                        onChanged: _toggleAutoUpdate,
                      ),
                      ListTile(
                        leading: _IconBox(
                          icon: Icons.system_update,
                          colorScheme: cs,
                        ),
                        title: const Text('Check for updates'),
                        subtitle: Text('Channel: ${UpdateService.channel}'),
                        trailing: Icon(
                          Icons.chevron_right,
                          color: cs.onSurfaceVariant,
                        ),
                        onTap: () => _checkForUpdate(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              // About section
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: Text(
                  'About',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: cs.primary),
                ),
              ),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: _IconBox(
                        icon: Icons.info_outline,
                        colorScheme: cs,
                      ),
                      title: const Text('Office Aschi'),
                      subtitle: Text(
                        appVersion == 'APP_VERSION_PLACEHOLDER'
                            ? 'dev (${UpdateService.channel})'
                            : 'v$appVersion (${UpdateService.channel})',
                      ),
                    ),
                    ListTile(
                      leading: _IconBox(icon: Icons.code, colorScheme: cs),
                      title: const Text('Built with Flutter'),
                      subtitle: const Text('Cross-platform seat booking'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // GitHub section
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 8),
                child: Text(
                  'GitHub',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: cs.primary),
                ),
              ),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: _IconBox(icon: Icons.source, colorScheme: cs),
                      title: const Text('Source Code'),
                      subtitle: const Text('arklnd/OfficeAschiFlutter'),
                      trailing: Icon(
                        Icons.open_in_new,
                        color: cs.onSurfaceVariant,
                      ),
                      onTap: () => launchUrl(
                        Uri.parse(
                          'https://github.com/arklnd/OfficeAschiFlutter',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    ListTile(
                      leading: _IconBox(
                        icon: Icons.bug_report,
                        colorScheme: cs,
                      ),
                      title: const Text('Report an Issue'),
                      subtitle: const Text('Bugs & feature requests'),
                      trailing: Icon(
                        Icons.open_in_new,
                        color: cs.onSurfaceVariant,
                      ),
                      onTap: () => launchUrl(
                        Uri.parse(
                          'https://github.com/arklnd/OfficeAschiFlutter/issues',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                    ListTile(
                      leading: _IconBox(
                        icon: Icons.new_releases_outlined,
                        colorScheme: cs,
                      ),
                      title: const Text('Releases'),
                      subtitle: const Text('Download latest versions'),
                      trailing: Icon(
                        Icons.open_in_new,
                        color: cs.onSurfaceVariant,
                      ),
                      onTap: () => launchUrl(
                        Uri.parse(
                          'https://github.com/arklnd/OfficeAschiFlutter/releases',
                        ),
                        mode: LaunchMode.externalApplication,
                      ),
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
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          size: 22,
        ),
      ),
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

class _IconBox extends StatelessWidget {
  final IconData icon;
  final ColorScheme colorScheme;

  const _IconBox({required this.icon, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 22),
    );
  }
}
