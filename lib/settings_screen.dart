import 'package:flutter/material.dart';

import 'api.dart';
import 'storage.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.storage});

  final Storage storage;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final _url = TextEditingController(text: widget.storage.serverUrl);
  late final _key = TextEditingController(text: widget.storage.apiKey);
  bool _hideKey = true;
  bool _testing = false;
  String? _status;
  bool _ok = false;

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    final url = _url.text.trim();
    final key = _key.text.trim();
    if (!url.startsWith('https://') && !url.startsWith('http://')) {
      setState(() {
        _ok = false;
        _status = 'The server address should start with https://';
      });
      return;
    }
    setState(() {
      _testing = true;
      _status = null;
    });
    final client = HermesClient(baseUrl: url, apiKey: key);
    try {
      await client.checkConnection();
      await widget.storage.saveServer(url, key);
      setState(() {
        _ok = true;
        _status = 'Connected and saved.';
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _status = 'Could not connect: $e';
      });
    } finally {
      client.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Your AI server', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Copy these from ~/heycode-app-settings.txt on your Oracle server.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: 'https://1-2-3-4.sslip.io/v1',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            obscureText: _hideKey,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: 'Private key',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_hideKey ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _hideKey = !_hideKey),
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _testing ? null : _testAndSave,
            icon: _testing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering),
            label: Text(_testing ? 'Testing…' : 'Test and save'),
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!, style: TextStyle(color: _ok ? Colors.green : scheme.error)),
          ],
          const SizedBox(height: 24),
          Text(
            'In China you may need your VPN switched on to reach the server.',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
