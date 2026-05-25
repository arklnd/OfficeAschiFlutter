import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:open_filex/open_filex.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'background_update.dart';
import '../main.dart' show navigatorKey;
import '../version.dart';

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

  Map<String, dynamic> toJson() => {
        'buildNumber': buildNumber,
        'version': version,
        'tagName': tagName,
        'downloadUrl': downloadUrl,
        'sizeBytes': sizeBytes,
        'releaseName': releaseName,
        'changelog': changelog,
      };

  factory AppUpdate.fromJson(Map<String, dynamic> json) => AppUpdate(
        buildNumber: json['buildNumber'] as int,
        version: json['version'] as String,
        tagName: json['tagName'] as String,
        downloadUrl: json['downloadUrl'] as String,
        sizeBytes: json['sizeBytes'] as int,
        releaseName: json['releaseName'] as String,
        changelog: json['changelog'] as String,
      );
}

// ---------------------------------------------------------------------------
// Service (business logic only)
// ---------------------------------------------------------------------------

class UpdateService {
  static const _owner = 'arklnd';
  static const _repo = 'OfficeAschiFlutter';
  static const _autoUpdateKey = 'autoUpdateCheck';

  static String get channel => kDebugMode ? 'debug' : 'release';

  static Future<bool> isAutoUpdateEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoUpdateKey) ?? true;
  }

  static Future<void> setAutoUpdateEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoUpdateKey, enabled);
  }

  static int? get currentBuildNumber {
    if (appVersion == 'APP_VERSION_PLACEHOLDER') return null;
    return int.tryParse(appVersion.split('.').first);
  }

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

  static String apkFileName(AppUpdate update) {
    return 'office-aschi-flutter-$channel-${update.version}.apk';
  }

  static Future<Directory> _downloadDir() async {
    final dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File?> getExistingApk(AppUpdate update) async {
    final dir = await _downloadDir();
    final file = File('${dir.path}/${apkFileName(update)}');
    if (await file.exists()) {
      final length = await file.length();
      if (update.sizeBytes > 0 && length == update.sizeBytes) return file;
      if (update.sizeBytes <= 0 && length > 0) return file;
      await file.delete();
    }
    return null;
  }

  static Future<void> installApk(File file) async {
    await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
  }

  static Future<void> downloadAndInstall(
    AppUpdate update, {
    ValueChanged<double>? onProgress,
    ValueChanged<List<String>>? onCleaned,
    int maxRetries = 5,
    bool Function()? isCancelled,
  }) async {
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
        int alreadyReceived = 0;
        if (await partFile.exists()) {
          alreadyReceived = await partFile.length();
          if (totalBytes > 0 && alreadyReceived >= totalBytes) {
            await partFile.delete();
            alreadyReceived = 0;
          }
        }

        httpClient = HttpClient();
        final request = await httpClient.getUrl(Uri.parse(update.downloadUrl));

        if (alreadyReceived > 0) {
          request.headers.set('Range', 'bytes=$alreadyReceived-');
        }

        final response = await request.close().timeout(
          const Duration(seconds: 30),
        );

        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception('Download failed: HTTP ${response.statusCode}');
        }

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

        if (totalBytes > 0 && received < totalBytes) {
          throw Exception(
            'Incomplete download ($received / $totalBytes bytes)',
          );
        }

        final partLen = await partFile.length();
        if (totalBytes > 0 && partLen != totalBytes) {
          await partFile.delete();
          throw Exception(
            'File verification failed (disk: $partLen, expected: $totalBytes bytes)',
          );
        }

        await partFile.rename(file.path);
        onProgress?.call(1.0);
        await installApk(file);
        return;
      } catch (e) {
        if (e.toString().contains('Download cancelled')) rethrow;

        attempt++;
        httpClient?.close(force: true);

        if (attempt >= maxRetries) {
          try {
            if (await partFile.exists()) await partFile.delete();
          } catch (_) {}
          rethrow;
        }

        final delay = Duration(seconds: 1 << attempt);
        debugPrint(
          'Download interrupted (attempt $attempt/$maxRetries), '
          'retrying in ${delay.inSeconds}s: $e',
        );
        await Future.delayed(delay);
      }
    }
  }

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

  static String _extractChangelog(String body) {
    final idx = body.indexOf('### Changelog');
    if (idx >= 0) {
      return body.substring(idx + '### Changelog'.length).trim();
    }
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
// Uses Android's system DownloadManager so downloads continue even if the
// app is killed.
// ---------------------------------------------------------------------------

const _downloadNotifId = 42;
const _downloadChannelId = 'download_progress';
const _downloadChannelName = 'Download Progress';

// SharedPreferences keys for persisting active download across app restarts
const _prefDownloadId = 'pending_download_id';
const _prefDownloadUpdate = 'pending_download_update';

// Android DownloadManager status codes
const _statusPending = 1;
const _statusRunning = 2;
const _statusPaused = 4;
const _statusSuccessful = 8;
const _statusFailed = 16;

// Platform channel names
const _methodChannel = MethodChannel('com.officeaschi/download_manager');
const _eventChannel = EventChannel('com.officeaschi/download_events');

class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  final ValueNotifier<double> progress = ValueNotifier(0);

  AppUpdate? activeUpdate;

  bool get isDownloading => _downloading;
  bool _downloading = false;

  String? error;
  bool completed = false;
  bool _cancelled = false;

  DateTime? startTime;

  double _speedBps = 0;
  double _lastProgress = 0;
  DateTime _lastSpeedSample = DateTime.now();

  Timer? _progressTimer;
  int? _nativeDownloadId;
  StreamSubscription? _completionSub;

  String get remainingFormatted {
    if (_speedBps <= 0 || activeUpdate == null) return '';
    final remainingBytes = (1.0 - progress.value) * activeUpdate!.sizeBytes;
    if (remainingBytes <= 0) return '';
    final secondsLeft = (remainingBytes / _speedBps).round();
    if (secondsLeft <= 0) return '';
    if (secondsLeft >= 3600) {
      final h = secondsLeft ~/ 3600;
      final m = (secondsLeft % 3600) ~/ 60;
      return '${h}h ${m}m left';
    }
    if (secondsLeft >= 60) {
      final m = secondsLeft ~/ 60;
      final s = secondsLeft % 60;
      return '${m}m ${s}s left';
    }
    return '${secondsLeft}s left';
  }

  String get speedFormatted {
    if (_speedBps <= 0) return '';
    if (_speedBps >= 1024 * 1024) {
      return '${(_speedBps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(_speedBps / 1024).toStringAsFixed(0)} KB/s';
  }

  // ---- Notification helpers (for completed/failed only) ----

  FlutterLocalNotificationsPlugin? _notifPlugin;
  bool _notifInitialized = false;

  Future<void> initNotifications() async {
    if (_notifInitialized) return;
    if (kIsWeb) return;
    _notifPlugin = FlutterLocalNotificationsPlugin();
    await _notifPlugin!.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher_foreground'),
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    await _notifPlugin!
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _notifInitialized = true;

    // Handle cold-start: if the app was launched by tapping a notification
    // while it was completely dead, the callback above won't fire.
    // We must check getNotificationAppLaunchDetails() instead.
    try {
      final launchDetails =
          await _notifPlugin!.getNotificationAppLaunchDetails();
      if (launchDetails != null &&
          launchDetails.didNotificationLaunchApp &&
          launchDetails.notificationResponse != null) {
        _onNotificationTap(launchDetails.notificationResponse!);
      }
    } catch (e) {
      debugPrint('Error checking notification launch details: $e');
    }
  }

  FlutterLocalNotificationsPlugin _getNotifPluginSync() {
    if (_notifPlugin == null) {
      _notifPlugin = FlutterLocalNotificationsPlugin();
      _notifPlugin!.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher_foreground'),
        ),
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
    }
    return _notifPlugin!;
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == 'download_complete') {
      _installCompletedUpdate();
      return;
    }
    if (response.payload != 'download_progress') return;
    _pendingDialogOpen = true;
    _tryShowPendingDialog();
  }

  /// Whether a notification tap requested opening the download dialog.
  /// Used to defer dialog show until the navigator is ready (cold start).
  bool _pendingDialogOpen = false;

  void _tryShowPendingDialog() {
    if (!_pendingDialogOpen) return;
    final update = activeUpdate;
    if (update == null) return; // wait for checkPendingDownload to set it
    final ctx = navigatorKey.currentState?.overlay?.context;
    if (ctx == null) return; // wait for navigator to be ready
    _pendingDialogOpen = false;
    showDialog(
      context: ctx,
      barrierDismissible: true,
      builder: (_) => DownloadProgressDialog(update: update),
    );
  }

  Future<void> _installCompletedUpdate() async {
    // Try activeUpdate first (app was alive), fall back to persisted state
    // (cold start from notification tap).
    AppUpdate? update = activeUpdate;
    if (update == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final json = prefs.getString(_prefDownloadUpdate);
        if (json != null) {
          update = AppUpdate.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
          );
        }
      } catch (_) {}
    }
    if (update == null) return;

    final apk = await UpdateService.getExistingApk(update);
    if (apk != null) {
      activeUpdate = update;
      completed = true;
      progress.value = 1.0;

      // Clear persisted state
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefDownloadId);
      await prefs.remove(_prefDownloadUpdate);

      await UpdateService.installApk(apk);
    }
  }


  // ---- Core download using Android DownloadManager ----

  Future<void> start(AppUpdate update) async {
    if (_downloading && activeUpdate?.tagName == update.tagName) return;

    activeUpdate = update;
    _downloading = true;
    _cancelled = false;
    error = null;
    completed = false;
    progress.value = 0;
    startTime = DateTime.now();
    _speedBps = 0;
    _lastProgress = 0;
    _lastSpeedSample = DateTime.now();

    try {
      // Check if already downloaded
      final existing = await UpdateService.getExistingApk(update);
      if (existing != null) {
        progress.value = 1.0;
        completed = true;
        _downloading = false;
        await UpdateService.installApk(existing);
        return;
      }

      // Clean old APKs
      final dir = await UpdateService._downloadDir();
      final fileName = UpdateService.apkFileName(update);
      await UpdateService._cleanOldApks(dir, fileName);

      // Delete any leftover .part file from old download mechanism
      final partFile = File('${dir.path}/$fileName.part');
      if (await partFile.exists()) {
        try { await partFile.delete(); } catch (_) {}
      }

      // Delete any partially-downloaded file so DownloadManager starts fresh
      final targetFile = File('${dir.path}/$fileName');
      if (await targetFile.exists()) {
        try { await targetFile.delete(); } catch (_) {}
      }

      // Enqueue download via Android's system DownloadManager
      final downloadId = await _methodChannel.invokeMethod<int>(
        'enqueueDownload',
        {
          'url': update.downloadUrl,
          'fileName': fileName,
          'title': 'Downloading update v${update.version}',
          'description': update.releaseName,
        },
      );

      if (downloadId == null) {
        throw Exception('Failed to enqueue download');
      }

      _nativeDownloadId = downloadId;

      // Persist download state so we can recover after app restart
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefDownloadId, downloadId);
      await prefs.setString(_prefDownloadUpdate, jsonEncode(update.toJson()));

      // Listen for completion events from the native BroadcastReceiver
      _listenForCompletion(downloadId, update);

      // Poll progress periodically while the app is alive
      _startProgressPolling(downloadId, update);
    } catch (e) {
      if (!_cancelled) {
        error = e.toString();
      }
      _downloading = false;
      if (!_cancelled) {
        await _showFailedNotification(update);
      }
    }
  }

  void _listenForCompletion(int downloadId, AppUpdate update) {
    _completionSub?.cancel();
    _completionSub = _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map))
        .listen((event) {
      final eventId = (event['downloadId'] as num?)?.toInt();
      if (eventId != downloadId) return;

      final status = (event['status'] as num?)?.toInt();
      if (status == _statusSuccessful) {
        _onDownloadCompleted(update);
      } else if (status == _statusFailed) {
        _onDownloadFailed(update, 'Download failed');
      }
    });
  }

  void _startProgressPolling(int downloadId, AppUpdate update) {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollProgress(downloadId, update),
    );
  }

  Future<void> _pollProgress(int downloadId, AppUpdate update) async {
    if (_cancelled || completed) {
      _progressTimer?.cancel();
      return;
    }

    try {
      final info = await _methodChannel.invokeMethod<Map>(
        'queryProgress',
        {'downloadId': downloadId},
      );

      if (info == null) return;

      final status = (info['status'] as num?)?.toInt() ?? 0;
      final bytesDownloaded = (info['bytesDownloaded'] as num?)?.toInt() ?? 0;
      final bytesTotal = (info['bytesTotal'] as num?)?.toInt() ?? 0;

      if (bytesTotal > 0) {
        final p = bytesDownloaded / bytesTotal;
        _updateSpeed(p, bytesTotal);
        progress.value = p;
      }

      if (status == _statusSuccessful) {
        _onDownloadCompleted(update);
      } else if (status == _statusFailed) {
        final reason = (info['reason'] as num?)?.toInt() ?? 0;
        _onDownloadFailed(update, 'Download failed (reason: $reason)');
      }
    } catch (e) {
      debugPrint('Error polling download progress: $e');
    }
  }

  Future<void> _onDownloadCompleted(AppUpdate update) async {
    _progressTimer?.cancel();
    _completionSub?.cancel();
    progress.value = 1.0;
    completed = true;
    _downloading = false;
    _nativeDownloadId = null;

    // Clear persisted state
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefDownloadId);
    await prefs.remove(_prefDownloadUpdate);

    await _showCompletedNotification(update);

    // Auto-install
    final apk = await UpdateService.getExistingApk(update);
    if (apk != null) {
      await UpdateService.installApk(apk);
    }
  }

  Future<void> _onDownloadFailed(AppUpdate update, String reason) async {
    _progressTimer?.cancel();
    _completionSub?.cancel();
    _downloading = false;
    _nativeDownloadId = null;
    error = reason;

    // Clear persisted state
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefDownloadId);
    await prefs.remove(_prefDownloadUpdate);

    await _showFailedNotification(update);
  }

  void cancel() {
    _cancelled = true;
    _progressTimer?.cancel();
    _completionSub?.cancel();

    final downloadId = _nativeDownloadId;
    if (downloadId != null) {
      _methodChannel.invokeMethod('cancelDownload', {'downloadId': downloadId});
      _nativeDownloadId = null;
    }

    // Clear persisted state
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(_prefDownloadId);
      prefs.remove(_prefDownloadUpdate);
    });
  }

  void reset() {
    activeUpdate = null;
    error = null;
    completed = false;
    progress.value = 0;
    startTime = null;
    _speedBps = 0;
  }

  /// Called on app startup to check if a download was in progress before the
  /// app was killed. If the system DownloadManager finished the download,
  /// this triggers installation. If still in progress, it re-attaches
  /// progress polling.
  Future<void> checkPendingDownload() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final downloadId = prefs.getInt(_prefDownloadId);
      final updateJson = prefs.getString(_prefDownloadUpdate);

      if (downloadId == null || updateJson == null) return;

      final update = AppUpdate.fromJson(
        jsonDecode(updateJson) as Map<String, dynamic>,
      );

      // Check if the APK is already fully downloaded (DownloadManager finished
      // while the app was dead).
      final existingApk = await UpdateService.getExistingApk(update);
      if (existingApk != null) {
        // Download completed while app was closed
        activeUpdate = update;
        completed = true;
        progress.value = 1.0;

        await prefs.remove(_prefDownloadId);
        await prefs.remove(_prefDownloadUpdate);

        await _showCompletedNotification(update);
        await UpdateService.installApk(existingApk);
        return;
      }

      // Query the DownloadManager for current status
      final info = await _methodChannel.invokeMethod<Map>(
        'queryProgress',
        {'downloadId': downloadId},
      );

      if (info == null) {
        // Download entry no longer exists — clean up
        await prefs.remove(_prefDownloadId);
        await prefs.remove(_prefDownloadUpdate);
        return;
      }

      final status = (info['status'] as num?)?.toInt() ?? 0;

      if (status == _statusSuccessful) {
        activeUpdate = update;
        completed = true;
        progress.value = 1.0;
        _downloading = false;

        await prefs.remove(_prefDownloadId);
        await prefs.remove(_prefDownloadUpdate);

        await _showCompletedNotification(update);

        final apk = await UpdateService.getExistingApk(update);
        if (apk != null) {
          await UpdateService.installApk(apk);
        }
      } else if (status == _statusFailed) {
        activeUpdate = update;
        error = 'Download failed while app was closed';
        _downloading = false;

        await prefs.remove(_prefDownloadId);
        await prefs.remove(_prefDownloadUpdate);

        await _showFailedNotification(update);
      } else if (status == _statusRunning ||
                 status == _statusPending ||
                 status == _statusPaused) {
        // Download still in progress — re-attach
        activeUpdate = update;
        _downloading = true;
        _cancelled = false;
        error = null;
        completed = false;
        _nativeDownloadId = downloadId;
        startTime = DateTime.now();
        _speedBps = 0;
        _lastProgress = 0;
        _lastSpeedSample = DateTime.now();

        final bytesDownloaded =
            (info['bytesDownloaded'] as num?)?.toInt() ?? 0;
        final bytesTotal = (info['bytesTotal'] as num?)?.toInt() ?? 0;
        if (bytesTotal > 0) {
          progress.value = bytesDownloaded / bytesTotal;
          _lastProgress = progress.value;
        }

        _listenForCompletion(downloadId, update);
        _startProgressPolling(downloadId, update);

        // Show the download progress dialog once the UI is ready.
        // On cold start this runs before runApp(), so defer until the
        // first frame is drawn.
        _pendingDialogOpen = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _tryShowPendingDialog();
        });
      }
    } catch (e) {
      debugPrint('Error checking pending download: $e');
    }
  }

  void _updateSpeed(double p, int totalBytes) {
    final now = DateTime.now();
    final dt = now.difference(_lastSpeedSample).inMilliseconds;
    if (dt > 500) {
      final bytesInInterval = (p - _lastProgress) * totalBytes;
      final instantSpeed = bytesInInterval / (dt / 1000);
      _speedBps = _speedBps == 0
          ? instantSpeed
          : _speedBps * 0.7 + instantSpeed * 0.3;
      _lastProgress = p;
      _lastSpeedSample = now;
    }
  }

  // ---- Notification helpers ----

  Future<void> _showCompletedNotification(AppUpdate update) async {
    if (kIsWeb) return;
    await initNotifications();
    final plugin = _getNotifPluginSync();
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
          largeIcon: DrawableResourceAndroidBitmap('ic_notification_large'),
          color: Color(0xFF673AB7), // deepPurple
        ),
      ),
      payload: 'download_complete',
    );
  }

  Future<void> _showFailedNotification(AppUpdate update) async {
    if (kIsWeb) return;
    await initNotifications();
    final plugin = _getNotifPluginSync();
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
          largeIcon: DrawableResourceAndroidBitmap('ic_notification_large'),
          color: Color(0xFF673AB7), // deepPurple
        ),
      ),
      payload: 'download_progress',
    );
  }
}

