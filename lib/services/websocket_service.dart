import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../core/constants.dart';
import '../models/sync_message.dart';

class PeerConnection {
  final String deviceId;
  String? deviceName;
  final WebSocket socket;
  int? lastSequence;

  PeerConnection({
    required this.deviceId,
    this.deviceName,
    required this.socket,
    this.lastSequence,
  });
}

class WebSocketService {
  HttpServer? _server;
  bool _isServerRunning = false;

  final Map<String, PeerConnection> _connectedPeers = {};
  final StreamController<MapEntry<String, SyncMessage>> _messageController =
      StreamController<MapEntry<String, SyncMessage>>.broadcast();
  final StreamController<String> _peerConnectedController =
      StreamController<String>.broadcast();
  final StreamController<String> _peerDisconnectedController =
      StreamController<String>.broadcast();

  Stream<MapEntry<String, SyncMessage>> get onMessage =>
      _messageController.stream;
  Stream<String> get onPeerConnected => _peerConnectedController.stream;
  Stream<String> get onPeerDisconnected =>
      _peerDisconnectedController.stream;

  Map<String, PeerConnection> get connectedPeers =>
      Map.unmodifiable(_connectedPeers);
  int get peerCount => _connectedPeers.length;

  Future<void> startServer({int port = AppConstants.wsPort}) async {
    if (_isServerRunning) return;
    _isServerRunning = true;

    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      // 不 await 整个循环，让它在后台运行
      _server!.listen((request) {
        if (request.uri.path == AppConstants.wsPath) {
          try {
            WebSocketTransformer.upgrade(request).then((ws) {
              _handleConnection(ws);
            });
          } catch (e) {
            // Upgrade failed
          }
        }
      });
    } catch (e) {
      _isServerRunning = false;
    }
  }

  void _handleConnection(WebSocket ws) {
    ws.cast<String>().listen(
      (messageStr) {
        _processMessage(ws, messageStr);
      },
      onDone: () {
        _removeConnection(ws);
      },
      onError: (error) {
        _removeConnection(ws);
      },
    );
  }

  void _processMessage(WebSocket ws, String messageStr) {
    try {
      final json = jsonDecode(messageStr) as Map<String, dynamic>;
      final msg = SyncMessage.fromJson(json);

      if (msg.isHandshake) {
        final deviceId = msg.senderId;
        _connectedPeers[deviceId] = PeerConnection(
          deviceId: deviceId,
          deviceName: msg.senderName,
          socket: ws,
        );
        _peerConnectedController.add(deviceId);
      } else if (msg.isClipboardSync) {
        // Find which peer sent this
        final peerEntry = _connectedPeers.entries.firstWhere(
          (e) => e.value.socket == ws,
          orElse: () => MapEntry('', PeerConnection(
            deviceId: '',
            socket: ws,
          )),
        );
        if (peerEntry.key.isNotEmpty) {
          _messageController.add(MapEntry(peerEntry.key, msg));
        }
      }
    } catch (e) {
      // Invalid message
    }
  }

  void _removeConnection(WebSocket ws) {
    final keys = _connectedPeers.entries
        .where((e) => e.value.socket == ws)
        .map((e) => e.key)
        .toList();
    for (final key in keys) {
      _connectedPeers.remove(key);
      _peerDisconnectedController.add(key);
    }
  }

  Future<void> connectToPeer(String host, int port,
      {required SyncMessage handshakeMsg}) async {
    try {
      final uri = Uri.parse('ws://$host:$port${AppConstants.wsPath}');
      final ws = await WebSocket.connect(uri.toString());

      ws.cast<String>().listen(
        (messageStr) {
          _processMessage(ws, messageStr);
        },
        onDone: () {
          _removeConnection(ws);
        },
        onError: (error) {
          _removeConnection(ws);
        },
      );

      // Send handshake
      ws.add(handshakeMsg.toJsonString());

      _connectedPeers[handshakeMsg.senderId] = PeerConnection(
        deviceId: handshakeMsg.senderId,
        deviceName: handshakeMsg.senderName,
        socket: ws,
      );
      _peerConnectedController.add(handshakeMsg.senderId);
    } catch (e) {
      // Connection failed
    }
  }

  Future<void> sendToPeer(String deviceId, SyncMessage message) async {
    final peer = _connectedPeers[deviceId];
    if (peer != null) {
      try {
        peer.socket.add(message.toJsonString());
      } catch (e) {
        // Send failed
      }
    }
  }

  Future<void> broadcastToAllPeers(SyncMessage message) async {
    final jsonStr = message.toJsonString();
    for (final peer in _connectedPeers.values) {
      try {
        peer.socket.add(jsonStr);
      } catch (e) {
        // Broadcast to peer failed
      }
    }
  }

  Future<void> stopServer() async {
    _isServerRunning = false;
    for (final peer in _connectedPeers.values) {
      try {
        await peer.socket.close();
      } catch (_) {}
    }
    _connectedPeers.clear();
    await _server?.close(force: true);
    _server = null;
  }

  void dispose() {
    stopServer();
    _messageController.close();
    _peerConnectedController.close();
    _peerDisconnectedController.close();
  }
}
