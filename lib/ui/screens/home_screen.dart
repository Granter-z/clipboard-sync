import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/device_info_model.dart';
import '../../services/sync_service.dart';
import '../widgets/connection_status_badge.dart';
import '../widgets/device_card.dart';
import '../widgets/clipboard_history_item.dart';
import '../../models/clipboard_item.dart';

class HomeScreen extends StatefulWidget {
  final SyncService syncService;

  const HomeScreen({super.key, required this.syncService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  List<DiscoveredDevice> _devices = [];
  List<ClipboardItem> _history = [];
  bool _isSyncing = false;
  bool _isInitialized = false;

  StreamSubscription? _statusSub;
  StreamSubscription? _devicesSub;
  StreamSubscription? _historySub;
  StreamSubscription? _syncStateSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await widget.syncService.initialize();
    await widget.syncService.startSync();

    _statusSub = widget.syncService.onConnectionStatusChanged.listen((status) {
      if (mounted) setState(() => _connectionStatus = status);
    });

    _devicesSub = widget.syncService.onDevicesChanged.listen((devices) {
      if (mounted) setState(() => _devices = devices);
    });

    _historySub = widget.syncService.onClipboardHistory.listen((item) {
      if (mounted) {
        setState(() {
          _history.insert(0, item);
          if (_history.length > 50) _history = _history.sublist(0, 50);
        });
      }
    });

    _syncStateSub = widget.syncService.onSyncStateChanged.listen((syncing) {
      if (mounted) setState(() => _isSyncing = syncing);
    });

    if (mounted) {
      setState(() {
        _isInitialized = true;
        _isSyncing = true;
        _connectionStatus = widget.syncService.currentStatus;
        _devices = widget.syncService.knownDevices;
      });
    }
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _devicesSub?.cancel();
    _historySub?.cancel();
    _syncStateSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Clipboard Sync'),
        actions: [
          IconButton(
            icon: Icon(
              _isSyncing ? Icons.sync : Icons.sync_disabled,
              color: _isSyncing ? Colors.blue : Colors.grey,
            ),
            onPressed: () async {
              if (_isSyncing) {
                await widget.syncService.stopSync();
              } else {
                await widget.syncService.startSync();
              }
            },
            tooltip: _isSyncing ? '停止同步' : '开始同步',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: _isInitialized
          ? RefreshIndicator(
              onRefresh: () async {
                await widget.syncService.startSync();
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: 16),
                children: [
                  // Connection status section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ConnectionStatusBadge(status: _connectionStatus),
                        const SizedBox(height: 4),
                        Text(
                          _connectionStatus == ConnectionStatus.connected
                              ? '设备已连接，剪贴板同步中'
                              : _connectionStatus == ConnectionStatus.connecting
                                  ? '正在搜索设备...'
                                  : '等待设备连接',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Connected/Running status card
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Icon(
                              _isSyncing
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: _isSyncing ? Colors.green : Colors.red,
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isSyncing ? '同步运行中' : '同步已停止',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  Text(
                                    _isSyncing
                                        ? '复制内容将自动同步到已连接设备'
                                        : '点击同步按钮恢复',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Discovered devices
                  if (_devices.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        '已发现设备',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    ..._devices.map((device) => DeviceCard(device: device)),
                    const SizedBox(height: 8),
                  ],

                  // Clipboard history header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        Text(
                          '剪贴板历史',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        if (_history.isNotEmpty)
                          TextButton(
                            onPressed: () {
                              setState(() => _history.clear());
                            },
                            child: const Text('清空'),
                          ),
                      ],
                    ),
                  ),

                  if (_history.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.content_copy,
                              size: 48,
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.4),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '暂无剪贴板记录',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '复制内容将自动显示在这里',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._history.map(
                      (item) => ClipboardHistoryItem(item: item),
                    ),
                ],
              ),
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}
