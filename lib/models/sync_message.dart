import 'dart:convert';

class ChunkInfo {
  final int totalChunks;
  final int chunkIndex;
  final String chunkId;
  final int chunkSize;

  ChunkInfo({
    required this.totalChunks,
    required this.chunkIndex,
    required this.chunkId,
    required this.chunkSize,
  });

  Map<String, dynamic> toJson() => {
        'totalChunks': totalChunks,
        'chunkIndex': chunkIndex,
        'chunkId': chunkId,
        'chunkSize': chunkSize,
      };

  factory ChunkInfo.fromJson(Map<String, dynamic> json) => ChunkInfo(
        totalChunks: json['totalChunks'] as int,
        chunkIndex: json['chunkIndex'] as int,
        chunkId: json['chunkId'] as String,
        chunkSize: json['chunkSize'] as int,
      );
}

class Payload {
  final String contentType;
  final String data;
  final String encoding;
  final int size;
  final String? hash;
  final ChunkInfo? chunks;

  Payload({
    required this.contentType,
    required this.data,
    this.encoding = 'utf-8',
    required this.size,
    this.hash,
    this.chunks,
  });

  Map<String, dynamic> toJson() => {
        'contentType': contentType,
        'data': data,
        'encoding': encoding,
        'size': size,
        if (hash != null) 'hash': hash,
        if (chunks != null) 'chunks': chunks!.toJson(),
      };

  factory Payload.fromJson(Map<String, dynamic> json) => Payload(
        contentType: json['contentType'] as String,
        data: json['data'] as String,
        encoding: json['encoding'] as String? ?? 'utf-8',
        size: json['size'] as int,
        hash: json['hash'] as String?,
        chunks: json['chunks'] != null
            ? ChunkInfo.fromJson(json['chunks'] as Map<String, dynamic>)
            : null,
      );
}

class SyncMessage {
  final String type;
  final int version;
  final String senderId;
  final String? senderName;
  final int? sequence;
  final int? timestamp;
  final Payload? payload;

  SyncMessage({
    required this.type,
    this.version = 1,
    required this.senderId,
    this.senderName,
    this.sequence,
    this.timestamp,
    this.payload,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'version': version,
        'senderId': senderId,
        if (senderName != null) 'senderName': senderName,
        if (sequence != null) 'sequence': sequence,
        if (timestamp != null) 'timestamp': timestamp,
        if (payload != null) 'payload': payload!.toJson(),
      };

  factory SyncMessage.fromJson(Map<String, dynamic> json) {
    return SyncMessage(
      type: json['type'] as String,
      version: json['version'] as int? ?? 1,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String?,
      sequence: json['sequence'] as int?,
      timestamp: json['timestamp'] as int?,
      payload: json['payload'] != null
          ? Payload.fromJson(json['payload'] as Map<String, dynamic>)
          : null,
    );
  }

  String toJsonString() => jsonEncode(toJson());

  static SyncMessage handshake({
    required String deviceId,
    required String deviceName,
    required String platform,
    List<String> capabilities = const ['text', 'image'],
  }) {
    return SyncMessage(
      type: 'handshake',
      senderId: deviceId,
      senderName: deviceName,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: Payload(
        contentType: 'handshake_info',
        data: jsonEncode({
          'deviceName': deviceName,
          'platform': platform,
          'capabilities': capabilities,
        }),
        encoding: 'utf-8',
        size: 0,
      ),
    );
  }

  static SyncMessage clipboardSync({
    required String senderId,
    required String? senderName,
    required int sequence,
    required Payload payload,
  }) {
    return SyncMessage(
      type: 'clipboard_sync',
      senderId: senderId,
      senderName: senderName,
      sequence: sequence,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      payload: payload,
    );
  }

  bool get isHandshake => type == 'handshake';
  bool get isClipboardSync => type == 'clipboard_sync';
  bool get isImage => payload?.contentType == 'image';
  bool get isImageChunk => payload?.contentType == 'image_chunk';
  bool get isText => payload?.contentType == 'text';
}
