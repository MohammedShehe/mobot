import 'package:url_launcher/url_launcher.dart';
import '../core/settings_store.dart';

/// "Play <song/artist>" opens the chosen music app's search for it.
class MusicService {
  static final _play = RegExp(
    r'^\s*(?:please\s+)?(?:play|put on|listen to|cheza|bajao|joue|pon)\s+(.+?)(?:\s+on\s+(?:youtube|spotify)(?:\s+music)?)?\s*[.!?]?\s*$',
    caseSensitive: false,
  );

  static String? extract(String text) => _play.firstMatch(text)?.group(1)?.trim();

  static Future<String> run(SettingsStore s, String term) async {
    final q = Uri.encodeComponent(term);
    final uri = Uri.parse(s.musicProvider == 'Spotify'
        ? 'https://open.spotify.com/search/$q'
        : 'https://music.youtube.com/search?q=$q');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ok
          ? 'Music: opened ${s.musicProvider} searching for "$term". Confirm briefly that it is opening.'
          : 'Music: could not open ${s.musicProvider}.';
    } catch (_) {
      return 'Music: could not open ${s.musicProvider}.';
    }
  }
}
