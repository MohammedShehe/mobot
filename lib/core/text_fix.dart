/// Text clean-up for what MO writes and what MO says.
class TextFix {
  /// The name is always written "MO" in text.
  static String brand(String t) => t.replaceAll(RegExp(r'\b(?:[Mm][Oo]|Moo)\b'), 'MO');

  /// Removes markdown and turns web addresses into speakable text.
  static String _plain(String t) {
    var s = t.replaceAll(RegExp(r'[*_#`~]'), '');
    return s.replaceAllMapped(
      RegExp(r'\b(?:https?://)?(?:www\.)?([a-z0-9-]+(?:\.[a-z0-9-]+)*\.(?:com|online|org|net|io|app|dev|co|tz|in|ke))\b', caseSensitive: false),
      (m) => m[1]!.replaceAll('.', ' dot '),
    );
  }

  /// MO is spoken "more" (rhymes with "door"), never "moo".
  static String _say(String t) {
    return t
        .replaceAll(RegExp(r'\bMO11\b', caseSensitive: false), 'more eleven')
        .replaceAll(RegExp(r'\bMO\b', caseSensitive: false), 'more');
  }

  /// Text for the speech engine (single language).
  static String spoken(String t) => _say(_plain(t));

  /// Splits text so the words "Little" and "MO" can be spoken with an English
  /// voice inside a non-English reply. Returns (text, isEnglishSegment).
  static List<(String, bool)> segments(String text) {
    final s = _plain(text);
    final out = <(String, bool)>[];
    var last = 0;
    for (final m in RegExp(r'\b(?:Little|MO11|MO)\b').allMatches(s)) {
      if (m.start > last) out.add((s.substring(last, m.start), false));
      final w = m[0]!;
      out.add((w == 'Little' ? 'Little' : w == 'MO11' ? 'more eleven' : 'more', true));
      last = m.end;
    }
    if (last < s.length) out.add((s.substring(last), false));
    // merge neighbours of the same kind
    final merged = <(String, bool)>[];
    for (final seg in out) {
      if (merged.isNotEmpty && merged.last.$2 == seg.$2) {
        merged[merged.length - 1] = ('${merged.last.$1}${seg.$1}', seg.$2);
      } else {
        merged.add(seg);
      }
    }
    return merged.where((e) => e.$1.trim().isNotEmpty).toList();
  }
}
