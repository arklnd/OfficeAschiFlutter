import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_update.dart';
import 'version.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class AppUpdate {
  final int buildNumber;
  final String version;
  final String tagName;
  final String downloadUrl;
  final int sizeBytes;
  final String releaseName;
  final String changelog;

  const AppUpdate({
    required this.buildNumber,
    required this.version,
    required this.tagName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.releaseName,
    required this.changelog,
  });
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class UpdateService {
  static const _owner = 'arklnd';
  static const _repo = 'OfficeAschiFlutter';
  static const _autoUpdateKey = 'autoUpdateCheck';

  /// 'debug' when running a debug build, 'release' otherwise.
  static String get channel => kDebugMode ? 'debug' : 'release';

  /// Whether automatic update checks on app start are enabled.
  static Future<bool> isAutoUpdateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoUpdateKey) ?? true;
  }

  /// Persist the auto-update-check preference.
  static Future<void> setAutoUpdateEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoUpdateKey, enabled);
  }

  /// Build number extracted from [appVersion] ("23.0.0-a35ced4" → 23).
  static int? get currentBuildNumber {
    if (appVersion == 'APP_VERSION_PLACEHOLDER') return null;
    return int.tryParse(appVersion.split('.').first);
  }

  /// Queries GitHub Releases and returns the newest release for the current
  /// channel whose build number is greater than [currentBuildNumber].
  static Future<AppUpdate?> checkForUpdate() async {
    if (kIsWeb) return null;
    if (!Platform.isAndroid) return null;

    try {
      final httpClient = HttpClient();
      try {
        final request = await httpClient.getUrl(
          Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases'),
        );
        request.headers.set('Accept', 'application/vnd.github+json');
        final response = await request.close().timeout(
          const Duration(seconds: 15),
        );

        if (response.statusCode != 200) return null;

        final body = await response.transform(utf8.decoder).join();
        final List<dynamic> releases = jsonDecode(body);
        final ch = channel;

        AppUpdate? latest;

        for (final release in releases) {
          final tag = release['tag_name'] as String? ?? '';
          if (!tag.contains('-$ch-')) continue;

          final buildNum = _extractBuildNumber(tag);
          if (buildNum == null) continue;

          final assets = release['assets'] as List<dynamic>? ?? [];
          final apkAsset = assets
              .cast<Map<String, dynamic>>()
              .where((a) => (a['name'] as String? ?? '').endsWith('.apk'))
              .firstOrNull;
          if (apkAsset == null) continue;

          if (latest == null || buildNum > latest.buildNumber) {
            latest = AppUpdate(
              buildNumber: buildNum,
              version: _extractVersion(tag),
              tagName: tag,
              downloadUrl: apkAsset['browser_download_url'] as String,
              sizeBytes: apkAsset['size'] as int? ?? 0,
              releaseName: release['name'] as String? ?? '',
              changelog: _extractChangelog(release['body'] as String? ?? ''),
            );
          }
        }

        if (latest == null) return null;

        final current = currentBuildNumber;
        if (current == null || latest.buildNumber > current) {
          return latest;
        }
        return null;
      } finally {
        httpClient.close();
      }
    } catch (e) {
      debugPrint('Update check failed: $e');
      return null;
    }
  }

  /// Expected APK filename for a given update (mirrors the GitHub asset name).
  static String apkFileName(AppUpdate update) {
    return 'office-aschi-flutter-$channel-${update.version}.apk';
  }

  /// Returns the public Downloads directory.
  static Future<Directory> _downloadDir() async {
    final dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Checks whether the APK for [update] is already fully downloaded.
  /// Returns the [File] if it exists with the expected size, otherwise `null`.
  static Future<File?> getExistingApk(AppUpdate update) async {
    final dir = await _downloadDir();
    final file = File('${dir.path}/${apkFileName(update)}');
    if (await file.exists()) {
      final length = await file.length();
      // If the remote size is known, verify the file is complete.
      if (update.sizeBytes > 0 && length == update.sizeBytes) return file;
      if (update.sizeBytes <= 0 && length > 0) return file;
      // Incomplete / corrupt – remove it.
      await file.delete();
    }
    return null;
  }

  /// Installs an already-downloaded APK.
  static Future<void> installApk(File file) async {
    await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
  }

  /// Downloads the APK to the Downloads folder (or installs an existing one)
  /// then launches the system package installer.
  ///
  /// The download is resilient to interruptions (app backgrounded, screen
  /// locked, transient network errors). It writes to a `.part` temp file and
  /// uses HTTP `Range` headers to resume from the last received byte. Up to
  /// [maxRetries] automatic retries are attempted with exponential back-off.
  ///
  /// Prefer using [DownloadManager] instead — it wraps this method with
  /// singleton state, notification support, and cancellation.
  static Future<void> downloadAndInstall(
    AppUpdate update, {
    ValueChanged<double>? onProgress,
    ValueChanged<List<String>>? onCleaned,
    int maxRetries = 5,
    bool Function()? isCancelled,
  }) async {
    // If the APK was already downloaded, skip straight to install.
    final existing = await getExistingApk(update);
    if (existing != null) {
      onProgress?.call(1.0);
      await installApk(existing);
      return;
    }

    final dir = await _downloadDir();
    final fileName = apkFileName(update);
    final file = File('${dir.path}/$fileName');
    final partFile = File('${dir.path}/$fileName.part');

    // Remove stale update APKs from previous versions.
    final cleaned = await _cleanOldApks(dir, fileName);
    if (cleaned.isNotEmpty) onCleaned?.call(cleaned);

    final totalBytes = update.sizeBytes;
    int attempt = 0;

    while (true) {
      if (isCancelled?.call() == true) {
        throw Exception('Download cancelled');
      }

      HttpClient? httpClient;
      try {
        // Determine how many bytes we already have from a previous attempt.
        int alreadyReceived = 0;
        if (await partFile.exists()) {
          alreadyReceived = await partFile.length();
          // If we somehow have more than expected, start fresh.
          if (totalBytes > 0 && alreadyReceived >= totalBytes) {
            await partFile.delete();
            alreadyReceived = 0;
          }
        }

        httpClient = HttpClient();
        final request = await httpClient.getUrl(Uri.parse(update.downloadUrl));

        // Request only the remaining bytes if we already have a partial file.
        if (alreadyReceived > 0) {
          request.headers.set('Range', 'bytes=$alreadyReceived-');
        }

        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );

        // 200 = full content, 206 = partial content (resume accepted).
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception('Download failed: HTTP ${response.statusCode}');
        }

        // If server returned 200 (ignoring Range), start from scratch.
        if (response.statusCode == 200 && alreadyReceived > 0) {
          await partFile.delete();
          alreadyReceived = 0;
        }

        final sink = partFile.openWrite(
          mode: alreadyReceived > 0 ? FileMode.append : FileMode.write,
        );
        int received = alreadyReceived;

        try {
          await for (final chunk in response) {
            if (isCancelled?.call() == true) {
              throw Exception('Download cancelled');
            }
            sink.add(chunk);
            received += chunk.length;
            if (totalBytes > 0) {
              onProgress?.call(received / totalBytes);
            }
          }
        } finally {
          await sink.flush();
          await sink.close();
        }

        // Verify completeness.
        if (totalBytes > 0 && received < totalBytes) {
          throw Exception(
            'Incomplete download ($received / $totalBytes bytes)',
          );
        }

        // Verify the .part file on disk matches what we expect.
        final partLen = await partFile.length();
        if (totalBytes > 0 && partLen != totalBytes) {
          await partFile.delete();
          throw Exception(
            'File verification failed (disk: $partLen, expected: $totalBytes bytes)',
          );
        }

        // Download complete – rename .part → final file.
        await partFile.rename(file.path);
        onProgress?.call(1.0);
        await installApk(file);
        return; // success – exit loop
      } catch (e) {
        if (e.toString().contains('Download cancelled')) rethrow;

        attempt++;
        httpClient?.close(force: true);

        if (attempt >= maxRetries) {
          // Clean up the partial file on final failure.
          try {
            if (await partFile.exists()) await partFile.delete();
          } catch (_) {}
          rethrow;
        }

        // Exponential back-off: 2s, 4s, 8s, 16s, 32s …
        final delay = Duration(seconds: 1 << attempt);
        debugPrint(
          'Download interrupted (attempt $attempt/$maxRetries), '
          'retrying in ${delay.inSeconds}s: $e',
        );
        await Future.delayed(delay);
        // Loop continues → resume from partial file.
      }
    }
  }

  /// Removes old Office Aschi APKs for the current [channel] from [dir],
  /// keeping [currentName] and any file from a different channel untouched.
  /// Returns the version strings of deleted files.
  static Future<List<String>> _cleanOldApks(
    Directory dir,
    String currentName,
  ) async {
    final deleted = <String>[];
    final prefix = 'office-aschi-flutter-$channel-';
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith(prefix) &&
              name.endsWith('.apk') &&
              name != currentName) {
            // Extract version: "office-aschi-flutter-debug-23.0.0-a35ced4.apk" → "23.0.0-a35ced4"
            final version = name
                .replaceFirst(prefix, '')
                .replaceFirst('.apk', '');
            await entity.delete();
            deleted.add(version);
          }
        }
      }
    } catch (_) {}
    return deleted;
  }

  // -- helpers --------------------------------------------------------------

  static int? _extractBuildNumber(String tag) {
    final match = RegExp(r'^v(\d+)-').firstMatch(tag);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  static String _extractVersion(String tag) {
    final parts = tag.substring(1).split('-');
    if (parts.length >= 3) {
      return '${parts[0]}.0.0-${parts.last}';
    }
    return tag;
  }

  /// Extracts the changelog section from the release body markdown.
  static String _extractChangelog(String body) {
    final idx = body.indexOf('### Changelog');
    if (idx >= 0) {
      return body.substring(idx + '### Changelog'.length).trim();
    }
    // Fallback: return lines that look like bullet points.
    final bullets = body
        .split('\n')
        .where(
          (l) => l.trimLeft().startsWith('•') || l.trimLeft().startsWith('- '),
        )
        .join('\n');
    return bullets;
  }
}

