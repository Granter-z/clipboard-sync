class AppConstants {
  AppConstants._();

  static const String appName = 'Clipboard Sync';
  static const String serviceType = '_clipboard-sync._tcp';
  static const int wsPort = 9876;
  static const String wsPath = '/ws';

  static const int chunkThreshold = 512 * 1024; // 512KB
  static const int chunkSize = 100 * 1024; // 100KB per chunk
  static const int maxRecentHashes = 100;
  static const Duration writeDebounceDuration = Duration(milliseconds: 500);
  static const Duration reconnectionDelay = Duration(seconds: 3);
  static const Duration discoveryInterval = Duration(seconds: 5);

  static const String channelName = 'com.clipsync/clipboard';
  static const String eventChannelName = 'com.clipsync/clipboard/events';
}
