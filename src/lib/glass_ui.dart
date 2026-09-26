import 'system_errors.dart';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'playback_scaffold.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;

bool _shadersReady = true;
lg.GlassQuality get studyGlassControlQuality =>
  _shadersReady ? lg.GlassQuality.standard : lg.GlassQuality.minimal;

// One rendering policy on every supported iOS version. Dense content uses the
// library's minimal tier; controls use standard, without startup benchmarking.
Widget studyGlassRoot(Widget child) => lg.LiquidGlassWidgets.wrap(
  brightnessResolver: Theme.maybeBrightnessOf,
  theme: lg.GlassThemeData.simple(blur: 8, thickness: 24,
    quality: studyGlassControlQuality),
  child: child,
);

Future<void> initializeStudyGlass() async {
  try {
    await lg.LiquidGlassWidgets.initialize(enablePerformanceMonitor: false,
      warmUpMode: lg.GlassWarmUpMode.never);
  } catch (error, caughtStack) {
      SystemErrors.record(error, caughtStack, module: 'rendering', operation: '初始化玻璃效果', context: {'source': 'glass_ui.dart'});
    // An optional visual effect must not prevent the local database opening.
    _shadersReady = false;
    debugPrint('Glass shader preload unavailable; using minimal glass: $error');
  }
}

Widget studyGlassPageScope(BuildContext context, Widget child) => CupertinoTheme(
  data: MaterialBasedCupertinoThemeData(materialTheme: Theme.of(context)), child: child);

lg.LiquidGlassSettings _settings(BuildContext context, {Color? tint, double blur = 8}) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return lg.LiquidGlassSettings(blur: blur, thickness: 24,
    glassColor: tint ?? (dark ? const Color(0x66363B40) : const Color(0x55FFFFFF)));
}

class _GlassSurfaceScope extends InheritedWidget {
  const _GlassSurfaceScope({required super.child});
  static bool contains(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_GlassSurfaceScope>() != null;
  @override
  bool updateShouldNotify(_GlassSurfaceScope oldWidget) => false;
}

/// Paint the glass behind, rather than around, other refractive controls.
/// This avoids GlassCard suppressing the effects of its descendants.
class GlassSurface extends StatelessWidget {
  const GlassSurface({super.key, required this.child, this.radius = 28,
    this.color, this.quality = lg.GlassQuality.standard});
  final Widget child;
  final double radius;
  final Color? color;
  final lg.GlassQuality quality;

  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned.fill(child: IgnorePointer(child: lg.GlassCard(
      padding: EdgeInsets.zero, useOwnLayer: true,
      quality: _shadersReady ? quality : lg.GlassQuality.minimal,
      shape: lg.LiquidRoundedSuperellipse(borderRadius: radius),
      settings: _settings(context, tint: color,
        blur: quality == lg.GlassQuality.minimal ? 0 : 8),
    ))),
    _GlassSurfaceScope(child: Material(type: MaterialType.transparency, child: DefaultTextStyle.merge(
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface), child: child))),
  ]);
}

enum _ButtonKind { text, filled, outlined }

