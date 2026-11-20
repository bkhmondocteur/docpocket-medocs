import 'package:flutter/material.dart';

/// Gros bouton tactile médical haute visibilité pensé pour une manipulation
/// ultra rapide et sans erreur entre deux consultations de patients
class BigTouchButton extends StatelessWidget {
  final String label;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final Color textColor;
  final VoidCallback? onPressed;
  final bool isSecondary;
  final double height;

  const BigTouchButton({
    super.key,
    required this.label,
    this.subtitle,
    required this.icon,
    required this.color,
    this.textColor = Colors.white,
    required this.onPressed,
    this.isSecondary = false,
    this.height = 68.0,
  });

  @override
  Widget build(BuildContext context) {
    if (isSecondary) {
      return SizedBox(
        height: height,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: color, width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: color),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: color.withOpacity(0.8),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: textColor,
          elevation: 3,
          shadowColor: color.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: textColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: textColor.withOpacity(0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
