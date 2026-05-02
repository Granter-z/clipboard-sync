import 'package:flutter/material.dart';
import '../../models/device_info_model.dart';

class ConnectionStatusBadge extends StatelessWidget {
  final ConnectionStatus status;
  final double size;

  const ConnectionStatusBadge({
    super.key,
    required this.status,
    this.size = 12,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ConnectionStatus.connected => Colors.green,
      ConnectionStatus.connecting => Colors.orange,
      ConnectionStatus.disconnected => Colors.red,
    };

    final label = switch (status) {
      ConnectionStatus.connected => '已连接',
      ConnectionStatus.connecting => '连接中...',
      ConnectionStatus.disconnected => '未连接',
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
