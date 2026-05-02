import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/clipboard_item.dart';
import '../models/device_info_model.dart';
import '../services/sync_service.dart';

class SyncProvider extends ChangeNotifier {
  final SyncService _syncService;

  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  List<DiscoveredDevice> _discoveredDevices = [];
  List<ClipboardItem> _clipboardHistory = [];
  bool _isSyncing = false;
  bool _isInitialized = false;

  ConnectionStatus get connectionStatus => _connectionStatus;
  List<DiscoveredDevice> get discoveredDevices => _discoveredDevices;
  List<ClipboardItem> get clipboardHistory => _clipboardHistory;
  bool get isSyncing => _isSyncing;
  bool get isInitialized => _isInitialized;

  // Subscriptions
  StreamSubscription? _statusSub;
  StreamSubscription? _devicesSub;
  StreamSubscription? _historySub;
  StreamSubscription? _syncStateSub;

  SyncProvider(this._syncService);

  Future<void> initialize() async {
    await _syncService.initialize();

    _statusSub = _syncService.onConnectionStatusChanged.listen((status) {
      _connectionStatus = status;
      notifyListeners();
    });

    _devicesSub = _syncService.onDevicesChanged.listen((devices) {
      _discoveredDevices = devices;
      notifyListeners();
    });

    _historySub = _syncService.onClipboardHistory.listen((item) {
      _clipboardHistory.insert(0, item);
      if (_clipboardHistory.length > 50) {
        _clipboardHistory = _clipboardHistory.sublist(0, 50);
      }
      notifyListeners();
    });

    _syncStateSub = _syncService.onSyncStateChanged.listen((syncing) {
      _isSyncing = syncing;
      notifyListeners();
    });

    _isInitialized = true;
    notifyListeners();
  }

  Future<void> startSync() async {
    await _syncService.startSync();
    _isSyncing = true;
    notifyListeners();
  }

  Future<void> stopSync() async {
    await _syncService.stopSync();
    _isSyncing = false;
    notifyListeners();
  }

  Future<void> setDeviceName(String name) async {
    await _syncService.setDeviceName(name);
  }

  Future<String?> getDeviceName() => _syncService.getDeviceName();

  @override
  void dispose() {
    _statusSub?.cancel();
    _devicesSub?.cancel();
    _historySub?.cancel();
    _syncStateSub?.cancel();
    _syncService.dispose();
    super.dispose();
  }
}