// ---------------------------------------------------------------------------
// UI helpers
// ---------------------------------------------------------------------------

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
                      'APK already downloaded — ready to install.',
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
                        'You can re-enable this in Settings -> Updates.',
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

  if (alreadyDownloaded) {
    await UpdateService.installApk(existingApk);
    return;
  }

  final dm = DownloadManager.instance;

  if (!dm.isDownloading || dm.activeUpdate?.tagName != update.tagName) {
    dm.reset();
  }

  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => DownloadProgressDialog(update: update),
  );
}

// ---------------------------------------------------------------------------
// Download progress dialog
// ---------------------------------------------------------------------------

class DownloadProgressDialog extends StatefulWidget {
  final AppUpdate update;
  const DownloadProgressDialog({super.key, required this.update});

  @override
  State<DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<DownloadProgressDialog>
    with WidgetsBindingObserver {
  final DownloadManager _dm = DownloadManager.instance;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dm.progress.addListener(_onProgress);

    if (_dm.isDownloading) {
      // Re-attach to existing download
    } else if (_dm.completed) {
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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  void _onProgress() {
    if (!mounted) return;
    setState(() {});

    // Check if download completed or failed while dialog is showing
    if (_dm.completed) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) Navigator.of(context).pop();
      });
    } else if (_dm.error != null && _error == null) {
      setState(() => _error = _dm.error);
    }
  }

  Future<void> _startDownload() async {
    setState(() {
      _error = null;
    });

    await _dm.start(widget.update);

    if (!mounted) return;

    if (_dm.completed) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) Navigator.of(context).pop();
      });
    } else if (_dm.error != null) {
      setState(() => _error = _dm.error);
    }
    // If downloading is in progress, the dialog stays open and
    // _onProgress will handle UI updates via the progress listener.
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
        title: Text('Downloading Update v${widget.update.version}'),
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
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_dm.remainingFormatted.isNotEmpty)
                      Text(
                        _dm.remainingFormatted,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    if (_dm.remainingFormatted.isNotEmpty &&
                        _dm.speedFormatted.isNotEmpty)
                      Text(
                        ' · ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    if (_dm.speedFormatted.isNotEmpty)
                      Text(
                        _dm.speedFormatted,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                  ],
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
