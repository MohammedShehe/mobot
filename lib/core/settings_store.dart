import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Language -> region/accent -> BCP-47 locale.
const kLocales = <String, Map<String, String>>{
  'English': {'US': 'en-US', 'UK': 'en-GB', 'Kenya': 'en-KE', 'India': 'en-IN'},
  'Swahili': {'Tanzania': 'sw-TZ', 'Kenya': 'sw-KE'},
  'Hindi': {'India': 'hi-IN'},
  'French': {'France': 'fr-FR', 'Canada': 'fr-CA'},
  'Spanish': {'Spain': 'es-ES', 'Mexico': 'es-MX'},
};

const kDefaultGroqModel = 'llama-3.3-70b-versatile';
const kMusicProviders = ['YouTube Music', 'Spotify'];

/// User preferences only. Chat history lives in HistoryStore.
class SettingsStore extends ChangeNotifier {
  late SharedPreferences _p;

  bool enabled = true;
  String wakeWord = 'Yow MO';
  String voiceGender = 'female'; // female | male
  String tone = 'friendly'; // friendly | formal
  String length = 'short'; // short | detailed
  String language = 'English';
  String accent = 'US';
  String defaultLocation = '';
  // Keys can be baked in at build time: --dart-define=GROQ_API_KEY=...
  String groqKey = const String.fromEnvironment('GROQ_API_KEY');
  String weatherKey = const String.fromEnvironment('OPENWEATHER_API_KEY');
  String newsKey = const String.fromEnvironment('NEWS_API_KEY');
  bool calendarOn = false;
  bool smartHomeOn = false;
  bool musicOn = false;
  bool dark = true;
  bool historyOn = true;
  bool handsFree = false;
  bool backgroundWake = true; // keep listening for the wake word when the app is closed / phone locked (Android)
  // always | mic (only after voice input) | off (text only)
  String voiceReplies = 'mic';
  // Voice the user picked, per locale, e.g. {'sw-TZ': 'sw-tz-x-...'}
  Map<String, String> voices = {};
  String groqModel = kDefaultGroqModel;
  String musicProvider = 'YouTube Music';
  String haUrl = '';
  String haToken = '';

  /// Model actually sent to Groq (falls back to the default when empty).
  String get model => groqModel.trim().isEmpty ? kDefaultGroqModel : groqModel.trim();

  String get locale {
    final m = kLocales[language] ?? kLocales['English']!;
    return m[accent] ?? m.values.first;
  }

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    enabled = _p.getBool('enabled') ?? enabled;
    wakeWord = _p.getString('wakeWord') ?? wakeWord;
    voiceGender = _p.getString('voiceGender') ?? voiceGender;
    tone = _p.getString('tone') ?? tone;
    length = _p.getString('length') ?? length;
    language = _p.getString('language') ?? language;
    accent = _p.getString('accent') ?? accent;
    defaultLocation = _p.getString('defaultLocation') ?? defaultLocation;
    groqKey = _p.getString('groqKey') ?? groqKey;
    weatherKey = _p.getString('weatherKey') ?? weatherKey;
    newsKey = _p.getString('newsKey') ?? newsKey;
    calendarOn = _p.getBool('calendarOn') ?? calendarOn;
    smartHomeOn = _p.getBool('smartHomeOn') ?? smartHomeOn;
    musicOn = _p.getBool('musicOn') ?? musicOn;
    dark = _p.getBool('dark') ?? dark;
    historyOn = _p.getBool('historyOn') ?? historyOn;
    handsFree = _p.getBool('handsFree') ?? handsFree;
    backgroundWake = _p.getBool('backgroundWake') ?? backgroundWake;
    voiceReplies = _p.getString('voiceReplies') ?? voiceReplies;
    try {
      voices = Map<String, String>.from(jsonDecode(_p.getString('voices') ?? '{}') as Map);
    } catch (_) {
      voices = {};
    }
    groqModel = _p.getString('groqModel') ?? groqModel;
    musicProvider = _p.getString('musicProvider') ?? musicProvider;
    haUrl = _p.getString('haUrl') ?? haUrl;
    haToken = _p.getString('haToken') ?? haToken;
  }

  /// Mutate fields inside [f]; saves and notifies listeners.
  void update(void Function() f) {
    f();
    _p.setBool('enabled', enabled);
    _p.setString('wakeWord', wakeWord);
    _p.setString('voiceGender', voiceGender);
    _p.setString('tone', tone);
    _p.setString('length', length);
    _p.setString('language', language);
    _p.setString('accent', accent);
    _p.setString('defaultLocation', defaultLocation);
    _p.setString('groqKey', groqKey);
    _p.setString('weatherKey', weatherKey);
    _p.setString('newsKey', newsKey);
    _p.setBool('calendarOn', calendarOn);
    _p.setBool('smartHomeOn', smartHomeOn);
    _p.setBool('musicOn', musicOn);
    _p.setBool('dark', dark);
    _p.setBool('historyOn', historyOn);
    _p.setBool('handsFree', handsFree);
    _p.setBool('backgroundWake', backgroundWake);
    _p.setString('voiceReplies', voiceReplies);
    _p.setString('voices', jsonEncode(voices));
    _p.setString('groqModel', groqModel);
    _p.setString('musicProvider', musicProvider);
    _p.setString('haUrl', haUrl);
    _p.setString('haToken', haToken);
    notifyListeners();
  }
}
