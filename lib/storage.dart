import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// Server settings and chat history, saved on the device only.
class Storage {
  Storage(this._prefs);

  static Future<Storage> open() async => Storage(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _serverKey = 'server_url';
  static const _apiKeyKey = 'api_key';
  static const _conversationsKey = 'conversations';

  String get serverUrl => _prefs.getString(_serverKey) ?? '';
  String get apiKey => _prefs.getString(_apiKeyKey) ?? '';
  bool get isConfigured => serverUrl.isNotEmpty && apiKey.isNotEmpty;

  Future<void> saveServer(String url, String key) async {
    await _prefs.setString(_serverKey, url.trim());
    await _prefs.setString(_apiKeyKey, key.trim());
  }

  List<Conversation> loadConversations() {
    final raw = _prefs.getString(_conversationsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return [for (final c in list) Conversation.fromJson(c as Map<String, dynamic>)]
        ..sort((a, b) => b.updated.compareTo(a.updated));
    } catch (_) {
      // Corrupt history should never stop the app from opening.
      return [];
    }
  }

  Future<void> saveConversations(List<Conversation> conversations) =>
      _prefs.setString(_conversationsKey, jsonEncode([for (final c in conversations) c.toJson()]));
}
