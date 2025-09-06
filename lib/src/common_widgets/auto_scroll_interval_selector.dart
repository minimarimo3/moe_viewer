import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

/// 自動スクロール間隔を設定するためのコンパクトなウィジェット
class AutoScrollIntervalSelector extends StatefulWidget {
  final int currentValue; // 現在の値（1/10秒単位）
  final ValueChanged<int> onChanged;

  const AutoScrollIntervalSelector({
    super.key,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  State<AutoScrollIntervalSelector> createState() =>
      _AutoScrollIntervalSelectorState();
}

class _AutoScrollIntervalSelectorState
    extends State<AutoScrollIntervalSelector> {
  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours時間$minutes分$seconds秒';
    } else if (minutes > 0) {
      return '$minutes分$seconds秒';
    } else {
      return '$seconds秒';
    }
  }

  void _showTimerPickerDialog() {
    // 現在の値をDurationに変換
    final milliseconds = (widget.currentValue * 100);
    Duration currentDuration = Duration(milliseconds: milliseconds);

    showDialog(
      context: context,
      builder: (context) => _TimerPickerDialog(
        initialDuration: currentDuration,
        onChanged: (duration) {
          // Durationを1/10秒単位の整数に変換
          final intervalValue = (duration.inMilliseconds / 100).round();
          // 最小値制限（0.5秒 = 5）
          final clampedValue = intervalValue < 5 ? 5 : intervalValue;
          widget.onChanged(clampedValue);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final milliseconds = (widget.currentValue * 100);
    final currentDuration = Duration(milliseconds: milliseconds);

    return Row(
      children: [
        Expanded(
          child: Text(
            '現在の画像自動スクロール間隔: ${_formatDuration(currentDuration)}',
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton.icon(
          onPressed: _showTimerPickerDialog,
          icon: const Icon(Icons.timer, size: 18),
          label: const Text('時間を変更'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 36),
          ),
        ),
      ],
    );
  }
}

/// タイマーピッカーダイアログ
class _TimerPickerDialog extends StatefulWidget {
  final Duration initialDuration;
  final ValueChanged<Duration> onChanged;

  const _TimerPickerDialog({
    required this.initialDuration,
    required this.onChanged,
  });

  @override
  State<_TimerPickerDialog> createState() => _TimerPickerDialogState();
}

class _TimerPickerDialogState extends State<_TimerPickerDialog> {
  late Duration _selectedDuration;

  @override
  void initState() {
    super.initState();
    _selectedDuration = widget.initialDuration;
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours時間$minutes分$seconds秒';
    } else if (minutes > 0) {
      return '$minutes分$seconds秒';
    } else {
      return '$seconds秒';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自動スクロール間隔を設定'),
      content: SizedBox(
        height: 280,
        width: double.maxFinite,
        child: Column(
          children: [
            // 説明テキスト
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '時間・分・秒を個別に設定できます。30分間隔なども簡単に設定可能です。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // タイマーピッカー
            Container(
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: CupertinoTimerPicker(
                mode: CupertinoTimerPickerMode.hms,
                initialTimerDuration: _selectedDuration,
                onTimerDurationChanged: (duration) {
                  setState(() {
                    _selectedDuration = duration;
                  });
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: () {
            widget.onChanged(_selectedDuration);
            Navigator.of(context).pop();
          },
          child: Text('設定 (${_formatDuration(_selectedDuration)})'),
        ),
      ],
    );
  }
}
