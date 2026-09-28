import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/settings_store.dart';
import '../core/theme.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.settings});
  final SettingsStore settings;
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

  // ignore: deprecated_member_use
  static final _perms = <String, (IconData, Permission)>{
    'Microphone': (Icons.mic_none_rounded, Permission.microphone),
    'Notifications': (Icons.notifications_none_rounded, Permission.notification),
    'Location': (Icons.location_on_outlined, Permission.location),
    // ignore: deprecated_member_use
    'Calendar': (Icons.event_outlined, Permission.calendar),
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
    for (final c in [_wake, _loc, _groq, _weather, _news]) {
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
    if (mounted) setState(() {});
  }

  Future<void> _ask(String name) async {
    final p = _perms[name]!.$2;
    final st = await p.request();
    if (st.isPermanentlyDenied) await openAppSettings();
    await _refresh();
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
                  _Choice('Voice', const ['female', 'male'], s.voiceGender, (v) => s.update(() => s.voiceGender = v)),
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
                  _SwitchRow(Icons.home_outlined, 'Smart home', 'Plugin slot, not connected yet', s.smartHomeOn, (v) => s.update(() => s.smartHomeOn = v)),
                  _SwitchRow(Icons.music_note_outlined, 'Music', 'Plugin slot, not connected yet', s.musicOn, (v) => s.update(() => s.musicOn = v)),
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
                  _SwitchRow(Icons.visibility_off_outlined, 'No history mode',
                      'Each question is answered on its own; nothing is remembered', s.noHistory, (v) => s.update(() => s.noHistory = v)),
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
  const _Choice(this.label, this.options, this.value, this.onChanged);
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
            label: Text(o[0].toUpperCase() + o.substring(1)),
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