/// Keeps existing callbacks and stateful ButtonStyle values while rendering a
/// real GlassButton. Content determines height, including large multiline text.
class StudyButton extends StatelessWidget {
  const StudyButton.text({super.key, required this.onPressed, required this.child,
    this.style}) : kind = _ButtonKind.text, icon = null;
  const StudyButton.filled({super.key, required this.onPressed, required this.child,
    this.style}) : kind = _ButtonKind.filled, icon = null;
  const StudyButton.outlined({super.key, required this.onPressed, required this.child,
    this.style}) : kind = _ButtonKind.outlined, icon = null;
  const StudyButton.textIcon({super.key, required this.onPressed, required Widget label,
    required this.icon, this.style}) : child = label, kind = _ButtonKind.text;
  const StudyButton.filledIcon({super.key, required this.onPressed, required Widget label,
    required this.icon, this.style}) : child = label, kind = _ButtonKind.filled;
  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final ButtonStyle? style;
  final _ButtonKind kind;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highContrast = MediaQuery.highContrastOf(context);
    final states = <WidgetState>{if (onPressed == null) WidgetState.disabled};
    final foreground = highContrast
      ? (kind == _ButtonKind.filled ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface)
      : style?.foregroundColor?.resolve(states) ?? theme.colorScheme.primary;
    final background = style?.backgroundColor?.resolve(states);
    final side = style?.side?.resolve(states);
    final size = style?.minimumSize?.resolve(states) ??
      const Size(104, 48);
    final padding = style?.padding?.resolve(states) ??
      const EdgeInsets.symmetric(horizontal: 14, vertical: 10);
    final alignment = style?.alignment ?? Alignment.center;
    final shape = style?.shape?.resolve(states);
    final radius = shape is RoundedRectangleBorder
      ? shape.borderRadius.resolve(Directionality.of(context)).topLeft.x : 18.0;
    final textStyle = (theme.textTheme.labelLarge ?? const TextStyle(fontSize: 14))
      .merge(style?.textStyle?.resolve(states)).copyWith(color: foreground);
    final button = lg.GlassButton.custom(
      onTap: onPressed ?? () {}, enabled: onPressed != null,
      style: kind == _ButtonKind.filled ? lg.GlassButtonStyle.prominent : lg.GlassButtonStyle.filled,
      shape: lg.LiquidRoundedSuperellipse(borderRadius: radius,
        side: side ?? BorderSide.none),
      useOwnLayer: true, quality: studyGlassControlQuality,
      settings: _settings(context, tint: highContrast
        ? (kind == _ButtonKind.filled ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest)
        : background == null ?
        (kind == _ButtonKind.filled ? theme.colorScheme.primary.withValues(alpha: .24) : null) :
        background.withValues(alpha: math.min(background.a, .32))),
      // Keep taps from turning into a drag when used inside scrolling lessons.
      stretch: 0, anchorStretch: false, persistPressOnDrag: false,
      alignment: alignment,
      child: ConstrainedBox(constraints: BoxConstraints(minWidth: size.width, minHeight: size.height),
        child: Padding(padding: padding, child: Align(
          alignment: alignment, widthFactor: 1, heightFactor: 1,
          child: DefaultTextStyle.merge(style: textStyle,
          textAlign: alignment == Alignment.center ? TextAlign.center : TextAlign.start,
          child: IconTheme.merge(data: IconThemeData(color: foreground, size: 20),
            child: icon == null ? child : Row(mainAxisSize: MainAxisSize.min, children: [
              icon!, const SizedBox(width: 6), Flexible(child: child),
            ]))))),
      ),
    );
    // Preserve answer-state borders independently of the shader's rim light.
    final decorated = side == null ? button : DecoratedBox(position: DecorationPosition.foreground,
      decoration: ShapeDecoration(shape: lg.LiquidRoundedSuperellipse(borderRadius: radius, side: side)),
      child: button);
    // Let an enclosing double-tap recognizer receive completed-state gestures.
    return IgnorePointer(ignoring: onPressed == null, child: decorated);
  }
}

class StudyIconButton extends StatelessWidget {
  const StudyIconButton({super.key, required this.icon, required this.onPressed,
    this.tooltip, this.color, this.iconSize, this.constraints, this.padding = const EdgeInsets.all(8)}) : showBackground = true, showPressHighlight = true;
  const StudyIconButton.filledTonal({super.key, required this.icon, required this.onPressed,
    this.tooltip, this.color, this.iconSize, this.constraints, this.padding = const EdgeInsets.all(8)}) : showBackground = true, showPressHighlight = true;
  const StudyIconButton.transparent({super.key, required this.icon, required this.onPressed,
    this.tooltip, this.color, this.iconSize, this.constraints, this.padding = EdgeInsets.zero,
    this.showPressHighlight = true}) : showBackground = false;
  final Widget icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? color;
  final double? iconSize;
  final BoxConstraints? constraints;
  final EdgeInsetsGeometry padding;
  final bool showBackground;
  final bool showPressHighlight;

