enum ConnectionStatus { disconnected, connecting, connected }

class DiscoveredDevice {
  final String id;
  final String name;
  final String host;
  final int port;
  final String platform;
  final ConnectionStatus status;
  final DateTime lastSeen;
  final List<String> capabilities;

  DiscoveredDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.platform = 'unknown',
    this.status = ConnectionStatus.disconnected,
    DateTime? lastSeen,
    this.capabilities = const ['text', 'image'],
  }) : lastSeen = lastSeen ?? DateTime.now();

  DiscoveredDevice copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? platform,
    ConnectionStatus? status,
    DateTime? lastSeen,
    List<String>? capabilities,
  }) {
    return DiscoveredDevice(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      platform: platform ?? this.platform,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      capabilities: capabilities ?? this.capabilities,
    );
  }
}
