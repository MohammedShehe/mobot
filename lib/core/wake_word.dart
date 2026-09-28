/// Forgiving wake-word matching. Speech recognisers rarely return the exact
/// phrase ("Yow MO" comes back as "yo mo", "you more", "yowmo"...), so both
/// sides are reduced to a rough phonetic key and compared with a small
/// edit-distance tolerance. MO is often heard as "more", "moe", "mow", "moh":
/// all of them reduce to the same key.
///
/// Kotlin twin: android/.../WakeMatcher.kt (used while the app is closed).
class WakeWord {
  static const _greet = {
    'hey', 'hay', 'hi', 'hello', 'yo', 'you', 'yow', 'your', 'yeah', 'okay', 'ok', 'oh', 'hei', 'eh',
  };
  static final _vowelish = RegExp(r'ore|oar|oor|our|oo|ow|ou|oe|oh|au|aw|or');

  static String _letters(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

  static String _key(String s) {
    final t = _letters(s).replaceAll(_vowelish, 'o');
    return t.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
  }

  static int _distance(String a, String b) {
    if (a == b) return 0;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [cur[j - 1] + 1, prev[j] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  static String _clean(String s) => s.replaceFirst(RegExp(r'^[\s,.!:;?-]+'), '').trim();

  /// Returns the text after the wake word ('' when only the wake word was
  /// said), or null when [heard] does not start with the wake word.
  /// An empty [wake] matches everything.
  static String? match(String heard, String wake) {
    final h = heard.trim();
    final w = wake.trim();
    if (w.isEmpty) return h;
    final wk = _key(w);
    final words = h.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    if (words.isEmpty) return null;

    if (wk.isEmpty) {
      // Non-Latin wake word: plain prefix match.
      return h.toLowerCase().startsWith(w.toLowerCase()) ? _clean(h.substring(w.length)) : null;
    }

    final wWords = w.split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
    final n = wWords.length;
    final tolerance = (wk.length * 0.25).floor().clamp(1, 3);
    var bestK = -1;
    var bestD = 999;
    for (var k = 1; k <= n + 1 && k <= words.length; k++) {
      final d = _distance(_key(words.take(k).join()), wk);
      if (d < bestD || (d == bestD && k == n)) {
        bestD = d;
        bestK = k;
      }
    }
    if (bestK >= 0 && bestD <= tolerance) return _clean(words.skip(bestK).join(' '));

    // "<greeting> MO": accept any greeting (hey / yo / you / yow ...) before the name.
    if (wWords.length >= 2 && _greet.contains(_letters(wWords.first))) {
      final core = _key(wWords.skip(1).join());
      if (core.isNotEmpty && _greet.contains(_letters(words.first))) {
        for (var m = 1; m <= 3 && 1 + m <= words.length; m++) {
          if (_key(words.skip(1).take(m).join()) == core) {
            return _clean(words.skip(1 + m).join(' '));
          }
        }
      }
    }
    return null;
  }
}
