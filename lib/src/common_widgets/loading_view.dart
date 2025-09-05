import 'package:flutter/material.dart';

/// 画面中央にスピナーとメッセージを表示する簡易ローディングビュー。
class LoadingView extends StatelessWidget {
  final String message;
  final Color? spinnerColor;
  final TextStyle? textStyle;
  final double spacing;

  const LoadingView({
    super.key,
    required this.message,
    this.spinnerColor,
    this.textStyle,
    this.spacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: spinnerColor ?? theme.colorScheme.primary,
          ),
          SizedBox(height: spacing),
          Text(
            message,
            textAlign: TextAlign.center,
            style: textStyle ?? theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
