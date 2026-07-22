import 'dart:io';
import 'package:flutter/material.dart';
import '../models/plugin_config.dart';
import '../theme/app_tokens.dart';
import 'source_image.dart';

/// 统一封面图：支持 http(s) 远程图与本地文件路径，含占位图、阴影、Hero。
///
/// 当 [source] 非空时，远程图委托给 [SourceImage]（注入防盗链 headers、
/// 带缓存与重试），并跳过自身装饰以避免双重 ClipRRect / Hero。
/// 当 [source] 为空时，保持原有兼容行为（无防盗链注入）。
class AppCoverImage extends StatelessWidget {
  final String? coverUrl;
  final double? width;
  final double? height;
  final double? radius;
  final BoxFit fit;
  final String? heroTag;
  final PluginConfig? source;

  /// 标题（封面为空时用于渲染首字占位图，避免纯灰块）。
  final String? title;
  const AppCoverImage({
    super.key,
    this.coverUrl,
    this.width,
    this.height,
    this.radius,
    this.fit = BoxFit.cover,
    this.heroTag,
    this.source,
    this.title,
  });

  bool get _isFile => coverUrl != null && !coverUrl!.startsWith('http');

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double r = radius ?? AppTokens.coverRadius;

    // 有源配置的远程图：直接委托 SourceImage（内部处理防盗链/圆角/Hero/占位），避免双重装饰。
    if (source != null && coverUrl != null && coverUrl!.isNotEmpty && !_isFile) {
      return SourceImage(
        url: coverUrl,
        source: source,
        width: width,
        height: height,
        fit: fit,
        radius: radius,
        heroTag: heroTag,
      );
    }

    final Widget placeholder = SizedBox(
      width: width,
      height: height,
      child: Container(
        color: scheme.surfaceContainerHighest,
        child: Icon(Icons.image_outlined,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
      ),
    );

    final Widget image;
    if (coverUrl == null || coverUrl!.isEmpty) {
      image = _letterPlaceholder(context);
    } else if (_isFile) {
      image = Image.file(
        File(coverUrl!),
        width: width,
        height: height,
        fit: fit,
        frameBuilder: _frame(placeholder),
      );
    } else {
      // 无源配置的远程图：用 SourceImage 但不传 radius/hero（由外层 AppCoverImage 装饰）。
      image = SourceImage(
        url: coverUrl,
        source: null,
        width: width,
        height: height,
        fit: fit,
        placeholder: placeholder,
      );
    }

    final Widget decorated = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(r),
        boxShadow: AppShadows.cover(scheme),
        color: scheme.surfaceContainerHighest,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: image,
      ),
    );

    return heroTag != null ? Hero(tag: heroTag!, child: decorated) : decorated;
  }

  /// 封面为空时的占位图：有标题则渲染首字 + 主题色，无标题才退回纯灰图标。
  Widget _letterPlaceholder(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String ch =
        (title != null && title!.trim().isNotEmpty) ? title!.trim()[0] : '';
    if (ch.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: Container(
          color: scheme.surfaceContainerHighest,
          child: Icon(Icons.image_outlined,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
        ),
      );
    }
    const List<Color> palette = <Color>[
      Colors.blue,
      Colors.teal,
      Colors.deepPurple,
      Colors.orange,
      Colors.green,
      Colors.pink,
      Colors.indigo,
      Colors.brown,
    ];
    final int hash = title!.codeUnits.fold(0, (int a, int b) => a + b);
    final Color bg = palette[hash % palette.length];
    return SizedBox(
      width: width,
      height: height,
      child: Container(
        color: bg,
        child: Center(
          child: Text(
            ch,
            style: TextStyle(
              color: Colors.white,
              fontSize: (width ?? 120) * 0.4,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  ImageFrameBuilder _frame(Widget placeholder) =>
      (c, Widget child, int? frame, _) => frame == null ? placeholder : child;
}
