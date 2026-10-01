package com.danlite.elm

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val existing = flutterEngine.plugins.get(BluetoothSppPlugin::class.java)
        if (existing == null) {
            flutterEngine.plugins.add(BluetoothSppPlugin())
        }

        // Tester-mode session recorder (lib/services/session_recorder.dart).
        // "directory" is inside noBackupFilesDir, which Android Auto Backup
        // never copies off the phone. "shareText" only opens the share sheet;
        // it runs solely when the rider taps Share.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.danlite.elm/session_recorder").setMethodCallHandler { call, result ->
            when (call.method) {
                "directory" -> {
                    val dir = File(noBackupFilesDir, "session_recordings")
                    dir.mkdirs()
                    result.success(dir.absolutePath)
                }
                "shareText" -> {
                    val text = call.argument<String>("text") ?: ""
                    val subject = call.argument<String>("subject") ?: "Danlite"
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_SUBJECT, subject)
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    startActivity(Intent.createChooser(send, subject))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
