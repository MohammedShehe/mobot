# MO fixes

1. "Moo" -> "more": lib/core/text_fix.dart (spoken text now says "more").
2. Voices: Android voices have no gender in their name, so MO now measures it (records each voice, analyses
   the pitch, caches the result). Only installed voices are listed (uninstalled ones fell back to the same
   default voice). Files: VoiceTools.kt, voice_service.dart, settings_screen.dart.
3. Wake word matching now understands "more/moe/mow" and any greeting (hey / yo / you / yow + MO):
   lib/core/wake_word.dart and WakeMatcher.kt.
4. Wake word when MO is closed / phone locked (Android): WakeService.kt (foreground microphone service),
   MainActivity.kt, AndroidManifest.xml, wake_bridge.dart, chat_controller.dart.

After installing: Settings > Voice & Interaction > turn on "Hands-free wake word", allow Microphone,
Notifications, "Display over other apps" and "Unrestricted battery".
Run `flutter clean && flutter run` (native code changed).
