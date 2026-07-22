import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:media_kit/media_kit.dart';

import '../../../core/player/player_controller.dart';
import '../../../core/theme/app_tokens.dart';

/// 字幕面板（底部抽屉）。
///
/// 展示可用字幕轨道列表、字幕偏移滑块（-5s~+5s）与显示开关，
/// 通过 [PlayerController] 实时切换 / 调整字幕，变更立即生效。
class SubtitlePanel extends StatefulWidget {
  const SubtitlePanel({super.key, required this.controller});

  final PlayerController controller;

  /// 以 modal bottom sheet 形式展示字幕面板。
  static Future<void> show(
    BuildContext context, {
    required PlayerController controller,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTokens.radiusLg),
        ),
      ),
      builder: (BuildContext context) =>
          SubtitlePanel(controller: controller),
    );
  }

  @override
  State<SubtitlePanel> createState() => _SubtitlePanelState();
}

class _SubtitlePanelState extends State<SubtitlePanel> {
  /// 当前可用字幕轨道（过滤掉 'auto' / 'no' 占位项，仅展示真实轨道）。
  List<SubtitleTrack> _tracks = const <SubtitleTrack>[];

  StreamSubscription<Tracks>? _tracksSub;

  // ── 字幕样式状态（本地 UI 状态，onChangeEnd 时写入 mpv） ──
  double _subFontSize = 28.0;
  double _subScale = 1.0;
  double _subBorderSize = 1.5;
  double _subShadowOffset = 2.0;
  String _subColor = 'FFFFFF';
  String _subBorderColor = '000000';
  String _subShadowColor = '000000';
  String _subPosition = 'bottom';
  String _subAssMode = 'yes';

  @override
  void initState() {
    super.initState();
    _refreshTracks(widget.controller.subtitleTracks);
    _tracksSub = widget.controller.tracksStream.listen((Tracks t) {
      _refreshTracks(t.subtitle);
    });
  }

  @override
  void dispose() {
    _tracksSub?.cancel();
    super.dispose();
  }

  /// 更新可用字幕轨道列表（过滤占位项），并同步当前选中轨道的显示状态。
  void _refreshTracks(List<SubtitleTrack> tracks) {
    final real = tracks
        .where((SubtitleTrack t) => t.id != 'auto' && t.id != 'no')
        .toList(growable: false);
    if (mounted) setState(() => _tracks = real);
  }

