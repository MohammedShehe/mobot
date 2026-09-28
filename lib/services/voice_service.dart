import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../core/settings_store.dart';
import '../core/text_fix.dart';
import 'wake_bridge.dart';

class VoiceInfo {
  const VoiceInfo(this.name, this.locale, this.gender, {this.quality = 0, this.network = false});
  final String name, locale;
  final String? gender; // female | male | null (unknown)
  final int quality; // Android: 300 normal, 400 high, 500 very high
  final bool network; // needs internet
  VoiceInfo withGender(String? g) => VoiceInfo(name, locale, g, quality: quality, network: network);
}

class VoiceService {
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  final speaking = ValueNotifier<bool>(false);
  bool _ready = false;
  bool _ttsInit = false;
  int _token = 0; // bumped by stopSpeaking() so a running speak() aborts
  List<VoiceInfo>? _voices;
  final Set<String> _measured = {}; // voices whose gender came from the device / a pitch measurement
  final Set<String> _tried = {}; // voices already sent for measurement this session
  Future<void>? _classifying;
  VoiceInfo? _override; // used by the "test voice" button
  void Function()? _onDone; // updated on every listen() so status callbacks reach the current caller

  bool get listening => _stt.isListening;

  // ---- gender detection --------------------------------------------------

  static const _femaleNames = {
    'samantha', 'karen', 'moira', 'tessa', 'fiona', 'victoria', 'kate', 'serena', 'susan', 'allison', 'ava', 'zoe',
    'amelie', 'amélie', 'marie', 'audrey', 'aurelie', 'paulina', 'monica', 'mónica', 'marisol', 'lekha', 'veena',
    'ioana', 'joana', 'luciana', 'sara', 'sandy', 'shelley', 'flo', 'grandma', 'nicky', 'catherine', 'zira', 'hazel',
    'heera', 'kalpana', 'neerja', 'jenny', 'aria', 'sonia', 'libby', 'natasha', 'clara', 'salma',
  };
  static const _maleNames = {
    'daniel', 'alex', 'fred', 'oliver', 'thomas', 'diego', 'jorge', 'juan', 'rishi', 'aaron', 'arthur', 'gordon',
    'reed', 'rocko', 'eddy', 'grandpa', 'ralph', 'albert', 'bruce', 'lee', 'nathan', 'david', 'mark', 'james',
    'ravi', 'hemant', 'prabhat', 'guy', 'ryan', 'antoine', 'mateo',
  };

  static String? genderOf(String name) {
    final n = name.toLowerCase();
    if (n.contains('female') || n.contains('woman')) return 'female';
    if (n.contains('male') || RegExp(r'\bman\b').hasMatch(n)) return 'male';
    final tokens = n.split(RegExp(r'[^a-zà-ÿ]+')).where((t) => t.isNotEmpty);
    for (final t in tokens) {
      if (_femaleNames.contains(t)) return 'female';
      if (_maleNames.contains(t)) return 'male';
    }
    return null;
  }

  static String _norm(String l) => l.toLowerCase().replaceAll('_', '-');

  Future<List<VoiceInfo>> _allVoices() async {
    if (_voices != null) return _voices!;
    final out = <VoiceInfo>[];
    if (WakeBridge.supported) {
      // Native list: installed voices only (not-downloaded ones silently
      // fall back to the default voice, which made every voice sound the same).
      for (final m in await WakeBridge.voices()) {
        final name = '${m['name']}';
        final g = '${m['gender'] ?? ''}';
        if (g.isNotEmpty) _measured.add(name);
        out.add(VoiceInfo(name, '${m['locale']}', g.isEmpty ? genderOf(name) : g,
            quality: (m['quality'] as num?)?.toInt() ?? 0, network: m['network'] == true));
      }
    }
    if (out.isEmpty) {
      try {
        final raw = await _tts.getVoices;
        if (raw is List) {
          for (final v in raw) {
            if (v is! Map) continue;
            final name = '${v['name']}';
            out.add(VoiceInfo(name, '${v['locale']}', genderOf(name)));
          }
        }
      } catch (_) {}
    }
    return _voices = out;
  }

  /// Measures male/female for the voices of [locale] (Android only, cached on
  /// the device, so it is only slow the first time).
  Future<void> warmUp(String locale) {
    final running = _classifying;
    if (running != null) return running;
    final f = _classify(locale).catchError((_) {}).whenComplete(() => _classifying = null);
    _classifying = f;
    return f;
  }

  Future<void> _classify(String locale) async {
    if (!WakeBridge.supported) return;
    final pool = await voicesFor(locale);
    final todo = pool.where((v) => !_measured.contains(v.name) && !_tried.contains(v.name)).map((v) => v.name).take(16).toList();
    if (todo.isEmpty) return;
    final res = await WakeBridge.classify(todo);
    _tried.addAll(todo);
    if (_voices == null) return;
    _voices = [
      for (final v in _voices!)
        if ((res[v.name] ?? '').isNotEmpty) v.withGender(res[v.name]) else v,
    ];
    for (final e in res.entries) {
      if (e.value.isNotEmpty) _measured.add(e.key);
    }
  }

