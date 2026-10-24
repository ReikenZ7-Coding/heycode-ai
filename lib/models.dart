enum Role { user, assistant }

class ChatMessage {
  ChatMessage({required this.role, required this.text, DateTime? at}) : at = at ?? DateTime.now();

  final Role role;
  String text;
  final DateTime at;

  Map<String, String> toApi() => {'role': role.name, 'content': text};

  Map<String, dynamic> toJson() => {'role': role.name, 'text': text, 'at': at.toIso8601String()};

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
    role: Role.values.byName(json['role'] as String),
    text: json['text'] as String,
    at: DateTime.parse(json['at'] as String),
  );
}

class Conversation {
  Conversation({required this.id, required this.title, List<ChatMessage>? messages, DateTime? updated})
    : messages = messages ?? [],
      updated = updated ?? DateTime.now();

  final String id;
  String title;
  final List<ChatMessage> messages;
  DateTime updated;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'updated': updated.toIso8601String(),
    'messages': [for (final m in messages) m.toJson()],
  };

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    id: json['id'] as String,
    title: json['title'] as String,
    updated: DateTime.parse(json['updated'] as String),
    messages: [for (final m in json['messages'] as List) ChatMessage.fromJson(m as Map<String, dynamic>)],
  );
}
