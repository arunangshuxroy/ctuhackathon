// MainActivity.kt
//
// Flutter's Android host activity. Kept minimal — all business logic lives
// in Dart. The UpiOverlayService is started from Dart via MethodChannel
// when a payment screen is detected.

package com.vigilupi.app

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