  @override
  Widget build(BuildContext context) {
    final width = constraints?.hasBoundedWidth == true ? constraints!.maxWidth : 44.0;
    final height = constraints?.hasBoundedHeight == true ? constraints!.maxHeight : 44.0;
    Widget button = SizedBox(width: width, height: height, child: lg.GlassButton.custom(
      onTap: onPressed ?? () {}, enabled: onPressed != null,
      label: tooltip ?? '', useOwnLayer: true, quality: studyGlassControlQuality,
      style: showBackground ? lg.GlassButtonStyle.filled : lg.GlassButtonStyle.transparent,
      ambientBaseLight: showPressHighlight ? null : 0,
      glowColor: showPressHighlight ? null : Colors.transparent,
      shape: const lg.LiquidOval(), settings: _settings(context),
      stretch: 0, anchorStretch: false, persistPressOnDrag: false,
      child: Center(child: Padding(padding: padding, child: IconTheme.merge(
        data: IconThemeData(color: color ?? Theme.of(context).colorScheme.primary, size: iconSize ?? 24),
        child: icon))),
    ));
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}

class StudySpeedButton extends StatelessWidget {
  const StudySpeedButton({super.key, required this.speed, required this.onPressed});
  final double speed;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => StudyIconButton.transparent(
    tooltip: '播放速度', onPressed: onPressed,
    icon: FittedBox(fit: BoxFit.scaleDown, child: Text(speed.toStringAsFixed(1),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary))),
  );
}

Future<T?> showGlassDialog<T>({required BuildContext context, required WidgetBuilder builder,
  bool barrierDismissible = true}) => showDialog<T>(
  context: context, builder: builder, barrierDismissible: barrierDismissible,
  barrierColor: Colors.black.withValues(alpha: .20),
  animationStyle: MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation
    : const AnimationStyle(duration: Duration(milliseconds: 180), reverseDuration: Duration(milliseconds: 140)),
);

/// Custom layout on library surfaces: the stock GlassDialog fixes buttons to
/// 44pt and a horizontal row, which is unsuitable for our scalable Chinese text.
class GlassAlertDialog extends StatelessWidget {
  const GlassAlertDialog({super.key, required this.title, required this.content, required this.actions});
  final Widget title, content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent,
      elevation: 0, insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
        child: GlassSurface(child: SingleChildScrollView(padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(namesRoute: true, header: true, child: DefaultTextStyle(
              style: theme.textTheme.titleLarge!.copyWith(fontSize: 20, fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface), child: title)),
            const SizedBox(height: 16),
            DefaultTextStyle(style: theme.textTheme.bodyLarge!.copyWith(height: 1.5,
              color: theme.colorScheme.onSurface), child: content),
            const SizedBox(height: 24),
            if (actions.isNotEmpty) LayoutBuilder(builder: (context, constraints) {
              const spacing = 12.0;
              final minimumWidth = 104 * math.max(1.0, MediaQuery.textScalerOf(context).scale(14) / 14);
              final rowWidth = (constraints.maxWidth - spacing * (actions.length - 1)) / actions.length;
              final width = rowWidth >= minimumWidth ? rowWidth : constraints.maxWidth;
              return Wrap(alignment: WrapAlignment.end, spacing: spacing, runSpacing: 10,
                children: [for (final action in actions) SizedBox(width: width, child: action)]);
            }),
          ]))),
      ));
  }
}

Future<T?> showGlassBottomSheet<T>({required BuildContext context, required WidgetBuilder builder,
  bool showDragHandle = true, bool isScrollControlled = true}) => showModalBottomSheet<T>(
  context: context, isScrollControlled: isScrollControlled, useSafeArea: true,
  backgroundColor: Colors.transparent, elevation: 0, showDragHandle: false,
  barrierColor: Colors.black.withValues(alpha: .20),
  sheetAnimationStyle: MediaQuery.disableAnimationsOf(context) ? AnimationStyle.noAnimation
    : const AnimationStyle(duration: Duration(milliseconds: 220), reverseDuration: Duration(milliseconds: 180)),
  builder: (sheetContext) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
    child: lg.GlassSheet(quality: studyGlassControlQuality, settings: _settings(sheetContext),
      showDragIndicator: showDragHandle, stretch: 0, interactionScale: 1,
      child: builder(sheetContext)),
  ),
);

