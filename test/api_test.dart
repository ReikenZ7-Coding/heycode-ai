import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:heycode_ai/api.dart';
import 'package:heycode_ai/models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final history = [ChatMessage(role: Role.user, text: 'hi')];

  test('streams the reply piece by piece', () async {
    late http.Request seen;
    final client = MockClient.streaming((request, bodyStream) async {
      seen = request as http.Request;
      final sse = [
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': 'Hel'},
            },
          ],
        })}',
        '',
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': 'lo'},
            },
          ],
        })}',
        '',
        'data: [DONE]',
        '',
      ].join('\n');
      return http.StreamedResponse(Stream.value(utf8.encode(sse)), 200, headers: {'content-type': 'text/event-stream'});
    });
    final api = HermesClient(baseUrl: 'https://x.sslip.io/v1/', apiKey: 'k', client: client);

    expect(await api.chat(history).join(), 'Hello');
    expect(seen.url.toString(), 'https://x.sslip.io/v1/chat/completions');
    expect(seen.headers['Authorization'], 'Bearer k');
    expect(jsonDecode(seen.body)['messages'], [
      {'role': 'user', 'content': 'hi'},
    ]);
  });

  test('accepts a plain JSON answer', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': 'Hello'},
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    final api = HermesClient(baseUrl: 'https://x/v1', apiKey: 'k', client: client);
    expect(await api.chat(history).join(), 'Hello');
  });

  test('explains a wrong key', () async {
    final client = MockClient((_) async => http.Response('nope', 401));
    final api = HermesClient(baseUrl: 'https://x/v1', apiKey: 'bad', client: client);
    expect(api.chat(history).join(), throwsA(isA<ApiException>()));
  });

  test('conversations survive a save and load', () {
    final c = Conversation(
      id: '1',
      title: 't',
      messages: [ChatMessage(role: Role.assistant, text: 'a')],
    );
    final back = Conversation.fromJson(jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>);
    expect(back.messages.single.text, 'a');
    expect(back.messages.single.role, Role.assistant);
  });
}