  /// Voices installed for [locale] (falls back to the same language).
  Future<List<VoiceInfo>> voicesFor(String locale) async {
    final all = await _allVoices();
    final l = _norm(locale);
    final exact = all.where((v) => _norm(v.locale) == l).toList();
    if (exact.isNotEmpty) return exact;
    final lang = l.split('-').first;
    return all.where((v) => _norm(v.locale).split('-').first == lang).toList();
  }

  Future<VoiceInfo?> _pickVoice(String locale, SettingsStore s) async {
    await _classifying?.timeout(const Duration(seconds: 10), onTimeout: () {});
    final pool = await voicesFor(locale);
    if (pool.isEmpty) return null;
    if (_override != null && pool.any((v) => v.name == _override!.name)) return _override;
    final chosen = s.voices[locale];
    if (chosen != null) {
      final m = pool.where((v) => v.name == chosen);
      if (m.isNotEmpty) return m.first;
    }
    final byGender = pool.where((v) => v.gender == s.voiceGender).toList();
    if (byGender.isEmpty) return null;
    // Best quality first, offline voices before ones that need internet.
    byGender.sort((a, b) {
      final q = b.quality.compareTo(a.quality);
      if (q != 0) return q;
      return a.network == b.network ? 0 : (a.network ? 1 : -1);
    });
    return byGender.first;
  }

  // ---- speaking ----------------------------------------------------------

  void _initTts() {
    if (_ttsInit) return;
    _ttsInit = true;
    _tts.awaitSpeakCompletion(true);
  }

  Future<void> _prepare(String locale, SettingsStore s) async {
    var loc = locale;
    try {
      final ok = await _tts.isLanguageAvailable(loc);
      if (!(ok == true || ok == 1) && !loc.toLowerCase().startsWith('en')) loc = 'en-US';
    } catch (_) {}
    await _tts.setLanguage(loc);
    final v = await _pickVoice(loc, s);
    if (v != null) {
      await _tts.setVoice({'name': v.name, 'locale': v.locale});
      // A gender-matched (or hand-picked) voice needs no pitch trick.
      await _tts.setPitch(1.0);
    } else {
      // No voice with a known gender on this device: shape it with pitch.
      await _tts.setPitch(s.voiceGender == 'female' ? 1.25 : 0.72);
    }
    await _tts.setSpeechRate(s.tone == 'formal' ? 0.45 : 0.5);
  }

  /// Speaks [text]. In non-English replies the words "Little" and "MO" are
  /// spoken with an English voice ("Little", "more").
  Future<void> speak(String text, SettingsStore s) async {
    _initTts();
    final token = ++_token;
    speaking.value = true;
    try {
      await _tts.stop();
      final isEnglish = s.locale.toLowerCase().startsWith('en');
      final segs = isEnglish ? [(TextFix.spoken(text), false)] : TextFix.segments(text);
      for (final seg in segs) {
        if (token != _token) return;
        await _prepare(seg.$2 ? 'en-US' : s.locale, s);
        if (token != _token) return;
        await _tts
            .speak(seg.$1)
            .timeout(Duration(seconds: 20 + seg.$1.length ~/ 6), onTimeout: () => null);
      }
    } catch (_) {
      // ignore: the reply is still visible as text
    } finally {
      if (token == _token) speaking.value = false;
    }
  }

  /// Plays a sample with one specific voice.
  Future<void> preview(VoiceInfo v, SettingsStore s) async {
    _override = v;
    try {
      await speak('Hi Little, I am MO. This is how I sound.', s);
    } finally {
      _override = null;
    }
  }

  Future<void> stopSpeaking() async {
    _token++;
    speaking.value = false;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  // ---- listening ---------------------------------------------------------

  Future<bool> listen({
    required String locale,
    required void Function(String text, bool isFinal) onResult,
    required void Function() onDone,
    bool stopSpeech = true,
  }) async {
    if (!await Permission.microphone.request().isGranted) return false;
    _onDone = onDone;
    if (!_ready) {
      _ready = await _stt.initialize(
        onStatus: (st) {
          if (st == 'done' || st == 'notListening') _onDone?.call();
        },
        onError: (_) => _onDone?.call(),
      );
    }
    if (!_ready) return false;
    if (stopSpeech) await stopSpeaking();
    if (_stt.isListening) await _stt.cancel();
    await _stt.listen(
      localeId: locale.replaceAll('-', '_'),
      pauseFor: const Duration(seconds: 3),
      listenFor: const Duration(seconds: 30),
      listenOptions: SpeechListenOptions(partialResults: true),
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
    );
    return true;
  }

  Future<void> stopListening() => _stt.stop();
}
