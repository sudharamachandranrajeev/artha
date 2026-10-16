import 'dart:io';

import 'package:flutter/services.dart';

/// What the platform tells Artha beyond Flutter: links it was opened with
/// and the device's name.
///
/// On Android, scanning a pairing QR code with the camera app opens Artha
/// with the `artha://` link (see MainActivity.kt). Desktops have no camera
/// flow; there the link is pasted.
class PlatformLinks {
  static const _channel = MethodChannel('dev.artha.artha/links');

  /// The link Artha was started with, once; null when there was none.
  static Future<String?> initial() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('takeLink');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// Calls [onLink] for each link that arrives while Artha is running.
  static void listen(void Function(String link) onLink) {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'link' && call.arguments is String) onLink(call.arguments as String);
    });
  }

  /// A name the user recognises, such as "Pixel 8" or the computer's host
  /// name. Shown to the other device when pairing.
  static Future<String> deviceName() async {
    if (Platform.isAndroid) {
      try {
        return await _channel.invokeMethod<String>('deviceName') ?? 'Android';
      } on Object {
        return 'Android';
      }
    }
    try {
      return Platform.localHostname;
    } on Object {
      return Platform.operatingSystem;
    }
  }
}
