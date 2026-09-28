import 'package:flutter/material.dart';
import '../core/settings_store.dart';
import '../core/theme.dart';
import '../services/chat_controller.dart';
import '../widgets/common.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.chat, required this.settings});
  final ChatController chat;
  final SettingsStore settings;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  int _lastCount = 0;

  ChatController get chat => widget.chat;

  @override
  void initState() {
    super.initState();
    chat.addListener(_onChat);
  }

  @override
  void dispose() {
    chat.removeListener(_onChat);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChat() {
    if (chat.listening && chat.partial.isNotEmpty) _text.text = chat.partial;
    if (!chat.listening && chat.partial.isEmpty && chat.messages.length != _lastCount) _text.clear();
    if (chat.messages.length != _lastCount || chat.thinking) {
      _lastCount = chat.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent + 80,
              duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
        }
      });
    }
  }

  void _submit() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    chat.send(t);
  }

  Future<void> _mic() async {
    final ok = await chat.toggleMic();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Microphone unavailable. Allow it in Settings → Privacy & Control.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListenableBuilder(
            listenable: Listenable.merge([chat, widget.settings]),
            builder: (context, _) {
              final s = widget.settings;
              return Column(
                children: [
                  Expanded(
                    child: chat.messages.isEmpty && !chat.thinking
                        ? _Welcome(off: !s.enabled)
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                            itemCount: chat.messages.length + (chat.thinking ? 1 : 0),
                            itemBuilder: (_, i) => i == chat.messages.length
                                ? const _Bubble(key: ValueKey('typing'), role: 'assistant', child: TypingDots())
                                : _Bubble(
                                    key: ValueKey(i),
                                    role: chat.messages[i].role,
                                    child: Text(chat.messages[i].text, style: const TextStyle(fontSize: 16, height: 1.4)),
                                  ),
                          ),
                  ),
                  if (!s.enabled)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('MO is switched off. Turn it on in Settings.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
                    ),
                  _InputBar(
                    controller: _text,
                    enabled: s.enabled,
                    listening: chat.listening,
                    hint: chat.listening ? 'Listening…' : 'Ask MO anything',
                    onSend: _submit,
                    onMic: _mic,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.off});
  final bool off;
  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    final part = h < 12 ? 'morning' : h < 18 ? 'afternoon' : 'evening';
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Reveal(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Opacity(
              opacity: off ? 0.4 : 1,
              child: Image.asset(moLogo(context), width: 190, height: 190),
            ),
            const SizedBox(height: 8),
            Text('Welcome back, Little',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Good $part. What can I do for you?',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
          ]),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.role, required this.child});
  final String role;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = role == 'user';
    final err = role == 'error';
    final bg = user
        ? cs.primary
        : err
            ? cs.error.withValues(alpha: 0.15)
            : moPanel(context);
    final fg = user ? MoColors.navy : cs.onSurface;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      builder: (_, v, c) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset((user ? 24 : -24) * (1 - v), 0), child: c),
      ),
      child: Align(
        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8 > 560 ? 560 : MediaQuery.sizeOf(context).width * 0.8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(user ? 20 : 4),
              bottomRight: Radius.circular(user ? 4 : 20),
            ),
          ),
          child: DefaultTextStyle.merge(style: TextStyle(color: fg), child: child),
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.enabled,
    required this.listening,
    required this.hint,
    required this.onSend,
    required this.onMic,
  });
  final TextEditingController controller;
  final bool enabled, listening;
  final String hint;
  final VoidCallback onSend, onMic;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 4, 6, 4),
        decoration: BoxDecoration(
          color: moPanel(context),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: listening ? cs.primary : Theme.of(context).dividerColor, width: listening ? 1.5 : 1),
          boxShadow: listening ? [BoxShadow(color: cs.primary.withValues(alpha: 0.35), blurRadius: 20)] : null,
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              decoration: InputDecoration(hintText: hint, hintStyle: TextStyle(color: cs.onSurface.withValues(alpha: 0.45))),
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (_, __) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: controller.text.trim().isNotEmpty && !listening
                  ? IconButton.filled(
                      key: const ValueKey('send'),
                      onPressed: enabled ? onSend : null,
                      icon: const Icon(Icons.arrow_upward_rounded),
                      style: IconButton.styleFrom(backgroundColor: cs.primary, foregroundColor: MoColors.navy),
                    )
                  : IconButton.filled(
                      key: const ValueKey('mic'),
                      onPressed: enabled ? onMic : null,
                      icon: Icon(listening ? Icons.stop_rounded : Icons.mic_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: listening ? cs.primary : cs.primary.withValues(alpha: 0.16),
                        foregroundColor: listening ? MoColors.navy : cs.primary,
                      ),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}