// Retain ScaffoldMessenger's queue, route lifetime, dismissal and live region.
class GlassSnackBar extends SnackBar {
  GlassSnackBar({super.key, required Widget content, super.duration = const Duration(seconds: 4)}) : super(
    backgroundColor: Colors.transparent, elevation: 0, behavior: SnackBarBehavior.floating,
    padding: EdgeInsets.zero,
    content: GlassSurface(radius: 20,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14), child: content)),
  );
}

class StudyCard extends StatelessWidget {
  const StudyCard({super.key, required this.child, this.color, this.margin,
    this.shape, this.clipBehavior = Clip.none, this.elevation});
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry? margin;
  final ShapeBorder? shape;
  final Clip clipBehavior;
  final double? elevation;
  @override
  Widget build(BuildContext context) {
    final border = shape;
    final radius = border is RoundedRectangleBorder
      ? border.borderRadius.resolve(Directionality.of(context)).topLeft.x : 20.0;
    Widget result = GlassSurface(radius: radius, quality: lg.GlassQuality.minimal,
      color: color?.withValues(alpha: .45), child: child);
    if (border != null) result = DecoratedBox(position: DecorationPosition.foreground,
      decoration: ShapeDecoration(shape: border), child: result);
    if (clipBehavior != Clip.none) result = ClipRRect(borderRadius: BorderRadius.circular(radius),
      clipBehavior: clipBehavior, child: result);
    return Padding(padding: margin ?? const EdgeInsets.all(4), child: result);
  }
}

/// Surface adapter for bespoke lesson, grammar and drag-and-drop panels.
class StudyPanel extends StatelessWidget {
  const StudyPanel({super.key, required this.child, this.color, this.shape,
    this.borderRadius, this.clipBehavior = Clip.none});
  final Widget child;
  final Color? color;
  final ShapeBorder? shape;
  final BorderRadiusGeometry? borderRadius;
  final Clip clipBehavior;
  @override
  Widget build(BuildContext context) => StudyCard(margin: EdgeInsets.zero,
    color: color, clipBehavior: clipBehavior,
    shape: shape ?? RoundedRectangleBorder(borderRadius: borderRadius ?? BorderRadius.circular(18)),
    child: child);
}

class StudyDivider extends StatelessWidget {
  const StudyDivider({super.key, this.height = 16, this.thickness = 1,
    this.indent = 0, this.endIndent = 0, this.color});
  final double height, thickness, indent, endIndent;
  final Color? color;
  @override
  Widget build(BuildContext context) => lg.GlassDivider(height: height, thickness: thickness,
    indent: indent, endIndent: endIndent, color: color ?? Theme.of(context).colorScheme.outlineVariant);
}

class StudyInkWell extends StatelessWidget {
  const StudyInkWell({super.key, required this.child, this.onTap, this.onLongPress,
    this.borderRadius, this.splashColor, this.highlightColor});
  final Widget child;
  final VoidCallback? onTap, onLongPress;
  final BorderRadius? borderRadius;
  final Color? splashColor, highlightColor;
  @override
  Widget build(BuildContext context) {
    final insideSurface = _GlassSurfaceScope.contains(context);
    return LayoutBuilder(builder: (context, constraints) {
      // Both glass branches loosen child constraints. Keep the original
      // InkWell extent in enabled and busy states, including grid cells.
      final content = ConstrainedBox(constraints: BoxConstraints(
        minWidth: constraints.minWidth, minHeight: constraints.minHeight), child: child);
      if (onTap == null && onLongPress == null) {
        // Non-interactive lesson groups must remain readable at full opacity.
        return insideSurface ? content : GlassSurface(radius: borderRadius?.topLeft.x ?? 16,
          quality: lg.GlassQuality.minimal, child: content);
      }
      Widget result = lg.GlassButton.custom(onTap: onTap ?? () {},
        enabled: onTap != null, useOwnLayer: true, quality: lg.GlassQuality.minimal,
        style: insideSurface ? lg.GlassButtonStyle.transparent : lg.GlassButtonStyle.filled,
        settings: _settings(context, blur: 0), shape: lg.LiquidRoundedSuperellipse(borderRadius: borderRadius?.topLeft.x ?? 16),
        alignment: Alignment.centerLeft, stretch: 0, anchorStretch: false,
        persistPressOnDrag: false, child: content);
      if (onLongPress != null) result = GestureDetector(onLongPress: onLongPress, child: result);
      return result;
    });
  }
}