// ---------------------------------------------------------------------------
// Download Manager – singleton that survives dialog dismissal
// ---------------------------------------------------------------------------

/// Notification IDs & channel for download progress.
const _downloadNotifId = 42;
const _downloadChannelId = 'download_progress';
const _downloadChannelName = 'Download Progress';

/// Manages a single active download with progress tracking, notification
/// support, and cancellation. Survives dialog open/close.
class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  /// Current download progress (0.0 – 1.0).
  final ValueNotifier<double> progress = ValueNotifier(0);

  /// Non-null while a download is in progress or completed.
  AppUpdate? activeUpdate;

  /// `true` while a download Future is running.
  bool get isDownloading => _downloading;
  bool _downloading = false;

  /// Error message if the last download failed.
  String? error;

  /// Whether download completed successfully (APK installer launched).
  bool completed = false;

  bool _cancelled = false;

  /// Whether a notification is currently showing progress.
  bool _notificationActive = false;

  FlutterLocalNotificationsPlugin? _notifPlugin;

  Future<FlutterLocalNotificationsPlugin> _getNotifPlugin() async {
    if (_notifPlugin != null) return _notifPlugin!;
    _notifPlugin = FlutterLocalNotificationsPlugin();
    await _notifPlugin!.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    return _notifPlugin!;
  }

  /// Start downloading [update]. No-op if already downloading the same update.
  Future<void> start(AppUpdate update) async {
    if (_downloading && activeUpdate?.tagName == update.tagName) return;

    activeUpdate = update;
    _downloading = true;
    _cancelled = false;
    error = null;
    completed = false;
    progress.value = 0;

    try {
      await UpdateService.downloadAndInstall(
        update,
        onProgress: (p) {
          progress.value = p;
          _updateNotificationIfActive(update, p);
        },
        isCancelled: () => _cancelled,
      );
      completed = true;
    } catch (e) {
      if (!_cancelled) {
        error = e.toString();
      }
    } finally {
      _downloading = false;
      if (_notificationActive) {
        if (completed) {
          await _showCompletedNotification(update);
        } else if (_cancelled) {
          await _dismissNotification();
        } else {
          await _showFailedNotification(update);
        }
      }
    }
  }

  /// Cancel the active download. Partial file is kept for resume.
  void cancel() {
    _cancelled = true;
    _dismissNotification();
  }

  /// Reset state so a new download can start.
  void reset() {
    activeUpdate = null;
    error = null;
    completed = false;
    progress.value = 0;
  }

  // -- Notification helpers -------------------------------------------------

  /// Call when the dialog is dismissed while download is active.
  Future<void> showNotification(AppUpdate update) async {
    if (!_downloading) return;
    _notificationActive = true;
    await _updateNotificationIfActive(update, progress.value);
  }

  /// Call when the dialog is re-shown to stop the notification.
  Future<void> hideNotification() async {
    _notificationActive = false;
    await _dismissNotification();
  }

  Future<void> _updateNotificationIfActive(AppUpdate update, double p) async {
    if (!_notificationActive) return;
    if (kIsWeb) return;

    final plugin = await _getNotifPlugin();
    final percent = (p * 100).round();
    final totalMb = (update.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final dlMb = (p * update.sizeBytes / (1024 * 1024)).toStringAsFixed(1);

    await plugin.show(
      _downloadNotifId,
      'Downloading update v${update.version}',
      '$dlMb / $totalMb MB — $percent%',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _downloadChannelId,
          _downloadChannelName,
          channelDescription: 'Shows download progress for app updates',
          importance: Importance.low,
          priority: Priority.low,
          onlyAlertOnce: true,
          ongoing: true,
          autoCancel: false,
          showProgress: true,
          maxProgress: 100,
          progress: percent,
          actions: [
            const AndroidNotificationAction(
              'cancel_download',
              'Cancel',
              showsUserInterface: false,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCompletedNotification(AppUpdate update) async {
    _notificationActive = false;
    if (kIsWeb) return;
    final plugin = await _getNotifPlugin();
    await plugin.show(
      _downloadNotifId,
      'Update ready',
      'v${update.version} downloaded — tap to install',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _downloadChannelId,
          _downloadChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  Future<void> _showFailedNotification(AppUpdate update) async {
    _notificationActive = false;
    if (kIsWeb) return;
    final plugin = await _getNotifPlugin();
    await plugin.show(
      _downloadNotifId,
      'Download failed',
      'v${update.version} — open app to retry',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _downloadChannelId,
          _downloadChannelName,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  Future<void> _dismissNotification() async {
    _notificationActive = false;
    if (kIsWeb) return;
    final plugin = await _getNotifPlugin();
    await plugin.cancel(_downloadNotifId);
  }
}

// ---------------------------------------------------------------------------
// UI helpers
// ---------------------------------------------------------------------------

/// Shows a dialog informing the user about the available update. If they
/// choose to download, a progress dialog follows and the APK installer is
/// launched automatically.
Future<void> showUpdateDialog(BuildContext context, AppUpdate update) async {
  final sizeMb = (update.sizeBytes / (1024 * 1024)).toStringAsFixed(1);
  final existingApk = await UpdateService.getExistingApk(update);
  final alreadyDownloaded = existingApk != null;

  if (!context.mounted) return;

  final shouldProceed = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      bool dontShowAgain = false;
      return StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          icon: const Icon(Icons.system_update, size: 36),
          title: const Text('Update Available'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 420, maxWidth: 340),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(update.releaseName),
                  const SizedBox(height: 8),
                  Text(
                    'Version: ${update.version}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  Text(
                    'Size: $sizeMb MB',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  Text(
                    'Channel: ${UpdateService.channel}',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  if (alreadyDownloaded) ...[
                    const SizedBox(height: 8),
                    Text(
                      'APK already downloaded – ready to install.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                  ],
                  if (update.changelog.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'What\'s New',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    const Divider(),
                    Text(
                      update.changelog,
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        height: 24,
                        width: 24,
                        child: Checkbox(
                          value: dontShowAgain,
                          onChanged: (v) =>
                              setDialogState(() => dontShowAgain = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setDialogState(
                            () => dontShowAgain = !dontShowAgain,
                          ),
                          child: Text(
                            'Don\'t remind me again',
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (dontShowAgain)
                    Padding(
                      padding: const EdgeInsets.only(left: 32, top: 2),
                      child: Text(
                        'You can re-enable this in Settings → Updates.',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.outline,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (dontShowAgain) {
                  UpdateService.setAutoUpdateEnabled(false);
                  BackgroundUpdateManager.cancel();
                }
                Navigator.pop(ctx, false);
              },
              child: const Text('Later'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: Icon(
                alreadyDownloaded ? Icons.install_mobile : Icons.download,
              ),
              label: Text(alreadyDownloaded ? 'Install' : 'Download & Install'),
            ),
          ],
        ),
      );
    },
  );

  if (shouldProceed != true || !context.mounted) return;

  // If already downloaded, install directly without the progress dialog.
  if (alreadyDownloaded) {
    await UpdateService.installApk(existingApk);
    return;
  }

  final dm = DownloadManager.instance;

  // If the same update is already downloading, just re-attach the dialog.
  if (!dm.isDownloading || dm.activeUpdate?.tagName != update.tagName) {
    // Not downloading → start fresh (DownloadManager handles partial resume).
    dm.reset();
  }

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => _DownloadProgressDialog(update: update),
  );
}

// ---------------------------------------------------------------------------
// Download‑progress dialog (private)
// ---------------------------------------------------------------------------

class _DownloadProgressDialog extends StatefulWidget {
  final AppUpdate update;
  const _DownloadProgressDialog({required this.update});

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog>
    with WidgetsBindingObserver {
  final DownloadManager _dm = DownloadManager.instance;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dm.progress.addListener(_onProgress);
    // Stop notification if it was showing (we're back in the dialog).
    _dm.hideNotification();

    if (_dm.isDownloading) {
      // Re-attach to existing download – nothing to start.
    } else if (_dm.completed) {
      // Already done – close immediately.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } else if (_dm.error != null) {
      _error = _dm.error;
    } else {
      _startDownload();
    }
  }

  @override
  void dispose() {
    _dm.progress.removeListener(_onProgress);
    WidgetsBinding.instance.removeObserver(this);

    // If still downloading when dialog is dismissed, show notification.
    if (_dm.isDownloading) {
      _dm.showNotification(widget.update);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  void _onProgress() {
    if (mounted) setState(() {});
  }

  Future<void> _startDownload() async {
    setState(() {
      _error = null;
    });

    await _dm.start(widget.update);

    if (!mounted) return;

    if (_dm.completed) {
      // Close dialog after a moment – installer was launched.
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) Navigator.of(context).pop();
      });
    } else if (_dm.error != null) {
      setState(() => _error = _dm.error);
    } else {
      // Cancelled while dialog open – just close.
      Navigator.of(context).pop();
    }
  }

  void _onCancel() {
    _dm.cancel();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return AlertDialog(
        icon: const Icon(Icons.error_outline, size: 36),
        title: const Text('Download Failed'),
        content: Text(_error!),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
    }

    final p = _dm.progress.value;
    final totalMb = (widget.update.sizeBytes / (1024 * 1024)).toStringAsFixed(
      1,
    );
    final downloadedMb = (p * widget.update.sizeBytes / (1024 * 1024))
        .toStringAsFixed(1);

    return PopScope(
      canPop: true,
      child: AlertDialog(
        title: const Text('Downloading Update'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 400, maxWidth: 340),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: p > 0 ? p : null,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),
                Text('$downloadedMb / $totalMb MB'),
                const SizedBox(height: 4),
                Text(
                  '${(p * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (widget.update.changelog.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'What\'s New',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.update.changelog,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _onCancel,
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: const Text('Cancel'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.minimize, size: 18),
            label: const Text('Background'),
          ),
        ],
      ),
    );
  }
}
