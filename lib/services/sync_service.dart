import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/constants.dart';
import '../models/clipboard_item.dart';
import '../models/sync_message.dart';
import '../models/device_info_model.dart';
import 'clipboard_service.dart';
import 'discovery_service.dart';
import 'websocket_service.dart';
import 'relay_service.dart';

class SyncService {
  final DiscoveryService _discoveryService = DiscoveryService();
  final WebSocketService _webSocketService = WebSocketService();
  final RelayService _relayService = RelayService();
  late final ClipboardService _clipboardService;
  late final Uuid _uuid;

  String? _deviceId;
  String? _deviceName;
  String _platform = 'unknown';

  // Sync loop prevention
  bool _isOwnWrite = false;
  Timer? _writeDebounceTimer;
  final Set<String> _recentHashes = {};
  int _sequence = 0;
  final Map<String, int> _lastSequenceFromPeer = {};

  // Image chunk reassembly
  final Map<String, List<Payload>> _pendingChunks = {};

  // State
  bool _isInitialized = false;
  bool _isSyncing = true;
  final List<DiscoveredDevice> _knownDevices = [];

  final StreamController<ConnectionStatus> _connectionStatusController =
      StreamController<ConnectionStatus>.broadcast();
  final StreamController<List<DiscoveredDevice>> _devicesController =
      StreamController<List<DiscoveredDevice>>.broadcast();
  final StreamController<ClipboardItem> _clipboardHistoryController =
      StreamController<ClipboardItem>.broadcast();
  final StreamController<bool> _syncStateController =
      StreamController<bool>.broadcast();

  Stream<ConnectionStatus> get onConnectionStatusChanged =>
      _connectionStatusController.stream;
  Stream<List<DiscoveredDevice>> get onDevicesChanged =>
      _devicesController.stream;
  Stream<ClipboardItem> get onClipboardHistory =>
      _clipboardHistoryController.stream;
  Stream<bool> get onSyncStateChanged => _syncStateController.stream;

  ConnectionStatus _currentStatus = ConnectionStatus.disconnected;

  ConnectionStatus get currentStatus => _currentStatus;
  List<DiscoveredDevice> get knownDevices => List.unmodifiable(_knownDevices);
  bool get isSyncing => _isSyncing;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _uuid = const Uuid();
    _clipboardService = ClipboardService();

    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('device_id');
    if (_deviceId == null) {
      _deviceId = _uuid.v4();
      await prefs.setString('device_id', _deviceId!);
    }
    _deviceName = prefs.getString('device_name') ??
        '${Platform.isAndroid ? "Android" : "Windows"}-${_deviceId!.substring(0, 4)}';

    _platform = Platform.isAndroid ? 'android' : 'windows';

    // Listen for local clipboard changes
    _clipboardService.clipboardChanges.listen(_onLocalClipboardChanged);

    // Listen for WebSocket messages
    _webSocketService.onMessage.listen((entry) {
      _onMessageFromPeer(entry.key, entry.value);
    });

    // Listen for discovered devices
    _discoveryService.onDeviceDiscovered.listen(_onDeviceDiscovered);
    _discoveryService.onDeviceRemoved.listen(_onDeviceRemoved);

    // Listen for relay peers
    _relayService.onPeerJoined.listen((peer) {
      _onRelayPeerJoined(peer);
    });
    _relayService.onPeerLeft.listen((deviceId) {
      _onRelayPeerLeft(deviceId);
    });
    _relayService.onMessage.listen((entry) {
      _onMessageFromPeer(entry.key, entry.value);
    });
    _relayService.onConnectionChanged.listen((connected) {
      if (connected) {
        _updateConnectionStatus(ConnectionStatus.connected);
      }
    });

