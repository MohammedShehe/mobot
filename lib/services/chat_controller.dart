import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/settings_store.dart';
import '../core/text_fix.dart';
import '../core/wake_word.dart';
import 'context_service.dart';
import 'groq_service.dart';
import 'history_store.dart';
import 'voice_service.dart';
import 'wake_bridge.dart';

/// Current conversation + hands-free loop. Conversations are saved to
/// [HistoryStore] (on-device) when history mode is on.
class ChatController extends ChangeNotifier {
  ChatController(this.settings, this.history) {
    voice.speaking.addListener(() {
      if (!voice.speaking.value) {
        _lastSpoke = DateTime.now();
        if (_armed) _armedAt = DateTime.now(); // give the user the full window after MO finishes talking
      }
      notifyListeners();
    });
    settings.addListener(_onSettings);
    _life = AppLifecycleListener(onStateChange: (st) {
      _bg = st != AppLifecycleState.resumed;
      // Opened by the wake word while closed / locked: pick up what was said.
      if (st == AppLifecycleState.resumed) _pullWake();
    });
    _lastLocale = settings.locale;
    voice.warmUp(settings.locale); // measure male/female voices in the background
    syncHandsFree();
    Future.delayed(const Duration(milliseconds: 900), _pullWake); // cold start from the wake word
  }

  final SettingsStore settings;
  final HistoryStore history;
  final voice = VoiceService();
  late final AppLifecycleListener _life;

  final List<Turn> messages = []; // roles: user | assistant | error
  Conversation? _current;
  bool thinking = false;
  bool listening = false;
  String partial = '';

  bool _hf = false; // hands-free loop running
  bool _bg = false; // app in background
  bool _armed = false; // wake word heard alone; next utterance is the question
  DateTime _armedAt = DateTime(2000);
  DateTime _lastSpoke = DateTime(2000);
  String _lastLocale = '';
  String _bgSig = '';
  String _lastHeard = '';
  DateTime _lastHeardAt = DateTime(2000);

  /// off | listening | armed | paused (shown as a pill in the chat screen)
  String hfStatus = 'off';
  void _setHf(String st) {
    if (hfStatus == st) return;
    hfStatus = st;
    notifyListeners();
  }

  String get title => _current?.title ?? 'MO';

  @override
  void dispose() {
    _hf = false;
    _life.dispose();
    WakelockPlus.disable();
    settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    if (settings.voiceReplies == 'off' && voice.speaking.value) voice.stopSpeaking();
    if (settings.locale != _lastLocale) {
      _lastLocale = settings.locale;
      voice.warmUp(settings.locale);
    }
    syncHandsFree();
  }

  String _ack() => switch (settings.language) {
        'Swahili' => 'Naam, Little?',
        'French' => 'Oui, Little ?',
        'Spanish' => 'Sí, Little?',
        'Hindi' => 'जी, Little?',
        _ => 'Yes, Little?',
      };

  String _stripWake(String raw) => WakeWord.match(raw, settings.wakeWord) ?? raw.trim();

  bool _shouldSpeak(bool viaVoice) => switch (settings.voiceReplies) {
        'always' => true,
        'mic' => viaVoice,
        _ => false,
      };

  String _system(String ctx) {
    final s = settings;
    final lang = s.language == 'Swahili' && s.accent == 'Tanzania'
        ? 'Swahili (natural Tanzanian Swahili, as spoken in Tanzania and Zanzibar)'
        : s.language;
    return '''You are MO, a warm, sharp human-robot assistant living in a mobile app.
Your name is always written in capital letters: MO. Never write it as "Mo", "mo" or "Moo" (the app takes care of how it is pronounced).
Address the user as "Little" (for example "Sure thing, Little"), naturally and at most once per reply. Do not open every reply with the same phrase. Always keep the word "Little" in English, exactly as spelled, even when you reply in Swahili, Hindi, French or Spanish. Never translate it.
Tone: ${s.tone == 'formal' ? 'formal, polite and precise' : 'friendly, casual and encouraging'}.
Length: ${s.length == 'short' ? 'short, 1 to 3 sentences unless asked for more' : 'detailed and thorough, but well organised'}.
Reply in $lang.
Speak like a real person: answer first, be direct, no filler such as "As an AI", do not repeat the question back, and keep grammar and spelling correct.
Your answers may be read aloud, so use plain text: no markdown, no emojis, no lists with symbols.
About this app and its developer (share only when the user asks about the app, who made it, or the developer): MO was built by MO11 (website: molittle.fourbrothers.online), a Zanzibari from Tanzania who studied at LPU in India. He started building MO in 2026, when he was 21 years old. Do not credit anyone else as the developer.
Use the live device context below when relevant. Never invent weather, news, sports or calendar facts that are not in it; if data is missing, say what is needed.
Live device context:
$ctx''';
  }

  // ---- history -----------------------------------------------------------

  static String _titleFrom(String t) {
    final one = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return one.length > 40 ? '${one.substring(0, 40)}…' : one;
  }

