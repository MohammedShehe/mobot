import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/settings_store.dart';

/// Smart home via Home Assistant's Conversation API
/// (POST {url}/api/conversation/process with a long-lived access token).
class SmartHomeService {
  static final _cmd = RegExp(
    r'\b(turn (on|off)|switch (on|off)|toggle|dim|brighten|lights?|lamp|fan|thermostat|heater|air ?con|lock|unlock|garage|curtains?|blinds|socket|plug|set .+ to)\b',
    caseSensitive: false,
  );

  static bool looksLikeCommand(String q) => _cmd.hasMatch(q);

  /// Returns a context line for the model describing what happened.
  static Future<String> run(SettingsStore s, String text) async {
    final base = s.haUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty || s.haToken.trim().isEmpty) {
      return 'Smart home: Home Assistant URL/token not set; tell the user to add them in Settings → Integrations.';
    }
    try {
      final r = await http
          .post(
            Uri.parse('$base/api/conversation/process'),
            headers: {'Authorization': 'Bearer ${s.haToken.trim()}', 'Content-Type': 'application/json'},
            body: jsonEncode({'text': text, 'language': s.locale.split('-').first}),
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 401) return 'Smart home: Home Assistant rejected the token (401).';
      if (r.statusCode != 200) return 'Smart home: Home Assistant error ${r.statusCode}.';
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      final speech = j['response']?['speech']?['plain']?['speech'];
      final type = j['response']?['response_type'];
      if (type == 'error') return 'Smart home: command failed: ${speech ?? 'unknown error'}.';
      return 'Smart home: command sent to Home Assistant. It replied: "${speech ?? 'done'}". Confirm briefly.';
    } catch (_) {
      return 'Smart home: could not reach Home Assistant. Check the URL and network.';
    }
  }
}
