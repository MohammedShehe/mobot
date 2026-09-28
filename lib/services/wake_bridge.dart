import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Bridge to the Android side (android/.../MainActivity.kt):
///  - the always-on wake-word service (works while MO is closed / phone locked)
///  - installed text-to-speech voices with a measured male/female label
/// On other platforms every call is a harmless no-op.
class WakeBridge {
  static const _ch = MethodChannel('mo/native');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<bool> start(String wake, String locale) async {
    if (!supported) return false;
    try {
      return await _ch.invokeMethod<bool>('startWake', {'wake': wake, 'locale': locale}) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async {
    if (!supported) return;
    try {
      await _ch.invokeMethod<bool>('stopWake');
    } catch (_) {}
  }

  /// What the background service heard after the wake word ('' = only the wake
  /// word), or null when the app was not opened by the wake word.
  static Future<String?> consume() async {
    if (!supported) return null;
    try {
      final m = await _ch.invokeMethod<Map>('consumeWake');
      if (m == null) return null;
      return '${m['text'] ?? ''}';
    } catch (_) {
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>> voices() async {
    if (!supported) return const [];
    try {
      final r = await _ch.invokeMethod<List>('getVoices');
      return (r ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return const [];
    }
  }

  /// voice name -> 'male' | 'female' | '' (unknown)
  static Future<Map<String, String>> classify(List<String> names) async {
    if (!supported || names.isEmpty) return {};
    try {
      final r = await _ch.invokeMethod<Map>('classifyVoices', {'names': names});
      if (r == null) return {};
      return r.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }
}
