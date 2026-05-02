import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants.dart';
import '../models/device_info_model.dart';

class DiscoveryService {
  final Map<String, DiscoveredDevice> _discoveredDevices = {};

  RawDatagramSocket? _listenSocket;
  RawDatagramSocket? _broadcastSocket;
  String? _deviceName;
  String? _deviceId;
  String _platform = 'unknown';
  bool _isRunning = false;
  Timer? _broadcastTimer;

  static const int _discoveryPort = 9875;

  final StreamController<DiscoveredDevice> _deviceDiscoveredController =
      StreamController<DiscoveredDevice>.broadcast();
  final StreamController<String> _deviceRemovedController =
      StreamController<String>.broadcast();

  Stream<DiscoveredDevice> get onDeviceDiscovered =>
      _deviceDiscoveredController.stream;
  Stream<String> get onDeviceRemoved => _deviceRemovedController.stream;

  bool get isRunning => _isRunning;

  Future<void> start({
    required String deviceName,
    required String deviceId,
    String platform = 'unknown',
  }) async {
    if (_isRunning) return;
    _isRunning = true;
    _deviceName = deviceName;
    _deviceId = deviceId;
    _platform = platform;

    final prefs = await SharedPreferences.getInstance();
    final storedId = prefs.getString('device_id');
    if (storedId == null) {
      await prefs.setString('device_id', deviceId);
    }

    // Start listening for discovery broadcasts
    try {
      _listenSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      _listenSocket!.listen((event) {
        if (event == RawSocketEvent.read) {
          final datagram = _listenSocket!.receive();
          if (datagram != null) {
            _handleDiscoveryMessage(datagram);
          }
        }
      });
    } catch (e) {
      _isRunning = false;
      return;
    }

    // Start broadcasting presence
    try {
      _broadcastSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        0, // ephemeral port
        reuseAddress: true,
      );
    } catch (e) {
      // Broadcast socket failed, but listen socket may still work
    }

    // Broadcast every 5 seconds
    _broadcastTimer = Timer.periodic(AppConstants.discoveryInterval, (_) {
      _broadcastPresence();
    });
    _broadcastPresence();
  }

  void _handleDiscoveryMessage(Datagram datagram) {
    try {
      final message = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      final senderId = message['id'] as String;

      // Ignore self
      if (senderId == _deviceId) return;

      final device = DiscoveredDevice(
        id: senderId,
        name: message['name'] as String? ?? 'Unknown',
        host: datagram.address.address,
        port: message['port'] as int? ?? AppConstants.wsPort,
        platform: message['platform'] as String? ?? 'unknown',
        status: ConnectionStatus.disconnected,
        lastSeen: DateTime.now(),
      );

      final existing = _discoveredDevices[senderId];
      if (existing == null ||
          existing.lastSeen.isBefore(DateTime.now().subtract(const Duration(seconds: 10)))) {
        _discoveredDevices[senderId] = device;
        _deviceDiscoveredController.add(device);
      }
    } catch (_) {
      // Invalid discovery message
    }
  }

  void _broadcastPresence() {
    if (_broadcastSocket == null || _deviceName == null || _deviceId == null) return;

    final message = jsonEncode({
      'type': 'clipboard_sync_discovery',
      'id': _deviceId,
      'name': _deviceName,
      'port': AppConstants.wsPort,
      'platform': _platform,
      'version': 1,
    });

    try {
      final data = utf8.encode(message);
      _broadcastSocket!.send(
        data,
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );
    } catch (_) {
      // Broadcast failed
    }
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _broadcastSocket?.close();
    _broadcastSocket = null;
    _listenSocket?.close();
    _listenSocket = null;
    _discoveredDevices.clear();
  }

  void dispose() {
    stop();
    _deviceDiscoveredController.close();
    _deviceRemovedController.close();
  }
}
