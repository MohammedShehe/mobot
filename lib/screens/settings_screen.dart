import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/settings_store.dart';
import '../core/theme.dart';
import '../services/chat_controller.dart';
import '../services/voice_service.dart';
import '../services/wake_bridge.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings, required this.chat});
  final SettingsStore settings;
  final ChatController chat;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  SettingsStore get s => widget.settings;
  late final _wake = TextEditingController(text: s.wakeWord);
  late final _loc = TextEditingController(text: s.defaultLocation);
  late final _groq = TextEditingController(text: s.groqKey);
  late final _weather = TextEditingController(text: s.weatherKey);
  late final _news = TextEditingController(text: s.newsKey);
  late final _model = TextEditingController(text: s.groqModel);
  late final _haUrl = TextEditingController(text: s.haUrl);
  late final _haToken = TextEditingController(text: s.haToken);

  // ignore: deprecated_member_use
  static final _perms = <String, (IconData, Permission)>{
    'Microphone': (Icons.mic_none_rounded, Permission.microphone),
    'Location': (Icons.location_on_outlined, Permission.location),
    // ignore: deprecated_member_use
    'Calendar': (Icons.event_outlined, Permission.calendar),
  };
  // Needed for waking MO while it is closed / the phone is locked (Android).
  static final _bgPerms = <String, (IconData, Permission, String)>{
    'Notifications': (Icons.notifications_none_rounded, Permission.notification, 'Shows that MO is listening'),
    'Display over other apps': (Icons.open_in_new_rounded, Permission.systemAlertWindow, 'Lets MO open itself when you say the wake word'),
    'Unrestricted battery': (Icons.battery_charging_full_rounded, Permission.ignoreBatteryOptimizations, 'Stops Android from putting the listener to sleep'),
  };
  final Map<String, PermissionStatus> _status = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [_wake, _loc, _groq, _weather, _news, _model, _haUrl, _haToken]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    for (final e in _perms.entries) {
      _status[e.key] = await e.value.$2.status;
    }
    if (WakeBridge.supported) {
      for (final e in _bgPerms.entries) {
        try {
          _status[e.key] = await e.value.$2.status;
        } catch (_) {}
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _ask(String name) async {
    final p = (_perms[name]?.$2) ?? _bgPerms[name]!.$2;
    final st = await p.request();
    if (st.isPermanentlyDenied) await openAppSettings();
    await _refresh();
  }

  Future<void> _pickVoice() async {
    // First time: MO listens to each installed voice to tell male from female.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      await widget.chat.voice.warmUp(s.locale).timeout(const Duration(seconds: 60), onTimeout: () {});
    } catch (_) {}
    final voices = await widget.chat.voice.voicesFor(s.locale);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // loading dialog
    final hasMale = voices.any((v) => v.gender == 'male');
    final hasFemale = voices.any((v) => v.gender == 'female');
    final counts = <String, int>{};
    final titles = <String, String>{}; // voice name -> "Male 2"
    for (final v in voices) {
      final label = v.gender == 'male' ? 'Male' : v.gender == 'female' ? 'Female' : 'Voice';
      titles[v.name] = '$label ${counts[label] = (counts[label] ?? 0) + 1}';
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (c) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('Automatic'),
              subtitle: Text('Best ${s.voiceGender} voice for ${s.locale}'),
              selected: s.voices[s.locale] == null,
              onTap: () {
                s.update(() => s.voices.remove(s.locale));
                Navigator.pop(c);
              },
            ),
            if (voices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('No voices found for this language on this phone. Install it in your phone\'s Text-to-speech settings, then reopen this list.'),
              )
            else if (!hasMale || !hasFemale)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Text(
                  'This phone has no ${!hasMale ? 'male' : 'female'} voice installed for ${s.locale}. '
                  'Add one in Settings > Text-to-speech > Google > Install voice data, then reopen this list. '
                  'Until then MO shifts the pitch of the voice it has.',
                  style: TextStyle(fontSize: 12, color: Theme.of(c).colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
            for (final v in voices)
              ListTile(
                leading: Icon(v.gender == 'male' ? Icons.face_6_outlined : v.gender == 'female' ? Icons.face_3_outlined : Icons.face_outlined),
                title: Text(titles[v.name] ?? 'Voice'),
                subtitle: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: s.voices[s.locale] == v.name,
                trailing: IconButton(
                  tooltip: 'Play sample',
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  onPressed: () => widget.chat.voice.preview(v, s),
                ),
                onTap: () {
                  s.update(() {
                    s.voices[s.locale] = v.name;
                    if (v.gender != null) s.voiceGender = v.gender!;
                  });
                  Navigator.pop(c);
                },
              ),
          ]),
        ),
      ),
    );
  }

  void _saved(String what) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text('$what saved'), duration: const Duration(seconds: 1)));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListenableBuilder(
            listenable: s,
            builder: (context, _) {
              final regions = (kLocales[s.language] ?? kLocales['English']!).keys.toList();
              final sections = <Widget>[
                _powerCard(context),
                _Section('Voice & Interaction', Icons.graphic_eq_rounded, [
                  _SaveField(controller: _wake, label: 'Wake word', onSave: () {
                    s.update(() => s.wakeWord = _wake.text.trim().isEmpty ? 'Yow MO' : _wake.text.trim());
                    _saved('Wake word');
                  }),
                  _SwitchRow(Icons.hearing_outlined, 'Hands-free wake word',
                      'Say the wake word and MO answers, like "Hey Siri"', s.handsFree, (v) async {
                    if (v) {
                      await _ask('Microphone');
                      if (WakeBridge.supported) await Permission.notification.request();
                      await _refresh();
                    }
                    s.update(() => s.handsFree = v && (_status['Microphone']?.isGranted ?? false));
                  }),
                  if (WakeBridge.supported && s.handsFree) ...[
                    _SwitchRow(Icons.bedtime_outlined, 'Wake up when MO is closed',
                        'Keeps listening with the app closed and the phone locked, and opens MO to answer', s.backgroundWake,
                        (v) => s.update(() => s.backgroundWake = v)),
                    if (s.backgroundWake)
                      for (final e in _bgPerms.entries) _bgPermRow(e.key, e.value.$1, e.value.$3),
                  ],
                  _Choice(
                    'Voice replies',
                    const ['always', 'mic', 'off'],
                    s.voiceReplies,
                    (v) {
                      s.update(() => s.voiceReplies = v);
                      if (v == 'off') widget.chat.voice.stopSpeaking();
                    },
                    labels: const {'always': 'Always', 'mic': 'After voice input', 'off': 'Off (text only)'},
                  ),
                  _Choice('Voice', const ['female', 'male'], s.voiceGender, (v) => s.update(() {
                        s.voiceGender = v;
                        s.voices.remove(s.locale); // the Male/Female choice must win over an old hand-picked voice
                      })),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickVoice,
                        icon: const Icon(Icons.record_voice_over_outlined, size: 18),
                        label: const Text('Choose voice'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => widget.chat.voice.speak('Hi Little, I am MO. This is how I sound.', s),
                        icon: const Icon(Icons.play_arrow_rounded, size: 20),
                        label: const Text('Test'),
                      ),
                    ),
                  ]),
                  _Choice('Tone', const ['friendly', 'formal'], s.tone, (v) => s.update(() => s.tone = v)),
                  _Choice('Response length', const ['short', 'detailed'], s.length, (v) => s.update(() => s.length = v)),
                ]),
                _Section('Language & Region', Icons.language_rounded, [
                  _Choice('Language', kLocales.keys.toList(), s.language, (v) => s.update(() {
                        s.language = v;
                        s.accent = kLocales[v]!.keys.first;
                      })),
                  _Choice('Accent', regions, regions.contains(s.accent) ? s.accent : regions.first, (v) => s.update(() => s.accent = v)),
                  _SaveField(controller: _loc, label: 'Default location (city)', onSave: () {
                    s.update(() => s.defaultLocation = _loc.text.trim());
                    _saved('Location');
                  }),
                ]),
                _Section('Integrations', Icons.hub_outlined, [
                  _SaveField(controller: _groq, label: 'Groq API key', secret: true, onSave: () {
                    s.update(() => s.groqKey = _groq.text.trim());
                    _saved('Groq key');
                  }),
                  _SaveField(controller: _model, label: 'Groq model (blank = $kDefaultGroqModel)', onSave: () {
                    s.update(() => s.groqModel = _model.text.trim());
                    _saved('Groq model');
                  }),
                  _SaveField(controller: _weather, label: 'OpenWeather API key', secret: true, onSave: () {
                    s.update(() => s.weatherKey = _weather.text.trim());
                    _saved('OpenWeather key');
                  }),
                  _SaveField(controller: _news, label: 'News API key', secret: true, onSave: () {
                    s.update(() => s.newsKey = _news.text.trim());
                    _saved('News API key');
                  }),
                  _SwitchRow(Icons.event_outlined, 'Calendar', 'Let MO read upcoming events', s.calendarOn, (v) async {
                    if (v) await _ask('Calendar');
                    s.update(() => s.calendarOn = v && (_status['Calendar']?.isGranted ?? false));
                  }),
                  _SwitchRow(Icons.home_outlined, 'Smart home', 'Say "turn on the lights" and MO sends it to Home Assistant', s.smartHomeOn,
                      (v) => s.update(() => s.smartHomeOn = v)),
                  if (s.smartHomeOn) ...[
                    _SaveField(controller: _haUrl, label: 'Home Assistant URL (e.g. http://192.168.1.10:8123)', onSave: () {
                      s.update(() => s.haUrl = _haUrl.text.trim());
                      _saved('Home Assistant URL');
                    }),
                    _SaveField(controller: _haToken, label: 'Home Assistant long-lived token', secret: true, onSave: () {
                      s.update(() => s.haToken = _haToken.text.trim());
                      _saved('Home Assistant token');
                    }),
                  ],
                  _SwitchRow(Icons.music_note_outlined, 'Music', 'Say "play <song or artist>" and MO opens it in your music app', s.musicOn,
                      (v) => s.update(() => s.musicOn = v)),
                  if (s.musicOn) _Choice('Music app', kMusicProviders, s.musicProvider, (v) => s.update(() => s.musicProvider = v)),
                ]),
                _Section('Appearance', Icons.palette_outlined, [
                  Row(children: [
                    Image.asset(moLogo(context), width: 56, height: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: false, icon: Icon(Icons.light_mode_outlined), label: Text('Light')),
                          ButtonSegment(value: true, icon: Icon(Icons.dark_mode_outlined), label: Text('Dark')),
                        ],
                        selected: {s.dark},
                        onSelectionChanged: (v) => s.update(() => s.dark = v.first),
                      ),
                    ),
                  ]),
                ]),
                _Section('Privacy & Control', Icons.shield_outlined, [
                  for (final e in _perms.entries) _permRow(e.key, e.value.$1),
                  _SwitchRow(Icons.history_rounded, 'History mode',
                      'Save chats on this device (no server) and let MO remember the conversation. Off = every question stands alone and nothing is saved',
                      s.historyOn, (v) => s.update(() => s.historyOn = v)),
                ]),
                _Section('About', Icons.info_outline_rounded, [
                  const Text('MO · Human Robot Assistant', style: TextStyle(fontWeight: FontWeight.w600)),
                  Text('Built by MO11, a Zanzibari from Tanzania. Started in 2026.',
                      style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65))),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => launchUrl(Uri.parse('https://molittle.fourbrothers.online'), mode: LaunchMode.externalApplication),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('molittle.fourbrothers.online'),
                    ),
                  ),
                ]),
              ];
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: sections.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) => Reveal(index: i, child: sections[i]),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _powerCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MoCard(
      child: Row(children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: s.enabled ? cs.primary.withValues(alpha: 0.18) : Colors.grey.withValues(alpha: 0.18),
          ),
          child: Icon(Icons.power_settings_new_rounded, color: s.enabled ? cs.primary : Colors.grey),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('MO Assistant', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            Text(s.enabled ? 'On, ready to help' : 'Off, MO will not reply',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
          ]),
        ),
        BounceSwitch(value: s.enabled, onChanged: (v) => s.update(() => s.enabled = v)),
      ]),
    );
  }

  Widget _bgPermRow(String name, IconData icon, String why) {
    final ok = _status[name]?.isGranted ?? false;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 34),
      child: Row(children: [
        Icon(icon, size: 20, color: cs.onSurface.withValues(alpha: 0.7)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: const TextStyle(fontSize: 14)),
            Text(why, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
          ]),
        ),
        ok
            ? Icon(Icons.check_circle_rounded, color: cs.primary)
            : TextButton(onPressed: () => _ask(name), child: const Text('Allow')),
      ]),
    );
  }

  Widget _permRow(String name, IconData icon) {
    final st = _status[name];
    final ok = st?.isGranted ?? false;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(icon, size: 22, color: cs.onSurface.withValues(alpha: 0.7)),
        const SizedBox(width: 12),
        Expanded(child: Text(name)),
        ok
            ? Icon(Icons.check_circle_rounded, color: cs.primary)
            : TextButton(onPressed: () => _ask(name), child: const Text('Allow')),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.icon, this.children);
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MoCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary, letterSpacing: 0.3)),
        ]),
        const SizedBox(height: 14),
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 14),
          children[i],
        ],
      ]),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice(this.label, this.options, this.value, this.onChanged, {this.labels});
  final Map<String, String>? labels;
  final String label, value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6))),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 6, children: [
        for (final o in options)
          ChoiceChip(
            label: Text(labels?[o] ?? o[0].toUpperCase() + o.substring(1)),
            selected: o == value,
            showCheckmark: false,
            selectedColor: cs.primary,
            labelStyle: TextStyle(color: o == value ? MoColors.navy : cs.onSurface),
            onSelected: (_) => onChanged(o),
          ),
      ]),
    ]);
  }
}

