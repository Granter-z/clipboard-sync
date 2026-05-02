import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
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
          hash: _hashData(base64Data),
        ),
      ];
    }

    final chunkId = _hashData(base64Data);
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

  static String _hashData(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16);
  }
}

class ClipboardServiceAndroid implements ClipboardService {
  static ClipboardServiceAndroid? _instance;
  factory ClipboardServiceAndroid._() {
    _instance ??= ClipboardServiceAndroid._internal();
    return _instance!;
  }
  ClipboardServiceAndroid._internal();

  static const _channel = MethodChannel(AppConstants.channelName);

  @override
  Future<String?> readText() async {
    try {
      return await _channel.invokeMethod<String>('readText');
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> writeText(String text) async {
    try {
      await _channel.invokeMethod('writeText', {'text': text});
    } catch (e) {
      // Write failed
    }
  }

  @override
  Future<Uint8List?> readImage() async {
    try {
      final base64 = await _channel.invokeMethod<String>('readImage');
      if (base64 == null) return null;
      return base64Decode(base64);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> writeImage(Uint8List imageBytes) async {
    try {
      final base64 = base64Encode(imageBytes);
      await _channel.invokeMethod('writeImage', {'data': base64});
    } catch (e) {
      // Write failed
    }
  }

  // Not used - Service sends directly to relay server
  @override
  Stream<ClipboardChangeEvent> get clipboardChanges =>
      const Stream.empty();

  @override
  Future<void> startMonitoring() async {
    try {
      await _channel.invokeMethod('startMonitoring');
    } catch (e) {
      // ignore
    }
  }

  @override
  Future<void> stopMonitoring() async {
    try {
      await _channel.invokeMethod('stopMonitoring');
    } catch (e) {
      // ignore
    }
  }
}

class ClipboardServiceWindows implements ClipboardService {
  static ClipboardServiceWindows? _instance;
  factory ClipboardServiceWindows._() {
    _instance ??= ClipboardServiceWindows._internal();
    return _instance!;
  }
  ClipboardServiceWindows._internal() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static const _channel = MethodChannel(AppConstants.channelName);
  final StreamController<ClipboardChangeEvent> _eventController =
      StreamController<ClipboardChangeEvent>.broadcast();

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onClipboardChanged') {
      try {
        final Map<dynamic, dynamic> event =
            call.arguments as Map<dynamic, dynamic>;
        _eventController.add(ClipboardChangeEvent(
          type: event['type'] as String,
          data: event['data'] as String,
        ));
      } catch (e) {
        // Event parsing failed
      }
    }
  }

  @override
  Future<String?> readText() async {
    try {
      return await _channel.invokeMethod<String>('readText');
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> writeText(String text) async {
    try {
      await _channel.invokeMethod('writeText', text);
    } catch (e) {
      // Write failed
    }
  }

  @override
  Future<Uint8List?> readImage() async {
    try {
      final base64 = await _channel.invokeMethod<String>('readImage');
      if (base64 == null) return null;
      return base64Decode(base64);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> writeImage(Uint8List imageBytes) async {
    try {
      final base64 = base64Encode(imageBytes);
      await _channel.invokeMethod('writeImage', base64);
    } catch (e) {
      // Write failed
    }
  }

  @override
  Stream<ClipboardChangeEvent> get clipboardChanges => _eventController.stream;

  @override
  Future<void> startMonitoring() async {
    try {
      await _channel.invokeMethod('startMonitoring');
    } catch (e) {
      // Start monitoring failed
    }
  }

  @override
  Future<void> stopMonitoring() async {
    try {
      await _channel.invokeMethod('stopMonitoring');
    } catch (e) {
      // Stop monitoring failed
    }
  }
}
