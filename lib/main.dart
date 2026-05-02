import 'package:flutter/material.dart';
import 'app.dart';
import 'services/sync_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final syncService = SyncService();
  runApp(ClipboardSyncApp(syncService: syncService));
}
