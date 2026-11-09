import 'package:flutter/material.dart';

import '../ui/components.dart';
import 'desktop_controller.dart';

class DesktopSettings extends StatelessWidget {
  const DesktopSettings({super.key, required this.controller});
  final DesktopController controller;

  Future<void> _save(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // The controller exposes the error beside the settings.
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('启动与关闭'),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  const label = _SettingLabel('关闭主窗口时', '收起到托盘后，继续接收文件和消息。');
                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                  final enabled = controller.ready && !controller.updating;
                  final control = RadioGroup<bool>(
                    groupValue: controller.closeToTray,
                    onChanged: (value) {
                      if (enabled && value != null) {
                        _save(() => controller.setCloseToTray(value));
                      }
                    },
                    child: Material(
                      type: MaterialType.transparency,
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          for (final option in const [
                            (true, '收起到任务托盘', 180.0),
                            (false, '退出邻传', 128.0),
                          ])
                            SizedBox(
                              width: option.$3 * textScale,
                              child: RadioListTile<bool>(
                                key: ValueKey('close-behavior-${option.$1}'),
                                value: option.$1,
                                enabled: enabled,
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                title: Text(
                                  option.$2,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontSize: 13),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                  if (box.maxWidth < 700 * textScale) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [label, const SizedBox(height: 12), control],
                    );
                  }
                  return Row(
                    children: [
                      const Expanded(child: label),
                      const SizedBox(width: 24),
                      SizedBox(width: 308 * textScale + 12, child: control),
                    ],
                  );
                },
              ),
              const SizedBox(height: 24),
              const Divider(height: 1),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: _SettingLabel('开机自启', '登录 Windows 后在任务托盘启动。'),
                  ),
                  const SizedBox(width: 16),
                  Switch(
                    key: const ValueKey('start-at-login'),
                    value: controller.startAtLogin,
                    onChanged: !controller.ready || controller.updating
                        ? null
                        : (value) =>
                              _save(() => controller.setStartAtLogin(value)),
                  ),
                ],
              ),
              for (final error in [
                controller.trayError,
                controller.settingsError,
              ])
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error,
                      style: const TextStyle(fontSize: 12, color: danger),
                    ),
                  ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SettingLabel extends StatelessWidget {
  const _SettingLabel(this.title, this.subtitle);
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(subtitle, style: const TextStyle(fontSize: 12, color: muted)),
    ],
  );
}
