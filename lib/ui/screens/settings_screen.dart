import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/sync_service.dart';

class SettingsScreen extends StatefulWidget {
  final SyncService syncService;

  const SettingsScreen({super.key, required this.syncService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _relayController = TextEditingController();
  bool _isLoading = true;
  bool _isRelayConnected = false;
  bool _isConnecting = false;
  StreamSubscription? _relayConnSub;
  StreamSubscription? _relayErrorSub;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    // 监听中继连接状态变化
    _relayConnSub = widget.syncService.onRelayConnectionChanged.listen((connected) {
      if (mounted) setState(() => _isRelayConnected = connected);
    });
    // 监听中继错误信息
    _relayErrorSub = widget.syncService.onRelayError.listen((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error), backgroundColor: Colors.red),
        );
      }
    });
  }

  Future<void> _loadSettings() async {
    final name = await widget.syncService.getDeviceName();
    final relayUrl = await widget.syncService.getRelayUrl();
    if (mounted) {
      setState(() {
        _nameController.text = name ?? '未知设备';
        _relayController.text = relayUrl ?? '';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    // 退出时自动保存设备名称
    final name = _nameController.text.trim();
    if (name.isNotEmpty) {
      widget.syncService.setDeviceName(name);
    }
    _nameController.dispose();
    _relayController.dispose();
    _relayConnSub?.cancel();
    _relayErrorSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Device name
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('设备名称',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            hintText: '输入设备名称',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.devices),
                          ),
                          onSubmitted: (value) {
                            if (value.trim().isNotEmpty) {
                              widget.syncService
                                  .setDeviceName(value.trim());
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('设备名称已更新')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Cloud Relay settings
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('云端中继',
                                style: theme.textTheme.titleSmall),
                            const Spacer(),
                            if (_isRelayConnected)
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _relayController,
                          decoration: const InputDecoration(
                            hintText: 'wss://clipboard-sync-production-f31f.up.railway.app',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.cloud),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '输入中继服务器地址后点击连接，'
                          '手机和电脑在不同网络也能同步',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                icon: _isConnecting
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.link),
                                label: Text(_isConnecting ? '连接中...' : '连接中继'),
                                onPressed: _isConnecting ? null : _connectRelay,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.link_off),
                                label: const Text('断开'),
                                onPressed: _disconnectRelay,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // About section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('关于',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        _aboutRow('版本', '1.0.0'),
                        _aboutRow('局域网模式', 'UDP广播 + WebSocket'),
                        _aboutRow('云端模式', 'WebSocket中继'),
                        _aboutRow('端口', '9876 (局域网) / 443 (Railway)'),
                        _aboutRow('支持内容', '文字 + 图片'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // How it works
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('工作模式',
                            style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        Text(
                          '【局域网模式】\n'
                          '同一WiFi下自动发现，无需配置\n\n'
                          '【云端中继模式】\n'
                          '手机和电脑在不同网络也能用\n'
                          '将 server/ 目录部署到 Railway 等平台\n'
                          '在上方输入 wss:// 开头的地址即可连接',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _connectRelay() async {
    final url = _relayController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入中继服务器地址')),
      );
      return;
    }

    setState(() => _isConnecting = true);

    try {
      final connected = await widget.syncService
          .connectRelay(url)
          .timeout(const Duration(seconds: 25));
      if (mounted) {
        if (connected) {
          setState(() => _isRelayConnected = true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已连接中继服务器')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('连接失败，请检查地址和网络'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('连接超时，服务器无响应，请检查地址是否正确'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接出错: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _disconnectRelay() async {
    await widget.syncService.disconnectRelay();
    setState(() => _isRelayConnected = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已断开中继服务器')),
      );
    }
  }

  Widget _aboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