    _isInitialized = true;
  }

  Future<void> startSync() async {
    if (!_isInitialized) return;

    _updateConnectionStatus(ConnectionStatus.connecting);

    // Start discovery
    await _discoveryService.start(
      deviceName: _deviceName!,
      deviceId: _deviceId!,
      platform: _platform,
    );

    // Start WebSocket server
    await _webSocketService.startServer(port: AppConstants.wsPort);

    // Listen for peer connections
    _webSocketService.onPeerConnected.listen((deviceId) {
      _updateConnectionStatus(ConnectionStatus.connected);
    });

    _webSocketService.onPeerDisconnected.listen((deviceId) {
      if (_webSocketService.peerCount == 0) {
        _updateConnectionStatus(ConnectionStatus.disconnected);
      }
    });

    // Start clipboard monitoring
    await _clipboardService.startMonitoring();

    _isSyncing = true;
    _syncStateController.add(true);
  }

  Future<void> stopSync() async {
    _isSyncing = false;
    _syncStateController.add(false);

    await _clipboardService.stopMonitoring();
    await _webSocketService.stopServer();
    await _discoveryService.stop();

    _updateConnectionStatus(ConnectionStatus.disconnected);
  }

  void _onLocalClipboardChanged(ClipboardChangeEvent event) {
    if (!_isSyncing) return;
    if (_isOwnWrite) return;

    final contentHash = sha256.convert(utf8.encode(event.data)).toString();
    if (_recentHashes.contains(contentHash)) return;

    _recentHashes.add(contentHash);
    if (_recentHashes.length > AppConstants.maxRecentHashes) {
      final first = _recentHashes.first;
      _recentHashes.remove(first);
    }

    _sequence++;

    if (event.contentType == ClipboardContentType.text) {
      final msg = SyncMessage.clipboardSync(
        senderId: _deviceId!,
        senderName: _deviceName,
        sequence: _sequence,
        payload: Payload(
          contentType: 'text',
          data: event.data,
          encoding: 'utf-8',
          size: event.data.length,
          hash: contentHash,
        ),
      );
      _webSocketService.broadcastToAllPeers(msg);
      _relayService.sendMessage(msg);

      _clipboardHistoryController.add(ClipboardItem(
        id: _uuid.v4(),
        contentType: ClipboardContentType.text,
        data: event.data,
        size: event.data.length,
        timestamp: DateTime.now(),
        sourceDeviceId: _deviceId!,
        sourceDeviceName: _deviceName ?? '本机',
      ));
    } else if (event.contentType == ClipboardContentType.image) {
      final payloads = ImageProcessor.createImagePayloads(event.data);
      for (int i = 0; i < payloads.length; i++) {
        final msg = SyncMessage.clipboardSync(
          senderId: _deviceId!,
          senderName: _deviceName,
          sequence: _sequence + i,
          payload: payloads[i],
        );
        _webSocketService.broadcastToAllPeers(msg);
        _relayService.sendMessage(msg);
      }

      _clipboardHistoryController.add(ClipboardItem(
        id: _uuid.v4(),
        contentType: ClipboardContentType.image,
        data: event.data,
        size: event.data.length,
        timestamp: DateTime.now(),
        sourceDeviceId: _deviceId!,
        sourceDeviceName: _deviceName ?? '本机',
      ));
    }
  }

  void _onMessageFromPeer(String peerId, SyncMessage msg) {
    if (msg.payload == null) return;

    // Sequence check
    final lastSeq = _lastSequenceFromPeer[peerId] ?? 0;
    if (msg.sequence != null && msg.sequence! <= lastSeq) return;
    if (msg.sequence != null) {
      _lastSequenceFromPeer[peerId] = msg.sequence!;
    }

    // Hash dedup
    if (msg.payload!.hash != null && _recentHashes.contains(msg.payload!.hash)) {
      return;
    }
    if (msg.payload!.hash != null) {
      _recentHashes.add(msg.payload!.hash!);
      if (_recentHashes.length > AppConstants.maxRecentHashes) {
        final first = _recentHashes.first;
        _recentHashes.remove(first);
      }
    }

    if (msg.isImageChunk) {
      final chunkId = msg.payload!.chunks!.chunkId;
      _pendingChunks.putIfAbsent(chunkId, () => []);
      _pendingChunks[chunkId]!.add(msg.payload!);

      if (_pendingChunks[chunkId]!.length == msg.payload!.chunks!.totalChunks) {
        final completeData =
            ImageProcessor.reassembleChunks(_pendingChunks[chunkId]!);
        _pendingChunks.remove(chunkId);

        _isOwnWrite = true;
        _writeImageToClipboard(completeData, msg);
      }
    } else if (msg.isImage) {
      _isOwnWrite = true;
      _writeImageToClipboard(msg.payload!.data, msg);
    } else if (msg.isText) {
      _isOwnWrite = true;
      _writeTextToClipboard(msg.payload!.data, msg);
    }
  }

  void _writeTextToClipboard(String text, SyncMessage msg) {
    _clipboardService.writeText(text);
    _addToClipboardHistory(msg, text, ClipboardContentType.text);
    _runWriteDebounce();
  }

  void _writeImageToClipboard(String base64Data, SyncMessage msg) {
    final bytes = base64Decode(base64Data);
    _clipboardService.writeImage(bytes);
    _addToClipboardHistory(msg, base64Data, ClipboardContentType.image);
    _runWriteDebounce();
  }

  void _addToClipboardHistory(
      SyncMessage msg, String data, ClipboardContentType type) {
    _clipboardHistoryController.add(ClipboardItem(
      id: _uuid.v4(),
      contentType: type,
      data: data,
      size: data.length,
      timestamp: DateTime.now(),
      sourceDeviceId: msg.senderId,
      sourceDeviceName: msg.senderName ?? '未知设备',
    ));
  }

  void _runWriteDebounce() {
    _writeDebounceTimer?.cancel();
    _writeDebounceTimer =
        Timer(AppConstants.writeDebounceDuration, () {
      _isOwnWrite = false;
    });
  }

  void _onDeviceDiscovered(DiscoveredDevice device) {
    final existingIndex = _knownDevices.indexWhere((d) => d.id == device.id);
    if (existingIndex >= 0) {
      _knownDevices[existingIndex] = device;
    } else {
      _knownDevices.add(device);

      // Auto-connect to newly discovered device
      final handshakeMsg = SyncMessage.handshake(
        deviceId: _deviceId!,
        deviceName: _deviceName!,
        platform: _platform,
      );
      _webSocketService.connectToPeer(device.host, device.port,
          handshakeMsg: handshakeMsg);
    }
    _devicesController.add(List.from(_knownDevices));
  }

  void _onDeviceRemoved(String deviceId) {
    _knownDevices.removeWhere((d) => d.id == deviceId);
    _devicesController.add(List.from(_knownDevices));
  }

  void _onRelayPeerJoined(RelayPeer peer) {
    if (peer.deviceId == _deviceId) return;
    _updateConnectionStatus(ConnectionStatus.connected);
  }

  void _onRelayPeerLeft(String deviceId) {
    // Handle relay peer disconnect
  }

  Future<void> connectRelay(String relayUrl) async {
    if (!_isInitialized) await initialize();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('relay_url', relayUrl);

    await _relayService.connect(
      relayUrl: relayUrl,
      deviceId: _deviceId!,
      deviceName: _deviceName!,
      platform: _platform,
    );
  }

  Future<void> disconnectRelay() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('relay_url');
    await _relayService.disconnect();
  }

  Future<String?> getRelayUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('relay_url');
  }

  void _updateConnectionStatus(ConnectionStatus status) {
    _currentStatus = status;
    _connectionStatusController.add(status);
  }

  Future<void> setDeviceName(String name) async {
    _deviceName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name', name);
  }

  Future<String?> getDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_name') ?? _deviceName;
  }

  void dispose() {
    stopSync();
    _connectionStatusController.close();
    _devicesController.close();
    _clipboardHistoryController.close();
    _syncStateController.close();
    _discoveryService.dispose();
    _webSocketService.dispose();
    _relayService.dispose();
  }
}
