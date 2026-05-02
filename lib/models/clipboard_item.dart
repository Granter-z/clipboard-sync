enum ClipboardContentType { text, image }

class ClipboardItem {
  final String id;
  final ClipboardContentType contentType;
  final String data;
  final String? imageMimeType;
  final int size;
  final DateTime timestamp;
  final String sourceDeviceId;
  final String sourceDeviceName;

  ClipboardItem({
    required this.id,
    required this.contentType,
    required this.data,
    this.imageMimeType,
    required this.size,
    required this.timestamp,
    required this.sourceDeviceId,
    required this.sourceDeviceName,
  });

  String get displayText {
    if (contentType == ClipboardContentType.text) {
      return data.length > 100 ? '${data.substring(0, 100)}...' : data;
    }
    return '[图片] ${imageMimeType ?? "PNG"}';
  }
}

class ClipboardChangeEvent {
  final String type;
  final String data;

  ClipboardChangeEvent({required this.type, required this.data});

  ClipboardContentType get contentType =>
      type == 'image' ? ClipboardContentType.image : ClipboardContentType.text;
}
