import 'dart:convert';
import 'package:device_calendar/device_calendar.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import '../core/settings_store.dart';

/// Builds the live context MO gets with every query (time, place, weather,
/// news, calendar). Nothing is cached or stored.
class ContextService {
  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  static String _two(int n) => n.toString().padLeft(2, '0');

  static Future<String> build(SettingsStore s, String query) async {
    final q = query.toLowerCase();
    final now = DateTime.now();
    final b = StringBuffer()
      ..writeln('Device date: ${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]} ${now.year}.')
      ..writeln('Device time: ${_two(now.hour)}:${_two(now.minute)} (local).');

    final wantsWeather = RegExp(r'weather|temperature|rain|forecast|hot|cold|umbrella').hasMatch(q);
    final wantsNews = RegExp(r'news|headline|sport|score|match|fixture').hasMatch(q);
    final wantsCal = RegExp(r'calendar|schedule|event|meeting|appointment|agenda|today|tomorrow').hasMatch(q);

    Position? pos;
    if (wantsWeather || wantsNews) pos = await _position();
    final place = s.defaultLocation.trim();

    if (wantsWeather) b.writeln(await _weather(s, pos, place));
    if (wantsNews) b.writeln(await _news(s, q, place));
    if (wantsCal && s.calendarOn) b.writeln(await _calendar());
    return b.toString();
  }

  static Future<Position?> _position() async {
    try {
      if (!await Permission.location.isGranted) return null;
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
      ).timeout(const Duration(seconds: 6));
    } catch (_) {
      return null;
    }
  }

  static Future<String> _weather(SettingsStore s, Position? pos, String place) async {
    if (s.weatherKey.isEmpty) return 'Weather: no OpenWeather key set; say so briefly.';
    final loc = pos != null
        ? 'lat=${pos.latitude}&lon=${pos.longitude}'
        : place.isNotEmpty
            ? 'q=${Uri.encodeComponent(place)}'
            : null;
    if (loc == null) return 'Weather: no location available; ask the user to allow location or set a default one.';
    try {
      final r = await http
          .get(Uri.parse('https://api.openweathermap.org/data/2.5/weather?$loc&units=metric&appid=${s.weatherKey}'))
          .timeout(const Duration(seconds: 8));
      final j = jsonDecode(r.body);
      if (r.statusCode != 200) return 'Weather lookup failed: ${j['message']}';
      return 'Current weather in ${j['name']}: ${j['weather'][0]['description']}, '
          '${j['main']['temp']}°C (feels ${j['main']['feels_like']}°C), humidity ${j['main']['humidity']}%, wind ${j['wind']['speed']} m/s.';
    } catch (_) {
      return 'Weather lookup failed (network).';
    }
  }

  static Future<String> _news(SettingsStore s, String q, String place) async {
    if (s.newsKey.isEmpty) return 'News: no News API key set; say so briefly.';
    final topic = q.contains('sport') || q.contains('score') || q.contains('match') ? 'sports' : 'top news';
    final term = place.isNotEmpty ? '$topic $place' : topic;
    try {
      final r = await http
          .get(Uri.parse('https://newsapi.org/v2/everything?q=${Uri.encodeComponent(term)}&pageSize=5&sortBy=publishedAt&language=en&apiKey=${s.newsKey}'))
          .timeout(const Duration(seconds: 8));
      final j = jsonDecode(r.body);
      if (r.statusCode != 200) return 'News lookup failed: ${j['message']}';
      final items = (j['articles'] as List).map((a) => '- ${a['title']} (${a['source']['name']})').join('\n');
      return 'Latest headlines for "$term":\n$items';
    } catch (_) {
      return 'News lookup failed (network).';
    }
  }

  static Future<String> _calendar() async {
    try {
      final plugin = DeviceCalendarPlugin();
      var perm = await plugin.hasPermissions();
      if (!(perm.data ?? false)) perm = await plugin.requestPermissions();
      if (!(perm.data ?? false)) return 'Calendar: permission not granted.';
      final cals = (await plugin.retrieveCalendars()).data ?? [];
      final start = DateTime.now();
      final end = start.add(const Duration(days: 7));
      final lines = <String>[];
      for (final c in cals) {
        final ev = await plugin.retrieveEvents(c.id, RetrieveEventsParams(startDate: start, endDate: end));
        for (final e in ev.data ?? <Event>[]) {
          final t = e.start?.toLocal();
          if (t == null) continue;
          lines.add('${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)} ${e.title}');
        }
      }
      lines.sort();
      return lines.isEmpty ? 'Calendar: no events in the next 7 days.' : 'Upcoming events (next 7 days):\n${lines.take(12).join('\n')}';
    } catch (_) {
      return 'Calendar lookup failed.';
    }
  }
}
