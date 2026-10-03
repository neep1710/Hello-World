package com.yourinstitute.secure_edu

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // FLAG_SECURE must be set before the first frame is drawn. It makes the
        // OS render this window as black in screenshots, screen recordings,
        // the Recents/Overview thumbnail, and on non-secure external displays
        // (casting/mirroring). Applied app-wide so no screen can leak content.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
        super.onCreate(savedInstanceState)
    }
}
