import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ui/components.dart';
import 'desktop_notifications.dart';

class NotificationSettings extends StatelessWidget {
  const NotificationSettings({super.key, required this.controller});
  final DesktopNotifications controller;

  Future<void> _save(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      /* The controller displays save errors. */
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('桌面通知'),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '文件接收提醒',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '仅在邻传位于后台时弹出。',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Semantics(
                    label: '文件接收提醒',
                    child: Switch(
                      key: const ValueKey('file-notifications'),
                      value: controller.enabled,
                      onChanged: controller.ready && !controller.updating
                          ? (value) =>
                                _save(() => controller.update(enabled: value))
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '文件请求提示音',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Semantics(
                    label: '文件请求提示音',
                    child: Switch(
                      key: const ValueKey('notification-sound'),
                      value: controller.sound,
                      onChanged:
                          controller.ready &&
                              controller.enabled &&
                              !controller.updating
                          ? (value) =>
                                _save(() => controller.update(sound: value))
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '传输完成通知',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '后台发送或接收完成时提醒。',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Semantics(
                    label: '传输完成通知',
                    child: Switch(
                      key: const ValueKey('completion-notifications'),
                      value: controller.completionEnabled,
                      onChanged: controller.ready && !controller.updating
                          ? (value) => _save(
                              () => controller.update(completionEnabled: value),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '完成提示音',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Semantics(
                    label: '完成提示音',
                    child: Switch(
                      key: const ValueKey('completion-sound'),
                      value: controller.completionSound,
                      onChanged: controller.ready && !controller.updating
                          ? (value) => _save(
                              () => controller.update(completionSound: value),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '消息桌面通知',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '后台收到未读消息时提醒。',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Semantics(
                    label: '消息桌面通知',
                    child: Switch(
                      key: const ValueKey('message-notifications'),
                      value: controller.messageEnabled,
                      onChanged: controller.ready && !controller.updating
                          ? (value) => _save(
                              () => controller.update(messageEnabled: value),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '消息提示音',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '试听消息提示音',
                    onPressed: controller.available && !controller.testing
                        ? controller.testMessageSound
                        : null,
                    icon: const Icon(LucideIcons.volume2, size: 19),
                  ),
                  const SizedBox(width: 8),
                  Semantics(
                    label: '消息提示音',
                    child: Switch(
                      key: const ValueKey('message-sound'),
                      value: controller.messageSound,
                      onChanged: controller.ready && !controller.updating
                          ? (value) => _save(
                              () => controller.update(messageSound: value),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: '发送测试通知',
                    onPressed:
                        controller.available &&
                            controller.enabled &&
                            !controller.testing &&
                            !controller.updating
                        ? controller.test
                        : null,
                    icon: controller.testing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(LucideIcons.bellRing, size: 19),
                  ),
                  IconButton(
                    tooltip: '重新检测通知',
                    onPressed: controller.updating ? null : controller.refresh,
                    icon: const Icon(LucideIcons.refreshCw, size: 19),
                  ),
                  IconButton(
                    tooltip: 'Windows 通知设置',
                    onPressed: controller.openSettings,
                    icon: const Icon(LucideIcons.settings2, size: 19),
                  ),
                ],
              ),
              if (controller.allowed == false)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Windows 已关闭邻传通知，可在系统通知设置中开启。',
                    style: TextStyle(fontSize: 12, color: amber),
                  ),
                ),
              if (controller.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    controller.error!,
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
