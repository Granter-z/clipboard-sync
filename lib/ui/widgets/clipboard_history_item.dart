import 'package:flutter/material.dart';
import '../../models/clipboard_item.dart';

class ClipboardHistoryItem extends StatelessWidget {
  final ClipboardItem item;

  const ClipboardHistoryItem({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = item.contentType == ClipboardContentType.image;
    final timeStr = _formatTime(item.timestamp);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isImage
              ? Colors.blue.withValues(alpha: 0.2)
              : Colors.amber.withValues(alpha: 0.2),
          child: Icon(
            isImage ? Icons.image : Icons.text_fields,
            color: isImage ? Colors.blue : Colors.amber,
          ),
        ),
        title: Text(
          isImage ? '图片' : item.displayText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Row(
          children: [
            Text(
              timeStr,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '来自: ${item.sourceDeviceName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${time.month}/${time.day} ${time.hour}:${time.minute.toString().padLeft(2, '0')}';
  }
}
