import 'package:flutter/material.dart';
import '../../models/device_info_model.dart';

class DeviceCard extends StatelessWidget {
  final DiscoveredDevice device;
  final VoidCallback? onTap;

  const DeviceCard({
    super.key,
    required this.device,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = device.status == ConnectionStatus.connected;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isConnected
              ? Colors.green.withValues(alpha: 0.2)
              : Colors.grey.withValues(alpha: 0.2),
          child: Icon(
            device.platform == 'android'
                ? Icons.phone_android
                : Icons.computer,
            color: isConnected ? Colors.green : Colors.grey,
          ),
        ),
        title: Text(
          device.name,
          style: theme.textTheme.titleSmall,
        ),
        subtitle: Text(
          '${device.host}:${device.port}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: isConnected ? Colors.green : Colors.grey,
            shape: BoxShape.circle,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