class StudyListTile extends StatelessWidget {
  const StudyListTile({super.key, required this.title, this.subtitle, this.leading, this.trailing,
    this.onTap, this.contentPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    this.minLeadingWidth = 24, this.horizontalTitleGap = 16});
  final Widget title;
  final Widget? subtitle, leading, trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry contentPadding;
  final double minLeadingWidth, horizontalTitleGap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(padding: contentPadding, child: Row(children: [
      if (leading != null) ...[ConstrainedBox(constraints: BoxConstraints(minWidth: minLeadingWidth),
        child: leading!), SizedBox(width: horizontalTitleGap)],
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        DefaultTextStyle.merge(style: theme.textTheme.titleMedium, child: title),
        if (subtitle != null) ...[const SizedBox(height: 4),
          DefaultTextStyle.merge(style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant), child: subtitle!)],
      ])),
      if (trailing != null) ...[const SizedBox(width: 12), trailing!],
    ]));
    return onTap == null ? row : StudyInkWell(onTap: onTap, child: row);
  }
}

class StudySwitchListTile extends StatelessWidget {
  const StudySwitchListTile({super.key, required this.title, required this.value,
    required this.onChanged, this.subtitle, this.secondary,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12)});
  final Widget title;
  final Widget? subtitle, secondary;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry contentPadding;
  @override
  Widget build(BuildContext context) => MergeSemantics(child: GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    child: StudyListTile(title: title, subtitle: subtitle,
    leading: secondary, contentPadding: contentPadding,
    trailing: Semantics(enabled: onChanged != null,
      child: IgnorePointer(ignoring: onChanged == null, child: Opacity(opacity: onChanged == null ? .45 : 1,
        child: SizedBox(height: 44, child: Center(child: lg.GlassSwitch(value: value,
          onChanged: onChanged ?? (_) {}, useOwnLayer: true, quality: studyGlassControlQuality,
          activeColor: Theme.of(context).colorScheme.primary)))))))));
}

class StudySlider extends StatelessWidget {
  const StudySlider({super.key, required this.value, required this.onChanged,
    this.min = 0, this.max = 1, this.divisions, this.label});
  final double value, min, max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  @override
  Widget build(BuildContext context) => lg.GlassSlider(value: value, onChanged: onChanged,
    min: min, max: max, divisions: divisions, label: label, useOwnLayer: true,
    activeColor: Theme.of(context).colorScheme.primary, quality: studyGlassControlQuality);
}

class StudySegments<T> extends StatelessWidget {
  const StudySegments({super.key, required this.values, required this.selected,
    required this.onChanged});
  final Map<T, String> values;
  final T selected;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList();
    return LayoutBuilder(builder: (context, bounds) {
      final text = MediaQuery.textScalerOf(context).scale(14);
      final height = math.max(44.0, text * 1.6 + 16);
      final minWidth = entries.fold<double>(0, (sum, e) => sum + e.value.length * text + 28);
      final theme = Theme.of(context);
      final control = lg.GlassSegmentedControl(
        segments: [for (final e in entries) lg.GlassSegment(label: e.value)],
        selectedIndex: entries.indexWhere((e) => e.key == selected),
        onSegmentSelected: (i) => onChanged(entries[i].key), height: height,
        useOwnLayer: true, quality: studyGlassControlQuality,
        selectedTextStyle: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: theme.colorScheme.primary),
        unselectedTextStyle: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
        indicatorColor: theme.colorScheme.primary.withValues(alpha: .18),
      );
      if (bounds.hasBoundedWidth && bounds.maxWidth < minWidth) {
        return SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: control));
      }
      return control;
    });
  }
}

