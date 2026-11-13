import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app_theme.dart';

class TransferFileCard extends StatefulWidget {
  const TransferFileCard({
    super.key,
    required this.child,
    required this.filePath,
    required this.onCopy,
  });

  final Widget child;
  final String? filePath;
  final Future<void> Function(String path) onCopy;

  @override
  State<TransferFileCard> createState() => _TransferFileCardState();
}

class _TransferFileCardState extends State<TransferFileCard> {
  final _focus = FocusNode(debugLabel: 'transfer-file');
  bool _menuOpen = false, _copying = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _focus.dispose();
    super.dispose();
  }

  Future<void> _copy() async {
    final path = widget.filePath;
    if (path == null || _copying) return;
    _copying = true;
    try {
      await widget.onCopy(path);
    } finally {
      _copying = false;
    }
  }

  Future<void> _showMenu(Offset position) async {
    if (_menuOpen) return;
    _focus.requestFocus();
    setState(() => _menuOpen = true);
    try {
      final path = widget.filePath;
      var available = false;
      if (path != null && path.isNotEmpty && !path.contains('\u0000')) {
        try {
          available = await File(path).exists();
        } on FileSystemException {
          available = false;
        }
      }
      if (!mounted) return;
      final overlay =
          Overlay.of(context).context.findRenderObject()! as RenderBox;
      final local = overlay.globalToLocal(position);
      final copy = await showMenu<bool>(
        context: context,
        position: RelativeRect.fromSize(
          Rect.fromLTWH(local.dx, local.dy, 0, 0),
          overlay.size,
        ),
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        menuPadding: const EdgeInsets.symmetric(vertical: 4),
        items: [
          PopupMenuItem(
            key: const ValueKey('copy-transfer-file'),
            value: true,
            enabled: available,
            child: Row(
              children: [
                Icon(
                  LucideIcons.copy,
                  size: 16,
                  color: available ? ink : muted,
                ),
                const SizedBox(width: 10),
                const Text('复制', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 36),
                const Text(
                  'Ctrl+C',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
        ],
      );
      if (copy == true && mounted) await _copy();
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _focus.hasFocus || _menuOpen;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): () =>
              unawaited(_copy()),
          const SingleActivator(LogicalKeyboardKey.escape): _focus.unfocus,
        },
        child: Focus(
          focusNode: _focus,
          child: Semantics(
            selected: selected,
            child: Material(
              color: selected ? blueTint : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: selected ? blue : Colors.transparent),
              ),
              child: InkWell(
                canRequestFocus: false,
                borderRadius: BorderRadius.circular(8),
                onTap: _focus.requestFocus,
                onSecondaryTapUp: (details) =>
                    unawaited(_showMenu(details.globalPosition)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
