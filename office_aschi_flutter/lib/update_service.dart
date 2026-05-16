import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

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

  const AppUpdate({
    required this.buildNumber,
    required this.version,
    required this.tagName,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.releaseName,
  });
}

// ---------------------------------------------------------------------------
// Service
// ---------------------------------------------------------------------------

class UpdateService {
  static const _owner = 'arklnd';
  static const _repo = 'OfficeAschiFlutter';

  /// 'debug' when running a debug build, 'release' otherwise.
  static String get channel => kDebugMode ? 'debug' : 'release';

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
  static Future<void> downloadAndInstall(
    AppUpdate update, {
    ValueChanged<double>? onProgress,
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

    // Remove stale update APKs from previous versions.
    await _cleanOldApks(dir, fileName);

    final httpClient = HttpClient();
    try {
      final request = await httpClient.getUrl(Uri.parse(update.downloadUrl));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

      final totalBytes = response.contentLength > 0
          ? response.contentLength
          : update.sizeBytes;
      final sink = file.openWrite();
      int received = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes > 0) {
          onProgress?.call(received / totalBytes);
        }
      }
      await sink.close();

      await installApk(file);
    } finally {
      httpClient.close();
    }
  }

  /// Removes old Office Aschi APKs from [dir], keeping only [currentName].
  static Future<void> _cleanOldApks(Directory dir, String currentName) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is File &&
            entity.uri.pathSegments.last.startsWith('office-aschi-flutter-') &&
            entity.path.endsWith('.apk') &&
            !entity.path.endsWith(currentName)) {
          await entity.delete();
        }
      }
    } catch (_) {}
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
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.system_update, size: 36),
      title: const Text('Update Available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(update.releaseName),
          const SizedBox(height: 8),
          Text(
            'Version: ${update.version}',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
          Text('Size: $sizeMb MB', style: Theme.of(ctx).textTheme.bodySmall),
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Later'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: Icon(alreadyDownloaded ? Icons.install_mobile : Icons.download),
          label: Text(alreadyDownloaded ? 'Install' : 'Download & Install'),
        ),
      ],
    ),
  );

  if (shouldProceed != true || !context.mounted) return;

  // If already downloaded, install directly without the progress dialog.
  if (alreadyDownloaded) {
    await UpdateService.installApk(existingApk);
    return;
  }

  await showDialog(
    context: context,
    barrierDismissible: false,
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

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    try {
      await UpdateService.downloadAndInstall(
        widget.update,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // Install intent was launched – close the dialog.
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
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
        ],
      );
    }

    final totalMb = (widget.update.sizeBytes / (1024 * 1024)).toStringAsFixed(
      1,
    );
    final downloadedMb = (_progress * widget.update.sizeBytes / (1024 * 1024))
        .toStringAsFixed(1);

    return AlertDialog(
      title: const Text('Downloading Update'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: _progress > 0 ? _progress : null,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text('$downloadedMb / $totalMb MB'),
          const SizedBox(height: 4),
          Text(
            '${(_progress * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
