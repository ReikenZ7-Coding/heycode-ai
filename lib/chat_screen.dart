import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'models.dart';
import 'settings_screen.dart';
import 'storage.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.storage});

  final Storage storage;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final List<Conversation> _conversations = widget.storage.loadConversations();
  Conversation? _current;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _current = _conversations.isEmpty ? null : _conversations.first;
    if (!widget.storage.isConfigured) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSettings());
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => SettingsScreen(storage: widget.storage)));
    setState(() {});
  }

  void _newChat() => setState(() {
    _current = null;
    _error = null;
  });

  Future<void> _deleteChat(Conversation c) async {
    setState(() {
      _conversations.remove(c);
      if (_current == c) _current = null;
    });
    await widget.storage.saveConversations(_conversations);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    if (!widget.storage.isConfigured) {
      await _openSettings();
      return;
    }

    var convo = _current;
    if (convo == null) {
      convo = Conversation(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: text.length > 40 ? '${text.substring(0, 40)}…' : text,
      );
      _conversations.insert(0, convo);
    }
    final reply = ChatMessage(role: Role.assistant, text: '');
    setState(() {
      _current = convo;
      _error = null;
      _sending = true;
      convo!.messages.add(ChatMessage(role: Role.user, text: text));
      _input.clear();
    });
    _scrollToEnd();

    final client = HermesClient(baseUrl: widget.storage.serverUrl, apiKey: widget.storage.apiKey);
    final history = List<ChatMessage>.of(convo.messages);
    try {
      setState(() => convo!.messages.add(reply));
      await for (final piece in client.chat(history)) {
        setState(() => reply.text += piece);
        _scrollToEnd();
      }
      if (reply.text.isEmpty) throw ApiException('The server sent an empty answer.');
    } catch (e) {
      setState(() {
        convo!.messages.remove(reply);
        _error = e.toString();
      });
    } finally {
      client.close();
      convo.updated = DateTime.now();
      _conversations
        ..remove(convo)
        ..insert(0, convo);
      await widget.storage.saveConversations(_conversations);
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _current?.messages ?? const <ChatMessage>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(_current?.title ?? 'HeyCode AI', overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: 'New chat', icon: const Icon(Icons.add_comment_outlined), onPressed: _newChat),
          IconButton(tooltip: 'Settings', icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
        ],
      ),
      drawer: _ChatList(
        conversations: _conversations,
        current: _current,
        onOpen: (c) {
          setState(() => _current = c);
          Navigator.of(context).pop();
          _scrollToEnd();
        },
        onNew: () {
          _newChat();
          Navigator.of(context).pop();
        },
        onDelete: _deleteChat,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? const _EmptyState()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      itemCount: messages.length,
                      itemBuilder: (_, i) => _Bubble(
                        message: messages[i],
                        thinking: _sending && i == messages.length - 1 && messages[i].text.isEmpty,
                      ),
                    ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            _Composer(controller: _input, sending: _sending, onSend: _send),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            Text('What can I do for you?', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Your own agent on your server, thinking with GLM-5.3.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.thinking});

  final ChatMessage message;
  final bool thinking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.role == Role.user;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        child: GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: message.text));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: mine ? scheme.primaryContainer : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: thinking
                ? Text(
                    'Thinking…',
                    style: TextStyle(color: scheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                  )
                : SelectableText(message.text),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.sending, required this.onSend});

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: CallbackShortcuts(
              // Enter sends on Windows; Shift+Enter adds a new line.
              bindings: {const SingleActivator(LogicalKeyboardKey.enter): onSend},
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 6,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  hintText: 'Message your AI…',
                  border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24))),
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: sending ? null : onSend,
            icon: sending
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.arrow_upward),
          ),
        ],
      ),
    );
  }
}

class _ChatList extends StatelessWidget {
  const _ChatList({
    required this.conversations,
    required this.current,
    required this.onOpen,
    required this.onNew,
    required this.onDelete,
  });

  final List<Conversation> conversations;
  final Conversation? current;
  final ValueChanged<Conversation> onOpen;
  final VoidCallback onNew;
  final ValueChanged<Conversation> onDelete;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            ListTile(leading: const Icon(Icons.add), title: const Text('New chat'), onTap: onNew),
            const Divider(height: 1),
            Expanded(
              child: conversations.isEmpty
                  ? const Center(child: Text('No chats yet'))
                  : ListView(
                      children: [
                        for (final c in conversations)
                          ListTile(
                            selected: c == current,
                            title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => onOpen(c),
                            trailing: IconButton(
                              tooltip: 'Delete chat',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => onDelete(c),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