class StudyChoiceChip extends StatelessWidget {
  const StudyChoiceChip({super.key, required this.label, required this.selected,
    required this.onSelected, this.labelStyle, this.backgroundColor, this.selectedColor,
    this.side, this.padding = EdgeInsets.zero, this.labelPadding = const EdgeInsets.symmetric(horizontal: 8),
    this.materialTapTargetSize, this.showCheckmark = false, this.shape});
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final TextStyle? labelStyle;
  final Color? backgroundColor, selectedColor;
  final BorderSide? side;
  final EdgeInsetsGeometry padding, labelPadding;
  final MaterialTapTargetSize? materialTapTargetSize;
  final bool showCheckmark;
  final OutlinedBorder? shape;
  @override
  Widget build(BuildContext context) {
    final button = selected ? StudyButton.filled : StudyButton.outlined;
    return Semantics(selected: selected,
    child: button(onPressed: onSelected == null ? null : () => onSelected!(!selected),
      style: TextButton.styleFrom(backgroundColor: selected ? selectedColor : backgroundColor,
        side: side, padding: padding.add(labelPadding), textStyle: labelStyle,
        foregroundColor: labelStyle?.color, shape: shape,
        minimumSize: const Size(44, 44)), child: label));
  }
}

class StudyExpansionTile extends StatefulWidget {
  const StudyExpansionTile({super.key, required this.title, required this.children,
    this.subtitle, this.initiallyExpanded = false, this.shape, this.collapsedShape,
    this.tilePadding = const EdgeInsets.all(16), this.childrenPadding = EdgeInsets.zero});
  final Widget title;
  final Widget? subtitle;
  final List<Widget> children;
  final bool initiallyExpanded;
  final ShapeBorder? shape, collapsedShape;
  final EdgeInsetsGeometry tilePadding, childrenPadding;
  @override
  State<StudyExpansionTile> createState() => _StudyExpansionTileState();
}

class _StudyExpansionTileState extends State<StudyExpansionTile> {
  late bool expanded;
  @override
  void initState() {
    super.initState();
    expanded = PageStorage.maybeOf(context)?.readState(context) as bool? ?? widget.initiallyExpanded;
  }
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Semantics(expanded: expanded, child: StudyListTile(title: widget.title,
      subtitle: widget.subtitle, contentPadding: widget.tilePadding,
      trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
      onTap: () {
        setState(() => expanded = !expanded);
        PageStorage.maybeOf(context)?.writeState(context, expanded);
      })),
    AnimatedSize(duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),
      alignment: Alignment.topCenter,
      child: expanded ? Padding(padding: widget.childrenPadding,
        child: Column(mainAxisSize: MainAxisSize.min, children: widget.children)) : const SizedBox.shrink()),
  ]);
}

/// Retains the approved three-sector geometry and the three setting colours.
/// The shared library surface supplies glass; state changes animate the tint.
class StudyGlassLogo extends StatelessWidget {
  const StudyGlassLogo({super.key});

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: 128,
    child: DecoratedBox(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 16, offset: Offset(0, 6))]),
      child: ClipRRect(borderRadius: BorderRadius.circular(24), child: Stack(fit: StackFit.expand, children: [
        Image.asset('assets/branding/app-icon.png', fit: BoxFit.cover, semanticLabel: '语之初 App 图标'),
        IgnorePointer(child: lg.AdaptiveGlass(
          shape: const lg.LiquidRoundedSuperellipse(borderRadius: 24),
          settings: _settings(context, tint: const Color(0x0DFFFFFF), blur: 0),
          quality: studyGlassControlQuality, useOwnLayer: true,
          child: const SizedBox.expand())),
        IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x99FFFFFF), width: .8),
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [Color(0x66FFFFFF), Color(0x18FFFFFF), Colors.transparent, Color(0x18000000)],
            stops: [0, .35, .6, 1])))),
      ])),
    ));
}

class StudyDisplayRingIcon extends StatelessWidget {
  const StudyDisplayRingIcon({super.key, required this.source, required this.ruby,
    required this.translation});
  final bool source, ruby, translation;
  @override
  Widget build(BuildContext context) {
    final values = [source, ruby, translation];
    const colors = [Color(0xFFB55343), Color(0xFF32AA43), Color(0xFF397CC6)];
    return SizedBox.square(dimension: 38, child: Stack(children: [
      Positioned.fill(child: ClipPath(clipper: const _RingClipper(),
        child: lg.AdaptiveGlass(shape: const lg.LiquidOval(), settings: _settings(context),
          quality: studyGlassControlQuality, useOwnLayer: true, child: const SizedBox.expand()))),
      for (var i = 0; i < 3; i++) Positioned.fill(child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: values[i] ? 1 : 0),
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
        builder: (context, activity, _) => CustomPaint(painter: _RingTintPainter(
          i, Color.lerp(Colors.grey.shade600, colors[i], activity)!, activity)),
      )),
    ]));
  }
}

