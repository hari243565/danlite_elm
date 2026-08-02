package com.danlite.elm

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val existing = flutterEngine.plugins.get(BluetoothSppPlugin::class.java)
        if (existing == null) {
            flutterEngine.plugins.add(BluetoothSppPlugin())
        }
    }
}