  void _persist() {
    if (!settings.historyOn) return;
    final turns = messages.where((m) => m.role != 'error').toList();
    if (turns.isEmpty) return;
    final c = _current ??= Conversation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: _titleFrom(turns.first.text),
    );
    c.turns
      ..clear()
      ..addAll(turns);
    c.updated = DateTime.now();
    history.save(c);
  }

  void newChat() {
    voice.stopSpeaking();
    messages.clear();
    _current = null;
    notifyListeners();
  }

  void open(Conversation c) {
    voice.stopSpeaking();
    messages
      ..clear()
      ..addAll(c.turns);
    _current = c;
    notifyListeners();
  }

  Future<void> deleteConversation(String id) async {
    if (_current?.id == id) newChat();
    await history.delete(id);
  }

  Future<void> clearHistory() async {
    newChat();
    await history.clear();
  }

  // ---- chat --------------------------------------------------------------

  Future<void> send(String raw, {bool viaVoice = false, bool strip = true}) async {
    final text = strip ? _stripWake(raw) : raw.trim();
    if (text.isEmpty || thinking || !settings.enabled) return;
    messages.add(Turn('user', text));
    _persist();
    thinking = true;
    notifyListeners();
    try {
      final ctx = await ContextService.build(settings, text);
      final convo = messages.where((m) => m.role != 'error').toList();
      final turns = !settings.historyOn
          ? [convo.last]
          : convo.length > 20 ? convo.sublist(convo.length - 20) : convo;
      final reply = await GroqService.ask(
        apiKey: settings.groqKey,
        model: settings.model,
        system: _system(ctx),
        turns: turns,
      );
      final clean = TextFix.brand(reply);
      messages.add(Turn('assistant', clean));
      _persist();
      if (_shouldSpeak(viaVoice)) voice.speak(clean, settings);
    } catch (e) {
      messages.add(Turn('error', e.toString().replaceFirst('Exception: ', '')));
    }
    thinking = false;
    notifyListeners();
  }

  // ---- voice -------------------------------------------------------------

  Future<bool> toggleMic() async {
    if (listening) {
      await voice.stopListening();
      return true;
    }
    partial = '';
    listening = true; // claim the mic so the hands-free loop backs off
    final ok = await voice.listen(
      locale: settings.locale,
      onResult: (t, isFinal) {
        partial = t;
        notifyListeners();
        if (isFinal && t.trim().isNotEmpty) {
          final q = t;
          partial = '';
          send(q, viaVoice: true);
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

  // ---- hands-free wake word (foreground only) ----------------------------

  void syncHandsFree() {
    final want = settings.handsFree && settings.enabled;
    if (want && !_hf) {
      _hf = true;
      WakelockPlus.enable(); // keep the screen on so the mic stays available
      _hfLoop();
    } else if (!want && _hf) {
      _hf = false;
      _armed = false;
      WakelockPlus.disable();
      voice.stopListening();
      _setHf('off');
    }
    _syncBackground();
  }

  /// Starts / stops the Android service that listens for the wake word while
  /// MO is closed or the phone is locked. Only (re)sent when something changed.
  void _syncBackground() {
    final on = settings.handsFree && settings.enabled && settings.backgroundWake;
    final sig = on ? '${settings.wakeWord}|${settings.locale}' : 'off';
    if (sig == _bgSig) return;
    _bgSig = sig;
    if (on) {
      WakeBridge.start(settings.wakeWord, settings.locale);
    } else {
      WakeBridge.stop();
    }
  }

  Future<void> _pullWake() async {
    final rest = await WakeBridge.consume();
    if (rest != null) _onWake(rest);
  }

  /// The wake word was heard (in the app or by the background service).
  void _onWake(String rest) {
    if (!settings.enabled) return;
    HapticFeedback.mediumImpact();
    if (rest.trim().isEmpty) {
      _armed = true;
      _armedAt = DateTime.now();
      _setHf('armed');
      if (settings.voiceReplies != 'off') voice.speak(_ack(), settings);
    } else {
      send(rest, viaVoice: true, strip: false);
    }
  }

  void _onHeard(String t) {
    final now = DateTime.now();
    // Some engines deliver the same final result twice.
    if (t == _lastHeard && now.difference(_lastHeardAt) < const Duration(seconds: 2)) return;
    _lastHeard = t;
    _lastHeardAt = now;

    if (_armed) {
      _armed = false;
      send(t, viaVoice: true, strip: false);
      return;
    }
    final rest = WakeWord.match(t, settings.wakeWord);
    if (rest == null) return; // not for MO: ignored, never sent anywhere
    _onWake(rest);
  }

  Future<void> _hfLoop() async {
    var quick = 0; // consecutive empty, very short sessions -> back off
    while (_hf) {
      final cooling = DateTime.now().difference(_lastSpoke) < const Duration(milliseconds: 900);
      if (_bg || thinking || listening || voice.speaking.value || cooling) {
        _setHf('paused');
        await Future.delayed(const Duration(milliseconds: 400));
        continue;
      }
      if (_armed && DateTime.now().difference(_armedAt) > const Duration(seconds: 10)) _armed = false;
      _setHf(_armed ? 'armed' : 'listening');

      final done = Completer<void>();
      var gotFinal = false;
      var lastPartial = '';
      final t0 = DateTime.now();
      final ok = await voice.listen(
        locale: settings.locale,
        stopSpeech: false,
        onResult: (t, isFinal) {
          lastPartial = t;
          if (isFinal && t.trim().isNotEmpty) {
            gotFinal = true;
            _onHeard(t);
          }
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
      );
      if (!ok) {
        // Mic denied or speech engine unavailable: switch the feature off.
        _hf = false;
        WakelockPlus.disable();
        _setHf('off');
        settings.update(() => settings.handsFree = false);
        break;
      }
      // Poll instead of only awaiting: a manual mic tap replaces the status
      // callback, so back off as soon as it takes over the microphone.
      while (_hf && !done.isCompleted && !listening && DateTime.now().difference(t0) < const Duration(seconds: 35)) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
      // Some engines end a session without a final result: use the last partial.
      if (!gotFinal && !listening && lastPartial.trim().isNotEmpty) _onHeard(lastPartial);

      final short = DateTime.now().difference(t0) < const Duration(milliseconds: 1500);
      quick = short && lastPartial.isEmpty ? quick + 1 : 0;
      await Future.delayed(Duration(milliseconds: 250 + quick.clamp(0, 8) * 350));
    }
    _setHf('off');
  }
}
