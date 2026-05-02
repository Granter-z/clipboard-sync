import 'package:flutter/material.dart';
import 'services/sync_service.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/settings_screen.dart';

class ClipboardSyncApp extends StatelessWidget {
  final SyncService syncService;

  const ClipboardSyncApp({super.key, required this.syncService});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Clipboard Sync',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: HomeScreen(syncService: syncService),
      routes: {
        '/settings': (context) => SettingsScreen(syncService: syncService),
      },
    );
  }
}
