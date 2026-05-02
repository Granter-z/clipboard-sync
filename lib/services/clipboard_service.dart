import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import '../core/constants.dart';
import '../models/clipboard_item.dart';
import '../models/sync_message.dart';

abstract class ClipboardService {
  Future<String?> readText();
  Future<void> writeText(String text);
  Future<Uint8List?> readImage();
  Future<void> writeImage(Uint8List imageBytes);
  Stream<ClipboardChangeEvent> get clipboardChanges;
  Future<void> startMonitoring();
  Future<void> stopMonitoring();

  factory ClipboardService() {
    if (Platform.isAndroid) {
      return ClipboardServiceAndroid._();
    } else if (Platform.isWindows) {
      return ClipboardServiceWindows._();
    }
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }
}

class ImageProcessor {
  static const int chunkThreshold = 512 * 1024;
  static const int chunkSize = 100 * 1024;

  static List<Payload> createImagePayloads(String base64Data) {
    if (base64Data.length <= chunkThreshold) {
      return [
        Payload(
          contentType: 'image',
          data: base64Data,
          encoding: 'base64',
          size: base64Data.length,
          hash: _simpleHash(base64Data),
        ),
      ];
    }

    final chunkId = _simpleHash(base64Data);
    final totalChunks = (base64Data.length / chunkSize).ceil();
    final payloads = <Payload>[];

    for (int i = 0; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize > base64Data.length)
          ? base64Data.length
          : start + chunkSize;
      payloads.add(Payload(
        contentType: 'image_chunk',
        data: base64Data.substring(start, end),
        encoding: 'base64',
        size: end - start,
        hash: chunkId,
        chunks: ChunkInfo(
          totalChunks: totalChunks,
          chunkIndex: i,
          chunkId: chunkId,
          chunkSize: chunkSize,
        ),
      ));
    }
    return payloads;
  }

  static String reassembleChunks(List<Payload> chunks) {
    chunks.sort((a, b) =>
        (a.chunks?.chunkIndex ?? 0).compareTo(b.chunks?.chunkIndex ?? 0));
    return chunks.map((c) => c.data).join();
  }

  static String _simpleHash(String input) {
    return base64Encode(utf8.encode(input));
  }
}

// Android Clipboard Service
class ClipboardServiceAndroid implements ClipboardService {
  static final ClipboardServiceAndroid _instance = ClipboardServiceAndroid._();
  factory ClipboardServiceAndroid._() => _instance;

  static const _channel = MethodChannel(AppConstants.channelName);
  static const _eventChannel = EventChannel(AppConstants.eventChannelName);

  @override
  Future<String?> readText() async {
    return await _channel.invokeMethod<String>('readText');
  }

  @override
  Future<void> writeText(String text) async {
    await _channel.invokeMethod('writeText', {'text': text});
  }

  @override
  Future<Uint8List?> readImage() async {
    final base64 = await _channel.invokeMethod<String>('readImage');
    if (base64 == null) return null;
    return base64Decode(base64);
  }

  @override
  Future<void> writeImage(Uint8List imageBytes) async {
    final base64 = base64Encode(imageBytes);
    await _channel.invokeMethod('writeImage', {'data': base64});
  }

  @override
  Stream<ClipboardChangeEvent> get clipboardChanges {
    return _eventChannel.receiveBroadcastStream().map((event) {
      final map = event as Map<dynamic, dynamic>;
      return ClipboardChangeEvent(
        type: map['type'] as String,
        data: map['data'] as String,
      );
    });
  }

  @override
  Future<void> startMonitoring() async {
    await _channel.invokeMethod('startMonitoring');
  }

  @override
  Future<void> stopMonitoring() async {
    await _channel.invokeMethod('stopMonitoring');
  }
}

// Windows Clipboard Service
class ClipboardServiceWindows implements ClipboardService {
  static final ClipboardServiceWindows _instance =
      ClipboardServiceWindows._();
  factory ClipboardServiceWindows._() => _instance;

  static const _channel = MethodChannel(AppConstants.channelName);
  static const _eventChannel = EventChannel(AppConstants.eventChannelName);

  @override
  Future<String?> readText() async {
    return await _channel.invokeMethod<String>('readText');
  }

  @override
  Future<void> writeText(String text) async {
    await _channel.invokeMethod('writeText', text);
  }

  @override
  Future<Uint8List?> readImage() async {
    final base64 = await _channel.invokeMethod<String>('readImage');
    if (base64 == null) return null;
    return base64Decode(base64);
  }

  @override
  Future<void> writeImage(Uint8List imageBytes) async {
    final base64 = base64Encode(imageBytes);
    await _channel.invokeMethod('writeImage', base64);
  }

  @override
  Stream<ClipboardChangeEvent> get clipboardChanges {
    return _eventChannel.receiveBroadcastStream().map((event) {
      final map = event as Map<dynamic, dynamic>;
      return ClipboardChangeEvent(
        type: map['type'] as String,
        data: map['data'] as String,
      );
    });
  }

  @override
  Future<void> startMonitoring() async {
    await _channel.invokeMethod('startMonitoring');
  }

  @override
  Future<void> stopMonitoring() async {
    await _channel.invokeMethod('stopMonitoring');
  }
}
