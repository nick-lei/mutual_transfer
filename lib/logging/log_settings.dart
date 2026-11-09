import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ui/components.dart';
import '../android/android_host.dart';
import 'app_log.dart';

Future<void> exportLogs(BuildContext context, AppLog log) async {
  try {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    if (Platform.isAndroid) {
      final path = '${log.directory.parent.path}/NearLink-$stamp.jsonl';
      await log.export(path);
      final saved = await AndroidPaths.channel.invokeMethod<bool>(
        'exportFile',
        {'path': path},
      );
      if (saved == true && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日志已导出')));
      }
      return;
    }
    final path = await FilePicker.saveFile(
      dialogTitle: '导出运行日志',
      fileName: 'NearLink-$stamp.jsonl',
      type: FileType.custom,
      allowedExtensions: ['jsonl'],
    );
    if (path == null) return;
    await log.export(path);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('日志已导出')));
    }
  } catch (error, stack) {
    log.warning(
      'logging',
      'export_failed',
      '日志导出失败',
      error: error,
      stack: stack,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('日志导出失败，请检查保存位置后重试。')));
    }
  }
}

class LogSettings extends StatelessWidget {
  const LogSettings({super.key, required this.log});
  final AppLog log;

  Future<void> _openDirectory(BuildContext context) async {
    try {
      await log.directory.create(recursive: true);
      final result = await Process.run('explorer.exe', [log.directory.path]);
      if (result.exitCode != 0 && result.exitCode != 1) {
        throw const FileSystemException('无法打开日志目录');
      }
    } catch (error) {
      log.warning('logging', 'open_directory_failed', '日志目录打开失败', error: error);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('无法打开日志目录，请检查目录是否可用。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<void>(
    stream: log.changes,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('运行日志'),
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, box) {
                  final actions = Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        key: const ValueKey('view-logs'),
                        tooltip: '查看日志',
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => LogViewer(log: log),
                        ),
                        icon: const Icon(LucideIcons.scrollText),
                      ),
                      IconButton(
                        tooltip: '打开日志目录',
                        onPressed: () => _openDirectory(context),
                        icon: const Icon(LucideIcons.folderOpen),
                      ),
                      IconButton(
                        tooltip: '导出日志',
                        onPressed: () => exportLogs(context, log),
                        icon: const Icon(LucideIcons.download),
                      ),
                    ],
                  );
                  final label = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '本机诊断记录',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '最多保留 ${((log.archiveCount + 1) * log.maxFileBytes / 1024 / 1024).round()} MiB',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  );
                  return box.maxWidth < 440
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            label,
                            const SizedBox(height: 12),
                            actions,
                          ],
                        )
                      : Row(
                          children: [
                            Expanded(child: label),
                            actions,
                          ],
                        );
                },
              ),
              const SizedBox(height: 14),
              SelectableText(
                log.directory.path,
                style: const TextStyle(color: muted, fontSize: 12),
              ),
              if (log.storageError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    log.storageError!,
                    style: const TextStyle(color: danger, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class LogViewer extends StatefulWidget {
  const LogViewer({super.key, required this.log});
  final AppLog log;
  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  final _search = TextEditingController();
  StreamSubscription<LogEntry>? _subscription;
  List<LogEntry> _entries = [];
  bool _loading = true, _exporting = false;
  String _level = 'all';
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscription = widget.log.events.listen((entry) {
      if (mounted) setState(() => _merge([entry]));
    });
    unawaited(_load());
  }

  void _merge(List<LogEntry> entries) {
    final all = {
      for (final entry in [..._entries, ...entries]) entry.id: entry,
    }.values.toList()..sort((a, b) => b.time.compareTo(a.time));
    _entries = all.take(500).toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await widget.log.readRecent();
      if (mounted) {
        setState(() {
          _merge(entries);
          _error = widget.log.storageError;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '日志读取失败，请检查日志目录后刷新。');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      await exportLogs(context, widget.log);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered = _entries
        .where(
          (entry) =>
              (_level == 'all' || entry.level.name == _level) &&
              (query.isEmpty ||
                  jsonEncode(entry.toJson()).toLowerCase().contains(query)),
        )
        .toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 1000,
        height: math.min(720, MediaQuery.sizeOf(context).height - 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '运行日志',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '刷新日志',
                    onPressed: _loading ? null : _load,
                    icon: const Icon(LucideIcons.refreshCw),
                  ),
                  IconButton(
                    tooltip: '导出日志',
                    onPressed: _exporting ? null : _export,
                    icon: const Icon(LucideIcons.download),
                  ),
                  IconButton(
                    tooltip: '关闭日志',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: LayoutBuilder(
                builder: (context, box) {
                  final search = TextField(
                    key: const ValueKey('log-search'),
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '搜索日志',
                      prefixIcon: const Icon(LucideIcons.search, size: 18),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '清空搜索',
                              onPressed: () => setState(_search.clear),
                              icon: const Icon(LucideIcons.x, size: 16),
                            ),
                    ),
                  );
                  final level = SizedBox(
                    width: 150,
                    child: DropdownButtonFormField<String>(
                      key: const ValueKey('log-level-filter'),
                      initialValue: _level,
                      isExpanded: true,
                      icon: const Icon(LucideIcons.chevronDown, size: 18),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('全部级别')),
                        DropdownMenuItem(value: 'info', child: Text('信息')),
                        DropdownMenuItem(value: 'warning', child: Text('警告')),
                        DropdownMenuItem(value: 'error', child: Text('错误')),
                      ],
                      onChanged: (value) =>
                          setState(() => _level = value ?? 'all'),
                    ),
                  );
                  return box.maxWidth < 500
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [search, const SizedBox(height: 10), level],
                        )
                      : Row(
                          children: [
                            Expanded(child: search),
                            const SizedBox(width: 12),
                            level,
                          ],
                        );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Text(
                '${filtered.length} / ${_entries.length} 条',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  _error!,
                  style: const TextStyle(color: danger, fontSize: 13),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                  ? Center(
                      child: Text(
                        _entries.isEmpty ? '暂无运行日志' : '没有匹配的日志',
                        style: const TextStyle(color: muted),
                      ),
                    )
                  : ListView.separated(
                      key: const ValueKey('log-entries'),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 20, endIndent: 20),
                      itemBuilder: (context, index) => _LogRow(
                        key: ValueKey(filtered[index].id),
                        entry: filtered[index],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({super.key, required this.entry});
  final LogEntry entry;
  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (entry.level) {
      LogLevel.info => (blue, LucideIcons.info, '信息'),
      LogLevel.warning => (amber, LucideIcons.triangleAlert, '警告'),
      LogLevel.error => (danger, LucideIcons.circleAlert, '错误'),
    };
    final time = entry.time
        .toLocal()
        .toIso8601String()
        .replaceFirst('T', ' ')
        .substring(0, 23);
    final json = const JsonEncoder.withIndent('  ').convert(entry.toJson());
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      shape: const Border(),
      collapsedShape: const Border(),
      leading: Tooltip(
        message: label,
        child: Icon(icon, color: color, size: 19),
      ),
      trailing: const Icon(LucideIcons.chevronsUpDown, size: 18),
      title: Text(
        entry.message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '$time\n${entry.component} / ${entry.event}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'Segoe UI',
          fontSize: 12,
          color: muted,
        ),
      ),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: IconButton(
            tooltip: '复制日志详情',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('日志详情已复制')));
              }
            },
            icon: const Icon(LucideIcons.copy, size: 17),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            json,
            style: const TextStyle(
              fontSize: 12,
              height: 1.7,
              fontFamily: 'Consolas',
            ),
          ),
        ),
      ],
    );
  }
}
