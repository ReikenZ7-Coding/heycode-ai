import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to Hermes Agent's OpenAI-style API on the user's server.
class HermesClient {
  HermesClient({required this.baseUrl, required this.apiKey, http.Client? client}) : _client = client ?? http.Client();

  /// Example: https://1-2-3-4.sslip.io/v1
  final String baseUrl;
  final String apiKey;
  final http.Client _client;

  Uri _uri(String path) {
    final base = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    return Uri.parse('$base$path');
  }

  Map<String, String> get _headers => {'Authorization': 'Bearer $apiKey', 'Content-Type': 'application/json'};

  /// Quick check used by the settings screen.
  Future<void> checkConnection() async {
    final res = await _client.get(_uri('/models'), headers: _headers).timeout(const Duration(seconds: 15));
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw ApiException('The server rejected the private key.');
    }
    if (res.statusCode != 200) {
      throw ApiException('Server answered with error ${res.statusCode}.');
    }
  }

  /// Sends the whole conversation and yields the reply as it streams in.
  Stream<String> chat(List<ChatMessage> history) async* {
    final request = http.Request('POST', _uri('/chat/completions'))
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'model': 'hermes-agent',
        'stream': true,
        'messages': [for (final m in history) m.toApi()],
      });

    final http.StreamedResponse res;
    try {
      // Agent tasks can take minutes before the first word arrives.
      res = await _client.send(request).timeout(const Duration(minutes: 10));
    } on TimeoutException {
      throw ApiException('The server took too long to answer.');
    }

    if (res.statusCode != 200) {
      final body = await res.stream.bytesToString();
      if (res.statusCode == 401 || res.statusCode == 403) {
        throw ApiException('The server rejected the private key. Check Settings.');
      }
      throw ApiException('Server error ${res.statusCode}: ${_shorten(body)}');
    }

    final contentType = res.headers['content-type'] ?? '';
    if (!contentType.contains('text/event-stream')) {
      // Server ignored streaming and sent one JSON answer.
      final body = await res.stream.bytesToString();
      yield _contentOf(jsonDecode(body), streaming: false);
      return;
    }

    final lines = res.stream.transform(utf8.decoder).transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') break;
      final piece = _contentOf(jsonDecode(data), streaming: true);
      if (piece.isNotEmpty) yield piece;
    }
  }

  static String _contentOf(dynamic json, {required bool streaming}) {
    if (json is! Map || json['choices'] is! List || (json['choices'] as List).isEmpty) {
      return '';
    }
    final choice = (json['choices'] as List).first as Map;
    final part = streaming ? choice['delta'] : choice['message'];
    if (part is Map && part['content'] is String) return part['content'] as String;
    return '';
  }

  static String _shorten(String s) => s.length > 200 ? '${s.substring(0, 200)}…' : s;

  void close() => _client.close();
}
