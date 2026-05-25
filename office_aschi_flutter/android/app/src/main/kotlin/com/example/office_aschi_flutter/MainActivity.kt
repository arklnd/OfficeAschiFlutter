package com.example.office_aschi_flutter

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.Environment
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val METHOD_CHANNEL = "com.officeaschi/download_manager"
        private const val EVENT_CHANNEL = "com.officeaschi/download_events"
    }

    private var downloadManager: DownloadManager? = null
    private var eventSink: EventChannel.EventSink? = null
    private var downloadReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        downloadManager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "enqueueDownload" -> {
                    try {
                        val url = call.argument<String>("url")!!
                        val fileName = call.argument<String>("fileName")!!
                        val title = call.argument<String>("title") ?: "Downloading update"
                        val description = call.argument<String>("description") ?: ""

                        // Remove existing file if present so DownloadManager doesn't
                        // append a numeric suffix.
                        try {
                            val dir = Environment.getExternalStoragePublicDirectory(
                                Environment.DIRECTORY_DOWNLOADS
                            )
                            val existing = java.io.File(dir, fileName)
                            if (existing.exists()) existing.delete()
                        } catch (_: Exception) {}

                        val request = DownloadManager.Request(Uri.parse(url))
                            .setTitle(title)
                            .setDescription(description)
                            .setNotificationVisibility(
                                DownloadManager.Request.VISIBILITY_VISIBLE
                            )
                            .setDestinationInExternalPublicDir(
                                Environment.DIRECTORY_DOWNLOADS, fileName
                            )
                            .setAllowedOverMetered(true)
                            .setAllowedOverRoaming(true)
                            .setMimeType("application/vnd.android.package-archive")

                        val downloadId = downloadManager!!.enqueue(request)
                        result.success(downloadId)
                    } catch (e: Exception) {
                        result.error("ENQUEUE_FAILED", e.message, null)
                    }
                }

                "queryProgress" -> {
                    try {
                        val downloadId = (call.argument<Number>("downloadId"))?.toLong()
                        if (downloadId == null) {
                            result.error("INVALID_ID", "Download ID is required", null)
                            return@setMethodCallHandler
                        }

                        val query = DownloadManager.Query().setFilterById(downloadId)
                        val cursor = downloadManager!!.query(query)

                        if (cursor != null && cursor.moveToFirst()) {
                            val status = cursor.getInt(
                                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                            )
                            val bytesDownloaded = cursor.getLong(
                                cursor.getColumnIndexOrThrow(
                                    DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR
                                )
                            )
                            val bytesTotal = cursor.getLong(
                                cursor.getColumnIndexOrThrow(
                                    DownloadManager.COLUMN_TOTAL_SIZE_BYTES
                                )
                            )
                            val reason = cursor.getInt(
                                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON)
                            )
                            val localUri = cursor.getString(
                                cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)
                            )
                            cursor.close()

                            result.success(
                                mapOf(
                                    "status" to status,
                                    "bytesDownloaded" to bytesDownloaded,
                                    "bytesTotal" to bytesTotal,
                                    "reason" to reason,
                                    "localUri" to (localUri ?: "")
                                )
                            )
                        } else {
                            cursor?.close()
                            result.success(null)
                        }
                    } catch (e: Exception) {
                        result.error("QUERY_FAILED", e.message, null)
                    }
                }

                "cancelDownload" -> {
                    try {
                        val downloadId = (call.argument<Number>("downloadId"))?.toLong()
                        if (downloadId != null) {
                            downloadManager!!.remove(downloadId)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("CANCEL_FAILED", e.message, null)
                    }
                }

                else -> result.notImplemented()
            }
        }

        // Event channel for download completion broadcasts
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    registerDownloadReceiver()
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    unregisterDownloadReceiver()
                }
            }
        )
    }

    private fun registerDownloadReceiver() {
        if (downloadReceiver != null) return
        downloadReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                val downloadId =
                    intent?.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1) ?: return
                if (downloadId == -1L) return

                val query = DownloadManager.Query().setFilterById(downloadId)
                val cursor = downloadManager?.query(query)

                if (cursor != null && cursor.moveToFirst()) {
                    val status = cursor.getInt(
                        cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS)
                    )
                    val localUri = cursor.getString(
                        cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_LOCAL_URI)
                    )
                    cursor.close()

                    eventSink?.success(
                        mapOf(
                            "downloadId" to downloadId,
                            "status" to status,
                            "localUri" to (localUri ?: "")
                        )
                    )
                } else {
                    cursor?.close()
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                downloadReceiver,
                IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE),
                Context.RECEIVER_EXPORTED
            )
        } else {
            registerReceiver(
                downloadReceiver,
                IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
            )
        }
    }

    private fun unregisterDownloadReceiver() {
        downloadReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        downloadReceiver = null
    }

    override fun onDestroy() {
        unregisterDownloadReceiver()
        super.onDestroy()
    }
}
