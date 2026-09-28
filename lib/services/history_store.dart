import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'groq_service.dart';

class Conversation {
  Conversation({required this.id, this.title = 'New chat', DateTime? updated, List<Turn>? turns})
      : updated = updated ?? DateTime.now(),
        turns = turns ?? [];
  final String id;
  String title;
  DateTime updated;
  final List<Turn> turns;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updated': updated.millisecondsSinceEpoch,
        'turns': turns.map((t) => t.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: '${j['id']}',
        title: '${j['title']}',
        updated: DateTime.fromMillisecondsSinceEpoch(j['updated'] as int),
        turns: (j['turns'] as List).map((e) => Turn.fromJson(Map<String, dynamic>.from(e as Map))).toList(),
      );
}

/// Serverless chat history: everything stays on the device (SharedPreferences).
class HistoryStore extends ChangeNotifier {
  static const _key = 'history_v1';
  static const maxConversations = 200;
  static const maxTurns = 300;

  SharedPreferences? _p;
  final List<Conversation> items = []; // newest first

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final raw = _p!.getString(_key);
    if (raw == null) return;
    try {
      items
        ..clear()
        ..addAll((jsonDecode(raw) as List).map((e) => Conversation.fromJson(Map<String, dynamic>.from(e as Map))));
      items.sort((a, b) => b.updated.compareTo(a.updated));
    } catch (_) {
      items.clear(); // corrupted data: start clean instead of crashing
    }
  }

  Future<void> _write() async {
    _p ??= await SharedPreferences.getInstance();
    await _p!.setString(_key, jsonEncode(items.map((c) => c.toJson()).toList()));
  }

  Future<void> save(Conversation c) async {
    if (c.turns.length > maxTurns) c.turns.removeRange(0, c.turns.length - maxTurns);
    items.removeWhere((x) => x.id == c.id);
    items.insert(0, c);
    if (items.length > maxConversations) items.removeRange(maxConversations, items.length);
    notifyListeners();
    await _write();
  }

  Future<void> delete(String id) async {
    items.removeWhere((x) => x.id == id);
    notifyListeners();
    await _write();
  }

  Future<void> clear() async {
    items.clear();
    notifyListeners();
    await _write();
  }
}