Path _ringSector(Size size, int index) {
  final scale = math.min(size.width, size.height) / 27;
  final center = Offset(size.width / 2, size.height / 2);
  const outer = 12.75, inner = 5.75, corner = 1.2, gap = 3.8;
  final outerRect = Rect.fromCircle(center: center, radius: outer * scale);
  final innerRect = Rect.fromCircle(center: center, radius: inner * scale);
  Offset point(double radius, double angle) => center + Offset(math.cos(angle), math.sin(angle)) * (radius * scale);
  Offset toward(Offset from, Offset to) => from + (to - from) * (corner * scale / (to - from).distance);
  final start = -math.pi / 2 + index * math.pi * 2 / 3;
  final end = start + math.pi * 2 / 3;
  final outerStart = start + math.asin(gap / 2 / outer);
  final innerStart = start + math.asin(gap / 2 / inner);
  final outerEnd = end - math.asin(gap / 2 / outer);
  final innerEnd = end - math.asin(gap / 2 / inner);
  final outerA = point(outer, outerStart), innerA = point(inner, innerStart);
  final outerB = point(outer, outerEnd), innerB = point(inner, innerEnd);
  final first = point(outer, outerStart + corner / outer);
  final path = Path()..moveTo(first.dx, first.dy)
    ..arcTo(outerRect, outerStart + corner / outer, outerEnd - outerStart - 2 * corner / outer, false);
  void rounded(Offset control, Offset destination) => path.quadraticBezierTo(control.dx, control.dy, destination.dx, destination.dy);
  rounded(outerB, toward(outerB, innerB));
  final endFace = toward(innerB, outerB);
  path.lineTo(endFace.dx, endFace.dy);
  rounded(innerB, point(inner, innerEnd - corner / inner));
  path.arcTo(innerRect, innerEnd - corner / inner, innerStart - innerEnd + 2 * corner / inner, false);
  rounded(innerA, toward(innerA, outerA));
  final startFace = toward(outerA, innerA);
  path.lineTo(startFace.dx, startFace.dy);
  rounded(outerA, first);
  return path..close();
}

class _RingClipper extends CustomClipper<Path> {
  const _RingClipper();
  @override
  Path getClip(Size size) {
    final path = Path();
    for (var i = 0; i < 3; i++) { path.addPath(_ringSector(size, i), Offset.zero); }
    return path;
  }
  @override
  bool shouldReclip(_RingClipper oldClipper) => false;
}

class _RingTintPainter extends CustomPainter {
  const _RingTintPainter(this.index, this.color, this.activity);
  final int index;
  final Color color;
  final double activity;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = _ringSector(size, index);
    // Give each segment its own lighting bounds, including the inner rim and ends.
    final bounds = path.getBounds();
    final scale = math.min(size.width, size.height) / 38;
    final tintOpacity = .65 + .35 * activity;
    final highlightOpacity = .18 + .82 * activity;
    Color highlight(Color value) => value.withValues(alpha: value.a * highlightOpacity);
    canvas.drawPath(path, Paint()..shader = LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight,
      colors: [Color.lerp(color, Colors.white, .12 + .36 * activity)!.withValues(alpha: .62 * tintOpacity),
        color.withValues(alpha: .52 * tintOpacity), color.withValues(alpha: .74 * tintOpacity),
        Color.lerp(color, Colors.black, .18)!.withValues(alpha: .86 * tintOpacity)],
      stops: const [0, .32, .65, 1]).createShader(bounds));
    canvas.save();
    canvas.clipPath(path);
    // A broad reflection and a narrow inner bevel suggest curved glass surfaces.
    canvas.drawRect(bounds, Paint()..shader = RadialGradient(
      center: const Alignment(-.55, -.75), radius: 1.05,
      colors: [highlight(const Color(0x99FFFFFF)), highlight(const Color(0x24FFFFFF)), Colors.transparent],
      stops: const [0, .40, 1]).createShader(bounds));
    canvas.drawPath(path.shift(Offset(-.65 * scale, -.85 * scale)),
      Paint()..style = PaintingStyle.stroke..strokeWidth = 1.8 * scale
        ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Colors.transparent, color.withValues(alpha: .08 * tintOpacity),
            Color.lerp(color, Colors.black, .45)!.withValues(alpha: .42 * tintOpacity)],
          stops: const [0, .45, 1]).createShader(bounds));
    canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4 * scale
      ..shader = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [highlight(const Color(0xEEFFFFFF)), highlight(const Color(0x88FFFFFF)),
          highlight(const Color(0x10FFFFFF)), highlight(const Color(0x99FFFFFF))],
        stops: const [0, .30, .65, 1]).createShader(bounds));
    canvas.restore();
  }
  @override
  bool shouldRepaint(_RingTintPainter oldDelegate) => index != oldDelegate.index ||
    color != oldDelegate.color || activity != oldDelegate.activity;
}

