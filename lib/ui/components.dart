import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import 'app_theme.dart';
export 'app_theme.dart';

class Brand extends StatelessWidget {
  const Brand({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Image.asset(
        'assets/brand/app-icon.png',
        width: 36,
        height: 36,
        filterQuality: FilterQuality.high,
        semanticLabel: compact ? '邻传 NearLink' : null,
        excludeFromSemantics: !compact,
      ),
      if (!compact) ...[
        const SizedBox(width: 11),
        const Text(
          '邻传',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: ink,
          ),
        ),
        const SizedBox(width: 7),
        const Text(
          'NearLink',
          style: TextStyle(
            fontFamily: 'Segoe UI',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: muted,
          ),
        ),
      ],
    ],
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = Colors.white,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading(this.title, this.subtitle, {super.key, this.action});
  final String title, subtitle;
  final Widget? action;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final copy = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 14, color: muted, height: 1.6),
          ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: 28),
        child: box.maxWidth < 620
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  copy,
                  if (action != null) ...[const SizedBox(height: 16), action!],
                ],
              )
            : Row(
                children: [
                  Expanded(child: copy),
                  if (action != null) ...[const SizedBox(width: 24), action!],
                ],
              ),
      );
    },
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(
    this.label, {
    super.key,
    this.color = green,
    this.dot = true,
  });
  final String label;
  final Color color;
  final bool dot;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.count, this.action});
  final String title;
  final int? count;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 8),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontFamily: 'Segoe UI',
                    fontSize: 13,
                    color: muted,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?action,
      ],
    ),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.label,
    this.detail,
    this.height = 180,
    this.action,
  });
  final IconData icon;
  final String label;
  final String? detail;
  final double height;
  final Widget? action;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minHeight: height),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: blueTint,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: blue, size: 26),
            ),
            const SizedBox(height: 18),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  detail!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: muted,
                    fontSize: 13,
                    height: 1.7,
                  ),
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    ),
  );
}

class FileGlyph extends StatelessWidget {
  const FileGlyph(this.name, {super.key, this.size = 44});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (p.extension(name).toLowerCase()) {
      '.png' ||
      '.jpg' ||
      '.jpeg' ||
      '.gif' ||
      '.webp' ||
      '.svg' => (LucideIcons.image, green),
      '.mp4' ||
      '.mov' ||
      '.mkv' ||
      '.avi' => (LucideIcons.film, const Color(0xFF7752B3)),
      '.zip' ||
      '.rar' ||
      '.7z' ||
      '.tar' ||
      '.gz' => (LucideIcons.fileArchive, amber),
      '.pdf' => (LucideIcons.fileText, danger),
      '.mp3' ||
      '.wav' ||
      '.flac' => (LucideIcons.music2, const Color(0xFFAB4573)),
      '.xls' || '.xlsx' || '.csv' => (LucideIcons.sheet, green),
      _ => (LucideIcons.fileText, blue),
    };
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: size * .48),
    );
  }
}

class DeviceAvatar extends StatelessWidget {
  const DeviceAvatar(
    this.platform, {
    super.key,
    this.size = 44,
    this.active = false,
  });
  final String platform;
  final double size;
  final bool active;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: active ? blue : blueTint,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Icon(
      deviceIcon(platform),
      size: size * .48,
      color: active ? Colors.white : blue,
    ),
  );
}

IconData deviceIcon(String platform) => switch (platform.toLowerCase()) {
  'android' || 'ios' => LucideIcons.smartphone,
  'macos' => LucideIcons.laptop,
  _ => LucideIcons.monitor,
};
String timeLabel(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
String dayLabel(DateTime time) {
  final now = DateTime.now();
  final days = DateTime(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime(time.year, time.month, time.day)).inDays;
  if (days == 0) return '今天';
  if (days == 1) return '昨天';
  return '${time.year == now.year ? '' : '${time.year}年'}${time.month}月${time.day}日';
}
