import 'package:flutter/material.dart';
import '../core/settings_store.dart';
import '../core/theme.dart';
import '../services/chat_controller.dart';
import 'chat_screen.dart';
import 'settings_screen.dart';

/// Icon-only navigation. Bottom bar on phones, side rail on tablets/foldables.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.settings, required this.chat});
  final SettingsStore settings;
  final ChatController chat;
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  static const _icons = [
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, 'Chat'),
    (Icons.tune_rounded, Icons.tune_rounded, 'Settings'),
  ];

  Widget _page() => _i == 0
      ? ChatScreen(key: const ValueKey('chat'), chat: widget.chat, settings: widget.settings)
      : SettingsScreen(key: const ValueKey('settings'), settings: widget.settings);

  // Chat fades, Settings slides in from the right.
  Widget _transition(Widget child, Animation<double> anim) {
    if (child.key == const ValueKey('settings')) {
      return SlideTransition(
        position: Tween(begin: const Offset(0.25, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: FadeTransition(opacity: anim, child: child),
      );
    }
    return FadeTransition(opacity: anim, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final body = AnimatedSwitcher(
      duration: const Duration(milliseconds: 420),
      switchInCurve: Curves.easeOut,
      transitionBuilder: (c, a) => _transition(c, a),
      child: _page(),
    );
    if (wide) {
      return Scaffold(
        body: Row(children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var n = 0; n < _icons.length; n++) ...[
                  _NavIcon(icons: _icons[n], selected: _i == n, onTap: () => setState(() => _i = n)),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
          ),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(60, 4, 60, 10),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: moPanel(context),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              for (var n = 0; n < _icons.length; n++)
                _NavIcon(icons: _icons[n], selected: _i == n, onTap: () => setState(() => _i = n)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({required this.icons, required this.selected, required this.onTap});
  final (IconData, IconData, String) icons;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: icons.$3,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.primary.withValues(alpha: 0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: AnimatedScale(
            scale: selected ? 1.15 : 1,
            duration: const Duration(milliseconds: 350),
            curve: Curves.elasticOut,
            child: Icon(selected ? icons.$2 : icons.$1,
                color: selected ? cs.primary : cs.onSurface.withValues(alpha: 0.55)),
          ),
        ),
      ),
    );
  }
}
