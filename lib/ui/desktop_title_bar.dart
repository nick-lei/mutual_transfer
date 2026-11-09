import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import 'components.dart';

class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({
    super.key,
    required this.leadingWidth,
    required this.compactBrand,
    required this.child,
    required this.actions,
    this.navigationToggle,
    this.closeToTray = false,
  });

  final double leadingWidth;
  final bool compactBrand;
  final Widget child;
  final List<Widget> actions;
  final Widget? navigationToggle;
  final bool closeToTray;

  Widget _dragRegion(Widget child) => GestureDetector(
    onSecondaryTap: windowManager.popUpWindowMenu,
    child: DragToMoveArea(child: child),
  );

  @override
  Widget build(BuildContext context) => Container(
    height: 64,
    decoration: const BoxDecoration(color: canvas),
    child: Row(
      children: [
        _dragRegion(
          Container(
            key: const ValueKey('brand-drag-region'),
            width: leadingWidth,
            height: double.infinity,
            padding: EdgeInsets.only(
              left: compactBrand ? (leadingWidth - 36) / 2 : 20,
            ),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: leadingWidth >= 76 ? shell : canvas,
            ),
            child: Brand(compact: compactBrand),
          ),
        ),
        if (navigationToggle != null)
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: navigationToggle,
          ),
        Expanded(
          child: _dragRegion(
            Container(
              key: const ValueKey('title-drag-region'),
              color: Colors.transparent,
              height: double.infinity,
              child: Padding(
                padding: EdgeInsets.only(
                  left: navigationToggle != null
                      ? 12
                      : leadingWidth < 76
                      ? 3
                      : 30,
                  right: 12,
                ),
                child: child,
              ),
            ),
          ),
        ),
        ...actions,
        const SizedBox(width: 10),
        Container(width: 1, height: 18, color: line),
        const SizedBox(width: 10),
        _WindowControls(closeToTray: closeToTray),
        const SizedBox(width: 8),
      ],
    ),
  );
}

class _WindowControls extends StatefulWidget {
  const _WindowControls({required this.closeToTray});
  final bool closeToTray;

  @override
  State<_WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<_WindowControls> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncMaximized());
  }

  Future<void> _syncMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _maximized = maximized);
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _toggleMaximized() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _syncMaximized();
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _CaptionButton(
        label: '最小化',
        icon: LucideIcons.minus,
        onPressed: windowManager.minimize,
      ),
      _CaptionButton(
        label: _maximized ? '还原' : '最大化',
        icon: _maximized ? LucideIcons.copy : LucideIcons.square,
        onPressed: _toggleMaximized,
      ),
      _CaptionButton(
        label: widget.closeToTray ? '收起到任务托盘' : '关闭',
        icon: LucideIcons.x,
        onPressed: windowManager.close,
        close: true,
      ),
    ],
  );
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.close = false,
  });
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool close;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onPressed,
    icon: Icon(icon, size: 14),
    style: ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(42, 36)),
      maximumSize: const WidgetStatePropertyAll(Size(42, 36)),
      fixedSize: const WidgetStatePropertyAll(Size(42, 36)),
      padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            close &&
                (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed))
            ? Colors.white
            : const Color(0xFF717982),
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            close &&
                (states.contains(WidgetState.hovered) ||
                    states.contains(WidgetState.pressed))
            ? const Color(0xFFC94C4C)
            : Colors.transparent,
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => close ? Colors.transparent : const Color(0xFFEEF1F3),
      ),
    ),
  );
}
