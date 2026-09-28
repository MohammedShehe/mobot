import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/settings_store.dart';
import 'core/theme.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'services/chat_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsStore();
  await settings.load();
  runApp(MoApp(settings: settings));
}

class MoApp extends StatefulWidget {
  const MoApp({super.key, required this.settings});
  final SettingsStore settings;
  @override
  State<MoApp> createState() => _MoAppState();
}

class _MoAppState extends State<MoApp> {
  late final ChatController chat = ChatController(widget.settings);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settings,
      builder: (context, _) {
        final dark = widget.settings.dark;
        SystemChrome.setSystemUIOverlayStyle(dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);
        return MaterialApp(
          title: 'MO',
          debugShowCheckedModeBanner: false,
          theme: moTheme(Brightness.light),
          darkTheme: moTheme(Brightness.dark),
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          home: SplashScreen(next: (_) => Shell(settings: widget.settings, chat: chat)),
        );
      },
    );
  }
}
