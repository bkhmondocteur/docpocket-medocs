import 'package:flutter/material.dart';
import '../../models/stock_alert_level.dart';

/// Badge visuel sémantique d'alerte médicale (Rouge, Orange, Vert)
class AlertBadge extends StatelessWidget {
  final StockAlertLevel level;
  final bool compact;
  final String? customText;

  const AlertBadge({
    super.key,
    required this.level,
    this.compact = false,
    this.customText,
  });

  @override
  Widget build(BuildContext context) {
    final text = customText ?? level.label;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: level.backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: level.color.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            level.icon,
            size: compact ? 13 : 16,
            color: level.color,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: level.color,
              fontSize: compact ? 11 : 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
