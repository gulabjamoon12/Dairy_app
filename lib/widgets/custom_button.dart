import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color? backgroundColor;
  final bool isOutlined;
  final double? width;

  const CustomButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.backgroundColor,
    this.isOutlined = false,
    this.width,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = backgroundColor ?? theme.colorScheme.primary;

    final iconWidget = icon != null ? Icon(icon) : const SizedBox.shrink();
    
    const double minTouchHeight = 48;
    Widget button = isOutlined
        ? OutlinedButton.icon(
            onPressed: onPressed,
            icon: iconWidget,
            label: Text(text),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, minTouchHeight),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              foregroundColor: theme.colorScheme.primary,
              side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.4)),
            ),
          )
        : ElevatedButton.icon(
            onPressed: onPressed,
            icon: iconWidget,
            label: Text(text),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, minTouchHeight),
              backgroundColor: bgColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 0,
            ),
          );

    if (width != null) {
      button = SizedBox(width: width, child: button);
    }

    return button;
  }
}
