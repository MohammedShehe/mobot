import 'package:flutter/material.dart';
import '../core/settings_store.dart';
import '../services/chat_controller.dart';
import '../services/history_store.dart';
import '../widgets/common.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.chat, required this.settings, required this.onOpen});
  final ChatController chat;
  final SettingsStore settings;
  final VoidCallback onOpen; // switch back to the chat tab

  static const _m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _when(DateTime d) =>
      '${d.day} ${_m[d.month - 1]} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete all history?'),
        content: const Text('Every saved conversation on this device will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete all')),
        ],
      ),
    );
    if (ok == true) await chat.clearHistory();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListenableBuilder(
            listenable: Listenable.merge([chat.history, settings]),
            builder: (context, _) {
              final items = chat.history.items;
              return Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                  child: Row(children: [
                    Expanded(child: Text('History', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600))),
                    IconButton(
                      tooltip: 'New chat',
                      icon: const Icon(Icons.add_comment_outlined),
                      onPressed: () {
                        chat.newChat();
                        onOpen();
                      },
                    ),
                    IconButton(
                      tooltip: 'Delete all',
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: items.isEmpty ? null : () => _confirmClear(context),
                    ),
                  ]),
                ),
                if (!settings.historyOn)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text('History mode is off, so new chats are not being saved. Turn it on in Settings → Privacy & Control.',
                        style: TextStyle(fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6))),
                  ),
                Expanded(
                  child: items.isEmpty
                      ? Center(child: Text('No saved chats yet', style: TextStyle(color: cs.onSurface.withValues(alpha: 0.55))))
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (_, i) {
                            final Conversation c = items[i];
                            return Reveal(
                              index: i > 6 ? 6 : i,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  chat.open(c);
                                  onOpen();
                                },
                                child: MoCard(
                                  child: Row(children: [
                                    Icon(Icons.chat_bubble_outline_rounded, color: cs.primary, size: 22),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                        const SizedBox(height: 2),
                                        Text('${c.turns.length} messages · ${_when(c.updated)}',
                                            style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
                                      ]),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete',
                                      icon: const Icon(Icons.close_rounded, size: 20),
                                      onPressed: () => chat.deleteConversation(c.id),
                                    ),
                                  ]),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