  /// 生成轨道展示标签：优先 title，其次 language，最后回退到「轨道 N」。
  String _trackLabel(SubtitleTrack track, AppLocalizations l10n) {
    if (track.title != null && track.title!.trim().isNotEmpty) {
      return track.title!.trim();
    }
    if (track.language != null && track.language!.trim().isNotEmpty) {
      return track.language!.trim();
    }
    return l10n.subtitleTrackN(track.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _header(context, l10n, theme),
          Flexible(
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (BuildContext context, _) {
                return ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTokens.spaceLg,
                    vertical: AppTokens.spaceSm,
                  ),
                  children: <Widget>[
                    _trackSection(l10n, theme),
                    const Divider(height: 1),
                    _styleSection(l10n, theme),
                    const SizedBox(height: AppTokens.spaceMd),
                    _offsetSection(l10n, theme),
                    const SizedBox(height: AppTokens.spaceXs),
                    _visibleSection(l10n, theme),
                    const SizedBox(height: AppTokens.spaceLg),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, AppLocalizations l10n, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppTokens.spaceLg,
        AppTokens.spaceMd,
        AppTokens.spaceSm,
        AppTokens.spaceSm,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              l10n.subtitleTitle,
              style: theme.textTheme.titleMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: l10n.close,
          ),
        ],
      ),
    );
  }

  Widget _trackSection(AppLocalizations l10n, ThemeData theme) {
    final current = widget.controller.currentSubtitleTrack;
    final visible = widget.controller.subtitleVisible;
    // 当前生效的轨道：显示开关关闭时视为未选中。
    final selected = visible ? current : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // #5 A4-#5: 加载外部字幕文件
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.file_open_outlined, color: theme.colorScheme.primary),
          title: Text(l10n.loadExternalSubtitle),
          onTap: () => _pickExternalSubtitle(l10n),
        ),
        const Divider(height: 1),
        for (final SubtitleTrack track in _tracks)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(_trackLabel(track, l10n)),
            trailing: selected?.id == track.id
                ? Icon(Icons.check, color: theme.colorScheme.primary)
                : null,
            onTap: () => widget.controller.setSubtitleTrack(track),
          ),
        // 关闭字幕
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.subtitleNone),
          trailing: selected == null
              ? Icon(Icons.check, color: theme.colorScheme.primary)
              : null,
          onTap: () => widget.controller.setSubtitleTrack(null),
        ),
        if (_tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
            child: Text(
              l10n.subtitleNoTracks,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  /// #5 A4-#5: 通过 file_picker 选择本地 .srt/.vtt/.ass 字幕文件，
  /// 使用 SubtitleTrack.uri 加载到播放器。
  Future<void> _pickExternalSubtitle(AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['srt', 'vtt', 'ass', 'ssa'],
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.first.path;
      if (path == null || path.isEmpty) return;
      final track = SubtitleTrack.uri(path);
      await widget.controller.setSubtitleTrack(track);
      await widget.controller.setSubtitleVisible(true);
      messenger.showSnackBar(
        SnackBar(content: Text(track.title ?? path)),
      );
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.loadExternalSubtitleFailed)),
      );
    }
  }

  /// 字幕样式设置：字号 / 颜色 / 边框 / 阴影 / 缩放 / 位置 / ASS覆盖。
  Widget _styleSection(AppLocalizations l10n, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 标题
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceXs),
          child: Text(
            l10n.subtitleStyleTitle,
            style: theme.textTheme.titleSmall,
          ),
        ),
        // 字号滑块
        Row(
          children: <Widget>[
            Expanded(child: Text(l10n.subtitleFontSize, style: theme.textTheme.bodyMedium)),
            Text('${_subFontSize.toInt()}', style: theme.textTheme.bodySmall),
          ],
        ),
        Slider(
          value: _subFontSize,
          min: 14,
          max: 60,
          divisions: 46,
          onChanged: (v) => setState(() => _subFontSize = v),
          onChangeEnd: (v) => widget.controller.setSubtitleFontSize(v),
        ),
        // 缩放
        Row(
          children: <Widget>[
            Expanded(child: Text(l10n.subtitleScale, style: theme.textTheme.bodyMedium)),
            Text(_subScale.toStringAsFixed(2), style: theme.textTheme.bodySmall),
          ],
        ),
        Slider(
          value: _subScale,
          min: 0.5,
          max: 3.0,
          divisions: 50,
          onChanged: (v) => setState(() => _subScale = v),
          onChangeEnd: (v) => widget.controller.setSubtitleScale(v),
        ),
        // 边框宽度
        Row(
          children: <Widget>[
            Expanded(child: Text(l10n.subtitleBorderSize, style: theme.textTheme.bodyMedium)),
            Text('${_subBorderSize.toStringAsFixed(1)}px', style: theme.textTheme.bodySmall),
          ],
        ),
        Slider(
          value: _subBorderSize,
          min: 0,
          max: 6,
          divisions: 12,
          onChanged: (v) => setState(() => _subBorderSize = v),
          onChangeEnd: (v) => widget.controller.setSubtitleBorderSize(v),
        ),
        // 阴影偏移
        Row(
          children: <Widget>[
            Expanded(child: Text(l10n.subtitleShadowOffset, style: theme.textTheme.bodyMedium)),
            Text('${_subShadowOffset.toStringAsFixed(1)}px', style: theme.textTheme.bodySmall),
          ],
        ),
        Slider(
          value: _subShadowOffset,
          min: 0,
          max: 12,
          divisions: 24,
          onChanged: (v) => setState(() => _subShadowOffset = v),
          onChangeEnd: (v) => widget.controller.setSubtitleShadowOffset(v),
        ),

        const SizedBox(height: AppTokens.spaceXs),

        // 颜色选择行（文字颜色 + 边框颜色 + 阴影颜色）
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceXs,
          children: <Widget>[
            ActionChip(
              avatar: CircleAvatar(backgroundColor: _bgrToColor(_subColor), radius: 8),
              label: Text(l10n.subtitleTextColor),
              onPressed: () => _pickColor(l10n, isText: true),
            ),
            ActionChip(
              avatar: CircleAvatar(backgroundColor: _bgrToColor(_subBorderColor), radius: 8),
              label: Text(l10n.subtitleBorderColorLabel),
              onPressed: () => _pickColor(l10n, isBorder: true),
            ),
            ActionChip(
              avatar: CircleAvatar(backgroundColor: _bgrToColor(_subShadowColor), radius: 8),
              label: Text(l10n.subtitleShadowColorLabel),
              onPressed: () => _pickColor(l10n, isShadow: true),
            ),
          ],
        ),

        const SizedBox(height: AppTokens.spaceSm),

        // 位置选择
        Row(
          children: <Widget>[
            Expanded(child: Text(l10n.subtitlePosition, style: theme.textTheme.bodyMedium)),
          ],
        ),
        SegmentedButton<String>(
          segments: const <ButtonSegment<String>>[
            ButtonSegment(value: 'top', label: Text('顶部'), icon: Icon(Icons.vertical_align_top, size: 16)),
            ButtonSegment(value: 'center', label: Text('居中'), icon: Icon(Icons.vertical_align_center, size: 16)),
            ButtonSegment(value: 'bottom', label: Text('底部'), icon: Icon(Icons.vertical_align_bottom, size: 16)),
          ],
          selected: {_subPosition},
          onSelectionChanged: (Set<String> s) {
            final pos = s.first;
            setState(() => _subPosition = pos);
            widget.controller.setSubtitlePosition(pos);
          },
          showSelectedIcon: false,
          style: ButtonStyle(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: WidgetStateProperty.all(const EdgeInsets.symmetric(horizontal: 8)),
            visualDensity: VisualDensity.compact,
          ),
        ),

        const SizedBox(height: AppTokens.spaceSm),

        // ASS/SSA 覆盖模式
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(l10n.subtitleAssOverride, style: theme.textTheme.bodyMedium),
            DropdownButton<String>(
              value: _subAssMode,
              items: const <DropdownMenuItem<String>>[
                DropdownMenuItem(value: 'yes', child: Text('是')),
                DropdownMenuItem(value: 'no', child: Text('否')),
                DropdownMenuItem(value: 'strip', child: Text('剥离')),
                DropdownMenuItem(value: 'force', child: Text('强制')),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() => _subAssMode = v);
                  widget.controller.setSubtitleAssOverride(v);
                }
              },
              underline: Container(),
              iconSize: 18,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }

  /// 颜色选择器（弹出预设颜色网格）。
  Future<void> _pickColor(AppLocalizations l10n, {bool isText = false, bool isBorder = false, bool isShadow = false}) async {
    final colors = <String>[
      'FFFFFF', // 白
      'FFFF00', // 黄
      '00FF00', // 绿
      '00FFFF', // 青
      'FF0000', // 红
      'FF00FF', // 品红
      '0000FF', // 蓝
      '000000', // 黑
    ];
    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isText ? l10n.subtitleTextColor : isBorder ? l10n.subtitleBorderColorLabel : l10n.subtitleShadowColorLabel),
        content: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: colors.map((c) {
            final color = _bgrToColor(c);
            return GestureDetector(
              onTap: () => Navigator.pop(ctx, c),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24),
                ),
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
        ],
      ),
    );
    if (selected == null) return;
    if (isText) {
      setState(() => _subColor = selected);
      widget.controller.setSubtitleColor(selected);
    } else if (isBorder) {
      setState(() => _subBorderColor = selected);
      widget.controller.setSubtitleBorderColor(selected);
    } else {
      setState(() => _subShadowColor = selected);
      widget.controller.setSubtitleShadowColor(selected);
    }
  }

  /// BGR 十六进制字符串转 Color（mpv 使用 BGR 格式）。
  static Color _bgrToColor(String hex) {
    final val = int.tryParse(hex, radix: 16) ?? 0xFFFFFFFF;
    // mpv sub-color 是 BGR(AABBGGRR)，Flutter Color 是 ARGB(0xAARRGGBB)
    final r = (val >> 16) & 0xFF;
    final g = (val >> 8) & 0xFF;
    final b = val & 0xFF;
    return Color.fromARGB(255, r, g, b);
  }

  Widget _offsetSection(AppLocalizations l10n, ThemeData theme) {
    final delay = widget.controller.subtitleDelay;
    final seconds = delay.inMilliseconds / 1000.0;
    final sign = seconds >= 0 ? '+' : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(l10n.subtitleOffset, style: theme.textTheme.bodyMedium),
            Text(
              '$sign${seconds.toStringAsFixed(1)}s',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ],
        ),
        Slider(
          value: seconds.clamp(-5.0, 5.0),
          min: -5,
          max: 5,
          divisions: 100,
          onChanged: (double v) =>
              widget.controller.setSubtitleDelay(Duration(milliseconds: (v * 1000).round())),
        ),
      ],
    );
  }

  Widget _visibleSection(AppLocalizations l10n, ThemeData theme) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(l10n.subtitleShow),
      value: widget.controller.subtitleVisible,
      onChanged: (bool v) => widget.controller.setSubtitleVisible(v),
    );
  }
}
