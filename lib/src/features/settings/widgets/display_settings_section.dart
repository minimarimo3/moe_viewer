import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../common_widgets/auto_scroll_interval_selector.dart';
import '../../../core/models/rating.dart';
import '../../../core/providers/settings_provider.dart';

class DisplaySettingsSection extends StatelessWidget {
  const DisplaySettingsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('表示設定', style: TextStyle(fontWeight: FontWeight.bold)),
        ),

        ListTile(
          leading: const Icon(Icons.play_circle_outline),
          subtitle: AutoScrollIntervalSelector(
            currentValue: settings.autoScrollInterval,
            onChanged: (value) {
              settings.setAutoScrollInterval(value);
            },
          ),
        ),

        ListTile(
          leading: const Icon(Icons.grid_view_outlined),
          title: Text('一覧の列数 (${settings.gridCrossAxisCount})'),
          subtitle: Slider(
            value: settings.gridCrossAxisCount.toDouble(),
            min: 1,
            max: 8,
            divisions: 7,
            label: settings.gridCrossAxisCount.toString(),
            onChanged: (double value) {
              settings.setGridCrossAxisCount(value.toInt());
            },
          ),
        ),

        ListTile(
          leading: const Icon(Icons.visibility_outlined),
          title: const Text('表示するレーティング'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Wrap(
              spacing: 8.0,
              children: Rating.values.map((rating) {
                final isVisible = settings.visibleRatings[rating] ?? true;
                return FilterChip(
                  label: Text(rating.displayName),
                  selected: isVisible,
                  onSelected: (bool selected) {
                    settings.setRatingVisibility(rating, selected);
                  },
                  selectedColor: Theme.of(context).colorScheme.primaryContainer,
                  checkmarkColor: Theme.of(
                    context,
                  ).colorScheme.onPrimaryContainer,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  labelStyle: TextStyle(
                    color: isVisible
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: isVisible ? FontWeight.bold : FontWeight.normal,
                  ),
                );
              }).toList(),
            ),
          ),
        ),

        ListTile(
          leading: const Icon(Icons.brightness_6_outlined),
          title: const Text('アプリのテーマ'),
          trailing: DropdownButton<ThemeMode>(
            value: settings.themeMode,
            items: const [
              DropdownMenuItem(
                value: ThemeMode.system,
                child: Text('システム設定に従う'),
              ),
              DropdownMenuItem(value: ThemeMode.light, child: Text('ライト')),
              DropdownMenuItem(value: ThemeMode.dark, child: Text('ダーク')),
            ],
            onChanged: (ThemeMode? newMode) {
              if (newMode != null) settings.setThemeMode(newMode);
            },
          ),
        ),

        ListTile(
          leading: const Icon(Icons.horizontal_rule),
          title: const Text('アプリバーの位置'),
          trailing: DropdownButton<bool>(
            value: settings.useBottomAppBar,
            items: const [
              DropdownMenuItem(value: false, child: Text('トップ')),
              DropdownMenuItem(value: true, child: Text('ボトム')),
            ],
            onChanged: (bool? newValue) {
              if (newValue != null) settings.setUseBottomAppBar(newValue);
            },
          ),
        ),
      ],
    );
  }
}
