import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/sync_message.dart';

class RelayPeer {
  final String deviceId;
  final String deviceName;
  final String platform;

  RelayPeer({
    required this.deviceId,
    required this.deviceName,
    this.platform = 'unknown',
  });
}

class RelayService {
  WebSocket? _ws;
  String? _relayUrl;
  String? _deviceId;
  String? _deviceName;
  String? _platform;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;

  final StreamController<RelayPeer> _peerJoinedController =
      StreamController<RelayPeer>.broadcast();
  final StreamController<String> _peerLeftController =
      StreamController<String>.broadcast();
  final StreamController<MapEntry<String, SyncMessage>> _messageController =
      StreamController<MapEntry<String, SyncMessage>>.broadcast();
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  Stream<RelayPeer> get onPeerJoined => _peerJoinedController.stream;
  Stream<String> get onPeerLeft => _peerLeftController.stream;
  Stream<MapEntry<String, SyncMessage>> get onMessage =>
      _messageController.stream;
  Stream<bool> get onConnectionChanged => _connectionController.stream;
  Stream<String> get onError => _errorController.stream;

  bool get isConnected => _isConnected;

  /// 连接中继服务器，返回 true 表示连接成功，false 表示连接失败
  Future<bool> connect({
    required String relayUrl,
    required String deviceId,
    required String deviceName,
    required String platform,
  }) async {
    _relayUrl = relayUrl;
    _deviceId = deviceId;
    _deviceName = deviceName;
    _platform = platform;
    _shouldReconnect = true;

    return await _doConnect();
  }

  Future<bool> _doConnect() async {
    if (_relayUrl == null) return false;

    try {
      final uri = Uri.parse(_relayUrl!);

      // 先做健康检查，验证手机能否访问服务器
      final healthScheme = uri.scheme == 'wss' ? 'https' : 'http';
      final healthHost = uri.host;
      final healthPort = uri.hasPort ? ':${uri.port}' : '';
      final healthUri = Uri.parse('$healthScheme://$healthHost$healthPort/health');
      try {
        final healthClient = HttpClient();
        healthClient.badCertificateCallback = (_, _, _) => true;
        healthClient.connectionTimeout = const Duration(seconds: 10);
        final healthReq = await healthClient.getUrl(healthUri);
        final healthResp = await healthReq.close();
        if (healthResp.statusCode != 200) {
          _errorController.add('服务器异常 (HTTP ${healthResp.statusCode})');
          healthClient.close();
          _scheduleReconnect();
          return false;
        }
        healthClient.close();
      } on SocketException catch (e) {
        _errorController.add('网络不可达: ${e.message}');
        _scheduleReconnect();
        return false;
      } on TimeoutException {
        _errorController.add('健康检查超时，请检查手机是否能访问该地址');
        _scheduleReconnect();
        return false;
      } catch (e) {
        _errorController.add('健康检查异常: $e');
        _scheduleReconnect();
        return false;
      }

      // 健康检查通过，尝试 WebSocket 连接（先用自定义 HttpClient，失败则回退）
      try {
        final httpClient = HttpClient();
        httpClient.badCertificateCallback =
            (X509Certificate cert, String host, int port) => true;
        httpClient.connectionTimeout = const Duration(seconds: 15);
        _ws = await WebSocket.connect(
          uri.toString(),
          customClient: httpClient,
        ).timeout(const Duration(seconds: 20));
      } catch (_) {
        // 回退到默认 WebSocket.connect
        _ws = await WebSocket.connect(
          uri.toString(),
        ).timeout(const Duration(seconds: 20));
      }

      _isConnected = true;
      _connectionController.add(true);

      // Send handshake
      final handshake = SyncMessage.handshake(
        deviceId: _deviceId!,
        deviceName: _deviceName!,
        platform: _platform!,
      );
      _ws!.add(handshake.toJsonString());

      _ws!.listen(
        (data) {
          String messageStr;
          if (data is List<int>) {
            messageStr = utf8.decode(data);
          } else if (data is String) {
            messageStr = data;
          } else {
            return;
          }

          try {
            final json = jsonDecode(messageStr) as Map<String, dynamic>;
            final type = json['type'] as String?;

            if (type == 'peer_joined') {
              final peer = RelayPeer(
                deviceId: json['senderId'] as String,
                deviceName: json['senderName'] as String? ?? 'Unknown',
                platform: json['platform'] as String? ?? 'unknown',
              );
              _peerJoinedController.add(peer);
            } else if (type == 'peer_left') {
              _peerLeftController.add(json['senderId'] as String);
            } else if (type == 'peer_list') {
              final peers = json['peers'] as List<dynamic>? ?? [];
              for (final p in peers) {
                final peer = RelayPeer(
                  deviceId: p['senderId'] as String,
                  deviceName: p['senderName'] as String? ?? 'Unknown',
                  platform: p['platform'] as String? ?? 'unknown',
                );
                _peerJoinedController.add(peer);
              }
            } else if (type == 'clipboard_sync') {
              final msg = SyncMessage.fromJson(json);
              _messageController.add(MapEntry(msg.senderId, msg));
            }
          } catch (e) {
            // Invalid message
          }
        },
        onDone: () {
          _isConnected = false;
          _connectionController.add(false);
          _scheduleReconnect();
        },
        onError: (error) {
          _isConnected = false;
          _connectionController.add(false);
          _errorController.add('连接断开: $error');
          _scheduleReconnect();
        },
      );

      return true;
    } catch (e) {
      _isConnected = false;
      _connectionController.add(false);
      final errorMsg = '连接失败: $e';
      _errorController.add(errorMsg);
      _scheduleReconnect();
      return false;
    }
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _doConnect();
    });
  }

  Future<void> sendMessage(SyncMessage message) async {
    if (_ws != null && _isConnected) {
      try {
        _ws!.add(message.toJsonString());
      } catch (e) {
        // Send failed
      }
    }
  }

  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isConnected = false;
    _connectionController.add(false);
    await _ws?.close();
    _ws = null;
  }

  void dispose() {
    disconnect();
    _peerJoinedController.close();
    _peerLeftController.close();
    _messageController.close();
    _connectionController.close();
    _errorController.close();
  }
}
