import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'api_service.dart';
import 'models.dart';
import 'totp_service.dart';
import 'qr_download.dart';
import 'team_detail_screen.dart';
import 'settings_screen.dart';
import 'update_service.dart';
import 'version.dart';

class TeamSearchScreen extends StatefulWidget {
  const TeamSearchScreen({super.key});

  @override
  State<TeamSearchScreen> createState() => _TeamSearchScreenState();
}

class _TeamSearchScreenState extends State<TeamSearchScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchController = TextEditingController();
  List<TeamSearchResult> _teams = [];
  bool _loading = true;
  String? _error;
  late final StreamSubscription _recoverySub;

  @override
  void initState() {
    super.initState();
    _loadTeams();
    _recoverySub = _api.backendRecovered.stream.listen((_) => _loadTeams());
    _checkForAppUpdate();
  }

  Future<void> _checkForAppUpdate() async {
    // Skip in dev builds and on non-Android platforms.
    if (kIsWeb) return;
    if (appVersion == 'APP_VERSION_PLACEHOLDER') return;

    // Respect user preference.
    if (!await UpdateService.isAutoUpdateEnabled()) return;

    // Let the UI settle before checking.
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final update = await UpdateService.checkForUpdate();
    if (update != null && mounted) {
      showUpdateDialog(context, update);
    }
  }

  @override
  void dispose() {
    _recoverySub.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTeams() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final teams = await _api.searchTeams(
        _searchController.text.isNotEmpty ? _searchController.text : null,
      );
      setState(() {
        _teams = teams;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openCreateTeamDialog() {
    final nameCtrl = TextEditingController();
    final codeCtrl = TextEditingController();
    String secret = TotpService.generateSecret();
    String? verifyError;
    String? nameError;
    bool creating = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final label = nameCtrl.text.isNotEmpty ? nameCtrl.text : 'Team';
          final otpUri = TotpService.getOtpAuthUri(secret, '$label (Manager)');

          return AlertDialog(
            title: const Text('Create Team'),
            content: SizedBox(
              width: 320,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Team Name',
                        errorText: nameError,
                      ),
                      onChanged: (_) {
                        secret = TotpService.generateSecret();
                        codeCtrl.clear();
                        setDialogState(() {
                          verifyError = null;
                          nameError = null;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Scan this QR code with your authenticator app',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: otpUri,
                        version: QrVersions.auto,
                        size: 200,
                        eyeStyle: QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Theme.of(ctx).colorScheme.onSurface,
                        ),
                        dataModuleStyle: QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Theme.of(ctx).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.inverseSurface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SelectableText(
                        secret,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(ctx).colorScheme.onInverseSurface,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final name = nameCtrl.text.isNotEmpty
                                ? nameCtrl.text
                                : 'team';
                            final path = await downloadQrImage(
                              otpUri,
                              'totp-$name-manager.png',
                            );
                            if (path != null && ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(content: Text('QR saved to $path')),
                              );
                            }
                          },
                          icon: const Icon(Icons.download, size: 16),
                          label: const Text('Download QR'),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: secret));
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(content: Text('Secret copied!')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy Secret'),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final uri = Uri.parse(otpUri);
                            try {
                              final launched = await launchUrl(
                                uri,
                                mode: LaunchMode.externalApplication,
                              );
                              if (!launched && ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('No authenticator app found'),
                                  ),
                                );
                              }
                            } catch (_) {
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('No authenticator app found'),
                                  ),
                                );
                              }
                            }
                          },
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Open with Authenticator'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: codeCtrl,
                      decoration: InputDecoration(
                        labelText: 'Verify TOTP Code',
                        hintText: '6-digit code',
                        errorText: verifyError,
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: creating
                    ? null
                    : () async {
                        if (nameCtrl.text.trim().isEmpty) {
                          setDialogState(
                            () => nameError = 'Team name is required',
                          );
                          return;
                        }
                        if (codeCtrl.text.length != 6) {
                          setDialogState(
                            () => verifyError = 'Enter 6-digit code',
                          );
                          return;
                        }
                        setDialogState(() {
                          verifyError = null;
                          nameError = null;
                          creating = true;
                        });
                        try {
                          final team = await _api.createTeam(
                            nameCtrl.text.trim(),
                            secret,
                            codeCtrl.text,
                          );
                          await TotpService.storeSecret(
                            'manager',
                            team.id,
                            secret,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    TeamDetailScreen(teamId: team.id),
                              ),
                            );
                          }
                        } catch (e) {
                          setDialogState(() {
                            verifyError = e.toString().replaceFirst(
                              'Exception: ',
                              '',
                            );
                            creating = false;
                          });
                        }
                      },
                child: Text(creating ? 'Creating...' : 'Create'),
              ),
            ],
          );
        },
      ),
    );
  }

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
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCreateTeamDialog,
        tooltip: 'Create Team',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search teams...',
              leading: const Icon(Icons.search),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      _loadTeams();
                    },
                  ),
              ],
              onSubmitted: (_) => _loadTeams(),
              onChanged: (_) {
                _loadTeams();
                setState(() {});
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadTeams,
              child: _loading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 200),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : _error != null
                  ? LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 32,
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: cs.errorContainer,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      _api.noInternet.value
                                          ? Icons.wifi_off_rounded
                                          : Icons.cloud_off_rounded,
                                      size: 48,
                                      color: cs.onErrorContainer,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    _api.noInternet.value
                                        ? 'No Internet Connection'
                                        : 'Unable to Reach Server',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _api.noInternet.value
                                        ? 'Check your internet connection and try again.'
                                        : 'The backend server is not responding. It may be down for maintenance.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: cs.onSurfaceVariant,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  FilledButton.icon(
                                    onPressed: _loadTeams,
                                    icon: const Icon(Icons.refresh, size: 18),
                                    label: const Text('Try Again'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : _teams.isEmpty
                  ? LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.group_work,
                                  size: 48,
                                  color: cs.onSurfaceVariant,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No teams found',
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                      itemCount: _teams.length,
                      itemBuilder: (context, index) {
                        final team = _teams[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: cs.primary,
                              child: Text(
                                team.name[0].toUpperCase(),
                                style: TextStyle(
                                  color: cs.onPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              team.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Builder(
                              builder: (context) {
                                final cs = Theme.of(context).colorScheme;
                                final isDark =
                                    Theme.of(context).brightness ==
                                    Brightness.dark;
                                return Wrap(
                                  spacing: 6,
                                  children: [
                                    Chip(
                                      label: Text('${team.seatCount} seats'),
                                      backgroundColor: cs.primaryContainer,
                                      labelStyle: TextStyle(
                                        color: cs.onPrimaryContainer,
                                      ),
                                      side: BorderSide.none,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    Chip(
                                      label: Text(
                                        '${team.memberCount} members',
                                      ),
                                      backgroundColor: isDark
                                          ? const Color(0xFF1B3A2A)
                                          : const Color(0xFFD4F5DC),
                                      labelStyle: TextStyle(
                                        color: isDark
                                            ? const Color(0xFFA8DAB5)
                                            : const Color(0xFF1B6B35),
                                      ),
                                      side: BorderSide.none,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ],
                                );
                              },
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TeamDetailScreen(teamId: team.id),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
