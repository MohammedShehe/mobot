import 'package:flutter/foundation.dart';
import '../core/settings_store.dart';
import 'context_service.dart';
import 'groq_service.dart';
import 'voice_service.dart';

/// Holds ONLY the current conversation, in memory. Closing the app wipes it.
class ChatController extends ChangeNotifier {
  ChatController(this.settings);
  final SettingsStore settings;
  final voice = VoiceService();

  final List<Turn> messages = []; // roles: user | assistant | error
  bool thinking = false;
  bool listening = false;
  String partial = '';

  String _stripWake(String raw) {
    final w = settings.wakeWord.trim().toLowerCase();
    var t = raw.trim();
    if (w.isNotEmpty && t.toLowerCase().startsWith(w)) {
      t = t.substring(w.length).replaceFirst(RegExp(r'^[\s,.!:;-]+'), '');
    }
    return t;
  }

  String _system(String ctx) {
    final s = settings;
    return '''You are MO, a warm, sharp human-robot assistant living in a mobile app.
Always address the user as "Little" (e.g. "Sure thing, Little").
Tone: ${s.tone == 'formal' ? 'formal, polite and precise' : 'friendly, casual and encouraging'}.
Length: ${s.length == 'short' ? 'short, 1 to 3 sentences unless asked for more' : 'detailed and thorough, but well organised'}.
Reply in ${s.language}.
Your answers may be read aloud, so use plain text: no markdown, no emojis, no lists with symbols.
Use the live device context below when relevant. Never invent weather, news, sports or calendar facts that are not in it; if data is missing, say what is needed.
Live device context:
$ctx''';
  }

  Future<void> send(String raw) async {
    final text = _stripWake(raw);
    if (text.isEmpty || thinking || !settings.enabled) return;
    messages.add(Turn('user', text));
    thinking = true;
    notifyListeners();
    try {
      final ctx = await ContextService.build(settings, text);
      final convo = messages.where((m) => m.role != 'error').toList();
      final turns = settings.noHistory
          ? [convo.last]
          : convo.length > 12 ? convo.sublist(convo.length - 12) : convo;
      final reply = await GroqService.ask(apiKey: settings.groqKey, system: _system(ctx), turns: turns);
      messages.add(Turn('assistant', reply));
      voice.speak(reply, settings);
    } catch (e) {
      messages.add(Turn('error', e.toString().replaceFirst('Exception: ', '')));
    }
    thinking = false;
    notifyListeners();
  }

  Future<bool> toggleMic() async {
    if (listening) {
      await voice.stopListening();
      return true;
    }
    partial = '';
    final ok = await voice.listen(
      locale: settings.locale,
      onResult: (t, isFinal) {
        partial = t;
        notifyListeners();
        if (isFinal && t.trim().isNotEmpty) {
          final q = t;
          partial = '';
          send(q);
        }
      },
      onDone: () {
        listening = false;
        notifyListeners();
      },
    );
    listening = ok;
    notifyListeners();
    return ok;
  }

  void clear() {
    messages.clear();
    notifyListeners();
  }
}