class _SaveField extends StatefulWidget {
  const _SaveField({required this.controller, required this.label, required this.onSave, this.secret = false});
  final TextEditingController controller;
  final String label;
  final VoidCallback onSave;
  final bool secret;
  @override
  State<_SaveField> createState() => _SaveFieldState();
}

class _SaveFieldState extends State<_SaveField> {
  late bool _hide = widget.secret;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: widget.controller,
      obscureText: _hide,
      autocorrect: false,
      enableSuggestions: !widget.secret,
      onSubmitted: (_) => widget.onSave(),
      decoration: InputDecoration(
        labelText: widget.label,
        filled: true,
        fillColor: cs.onSurface.withValues(alpha: 0.05),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
          if (widget.secret)
            IconButton(
              icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
              onPressed: () => setState(() => _hide = !_hide),
            ),
          IconButton(icon: Icon(Icons.check_rounded, color: cs.primary), onPressed: widget.onSave),
        ]),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow(this.icon, this.title, this.subtitle, this.value, this.onChanged);
  final IconData icon;
  final String title, subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 22, color: cs.onSurface.withValues(alpha: 0.7)),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title),
          Text(subtitle, style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
        ]),
      ),
      BounceSwitch(value: value, onChanged: onChanged),
    ]);
  }
}
