import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../core/settings_store.dart';

class VoiceService {
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  bool _ready = false;

  bool get listening => _stt.isListening;

  Future<bool> listen({
    required String locale,
    required void Function(String text, bool isFinal) onResult,
    required void Function() onDone,
  }) async {
    if (!await Permission.microphone.request().isGranted) return false;
    if (!_ready) {
      _ready = await _stt.initialize(
        onStatus: (st) {
          if (st == 'done' || st == 'notListening') onDone();
        },
        onError: (_) => onDone(),
      );
    }
    if (!_ready) return false;
    await _tts.stop();
    await _stt.listen(
      localeId: locale.replaceAll('-', '_'),
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
    );
    return true;
  }

  Future<void> stopListening() => _stt.stop();

  Future<void> speak(String text, SettingsStore s) async {
    try {
      await _tts.setLanguage(s.locale);
      // Pitch/rate are the portable way to shape male vs female + tone.
      await _tts.setPitch(s.voiceGender == 'female' ? 1.15 : 0.8);
      await _tts.setSpeechRate(s.tone == 'formal' ? 0.45 : 0.5);
      final voices = await _tts.getVoices;
      if (voices is List) {
        final want = s.voiceGender;
        final match = voices.cast<Map>().where((v) {
          final n = '${v['name']}'.toLowerCase();
          return '${v['locale']}'.toLowerCase().replaceAll('_', '-') == s.locale.toLowerCase() && n.contains(want);
        });
        if (match.isNotEmpty) {
          await _tts.setVoice({'name': '${match.first['name']}', 'locale': '${match.first['locale']}'});
        }
      }
      await _tts.speak(text.replaceAll(RegExp(r'[*_#`]'), ''));
    } catch (_) {}
  }

  Future<void> stopSpeaking() => _tts.stop();
}
