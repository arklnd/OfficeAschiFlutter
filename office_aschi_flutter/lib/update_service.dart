import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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

  /// Downloads the APK to temp storage, then launches the system installer.
  static Future<void> downloadAndInstall(
    AppUpdate update, {
    ValueChanged<double>? onProgress,
  }) async {
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
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/office-aschi-update.apk');
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

      await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
    } finally {
      httpClient.close();
    }
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

  final shouldDownload = await showDialog<bool>(
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
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Later'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.download),
          label: const Text('Download & Install'),
        ),
      ],
    ),
  );

  if (shouldDownload == true && context.mounted) {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadProgressDialog(update: update),
    );
  }
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
