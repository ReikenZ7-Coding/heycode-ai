import 'package:flutter/material.dart';

import 'chat_screen.dart';
import 'storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  runApp(HeyCodeApp(storage: storage));
}

class HeyCodeApp extends StatelessWidget {
  const HeyCodeApp({super.key, required this.storage});

  final Storage storage;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2F6FED);
    return MaterialApp(
      title: 'HeyCode AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: seed, brightness: Brightness.dark),
      home: ChatScreen(storage: storage),
    );
  }
}