class StudyAppBar extends StatelessWidget implements PreferredSizeWidget {
  const StudyAppBar({super.key, this.title, this.leading, this.actions, this.centerTitle = true,
    this.backgroundColor});
  final Widget? title, leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final Color? backgroundColor;
  @override
  Size get preferredSize => const Size.fromHeight(56);
  @override
  Widget build(BuildContext context) => CupertinoTheme(
    data: MaterialBasedCupertinoThemeData(materialTheme: Theme.of(context)),
    child: lg.GlassAppBar(title: title == null ? null : DefaultTextStyle.merge(
      style: Theme.of(context).textTheme.titleMedium!.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      child: title!), centerTitle: centerTitle, toolbarHeight: 56,
      leading: leading ?? (Navigator.of(context).canPop() ? StudyIconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: () => Navigator.of(context).maybePop()) : null),
      actions: actions, backgroundColor: backgroundColor?.withValues(alpha: .18) ?? Colors.transparent),
  );
}

class StudyCircularProgressIndicator extends StatelessWidget {
  const StudyCircularProgressIndicator({super.key, this.value, this.strokeWidth = 4,
    this.color, this.backgroundColor});
  final double? value;
  final double strokeWidth;
  final Color? color, backgroundColor;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, bounds) =>
    lg.GlassProgressIndicator.circular(value: value, strokeWidth: strokeWidth,
      size: bounds.hasTightWidth && bounds.hasTightHeight
        ? math.min(bounds.maxWidth, bounds.maxHeight) : 36,
      color: color ?? Theme.of(context).colorScheme.primary, backgroundColor: backgroundColor,
      useOwnLayer: true, quality: lg.GlassQuality.minimal));
}

class StudyLinearProgressIndicator extends StatelessWidget {
  const StudyLinearProgressIndicator({super.key, this.value, this.minHeight = 4,
    this.color, this.backgroundColor});
  final double? value;
  final double minHeight;
  final Color? color, backgroundColor;
  @override
  Widget build(BuildContext context) => lg.GlassProgressIndicator.linear(value: value,
    height: minHeight, minWidth: 0, color: color ?? Theme.of(context).colorScheme.primary,
    backgroundColor: backgroundColor, useOwnLayer: true, quality: lg.GlassQuality.minimal);
}

class StudyGlassLicensesPage extends StatefulWidget {
  const StudyGlassLicensesPage({super.key});
  @override
  State<StudyGlassLicensesPage> createState() => _StudyGlassLicensesPageState();
}

class _StudyGlassLicensesPageState extends State<StudyGlassLicensesPage> {
  late final Future<String> notices = rootBundle.loadString('assets/licenses/liquid_glass_widgets.txt');
  @override
  Widget build(BuildContext context) => PlaybackScaffold(
    appBar: const StudyAppBar(title: Text('玻璃组件开源许可')),
    body: SafeArea(top: false, child: FutureBuilder<String>(future: notices,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Center(child: Text('许可信息暂时无法读取。'));
        if (!snapshot.hasData) return const Center(child: StudyCircularProgressIndicator());
        return SingleChildScrollView(padding: const EdgeInsets.all(20),
          child: SelectableText(snapshot.data!, style: Theme.of(context).textTheme.bodySmall));
      })),
  );
}
