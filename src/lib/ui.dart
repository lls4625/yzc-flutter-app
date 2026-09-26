import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart' as lg;
import 'glass_ui.dart';
export 'glass_ui.dart';

const vermilion = Color(0xFFC94F3D);
const indigo = Color(0xFF344966);

ThemeData studyTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: vermilion,
      brightness: brightness,
      surface: dark ? const Color(0xFF171817) : const Color(0xFFF8F4EC),
    );
    final baseText = ThemeData(brightness: brightness).textTheme.apply(
      fontFamily: 'PingFang SC',
      fontFamilyFallback: const ['Hiragino Sans'],
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: 'PingFang SC',
      fontFamilyFallback: const ['Hiragino Sans'],
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      // Interface hierarchy; lesson text and ruby retain their reading sizes.
      textTheme: baseText.copyWith(
        displayMedium: baseText.displayMedium?.copyWith(fontSize: 36, fontWeight: FontWeight.w700),
        displaySmall: baseText.displaySmall?.copyWith(fontSize: 32, fontWeight: FontWeight.w700),
        headlineMedium: baseText.headlineMedium?.copyWith(fontSize: 24, fontWeight: FontWeight.w700),
        headlineSmall: baseText.headlineSmall?.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
        titleLarge: baseText.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
        labelLarge: baseText.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
        bodyMedium: baseText.bodyMedium?.copyWith(fontSize: 15),
        bodySmall: baseText.bodySmall?.copyWith(fontSize: 13),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF222322) : const Color(0xFFFFFCF7),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: .55)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 70,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

/// Visual order differs from the existing page indices in the app shell.
const _studyNavigationPageIndices = [0, 1, 4, 2, 3];
const _studyNavigationBarHeight = 70.0;
const _studyNavigationIconSize = 24.0;
const _studyRoomIconSize = 44.0;

class StudyNavigationBar extends StatelessWidget {
  const StudyNavigationBar({super.key, required this.selectedIndex,
    required this.isStudyRoomUnlocked, required this.onDestinationSelected});
  final int selectedIndex;
  final bool isStudyRoomUnlocked;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget navigationIcon(IconData icon) => SizedBox.square(
      dimension: _studyRoomIconSize,
      child: Align(alignment: Alignment.bottomCenter,
        child: Icon(icon, size: _studyNavigationIconSize)));
    lg.GlassTab navigationTab(IconData icon, IconData activeIcon, String label) => lg.GlassTab(
      icon: navigationIcon(icon), activeIcon: navigationIcon(activeIcon),
      label: label);
    return SafeArea(top: false, child: lg.GlassTabBar.bottom(
      selectedIndex: _studyNavigationPageIndices.indexOf(selectedIndex),
      onTabSelected: (index) => onDestinationSelected(_studyNavigationPageIndices[index]),
      horizontalPadding: 8, verticalPadding: 0,
      barHeight: _studyNavigationBarHeight,
      pressScale: 1.0,
      iconLabelSpacing: 3, iconSize: _studyNavigationIconSize, labelFontSize: 12,
      selectedLabelStyle: const TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontSize: 12, height: 1.2, fontWeight: FontWeight.w500),
      selectedIconColor: scheme.primary, unselectedIconColor: scheme.onSurfaceVariant,
      selectedLabelColor: scheme.primary, unselectedLabelColor: scheme.onSurfaceVariant,
      quality: studyGlassControlQuality, backgroundQuality: lg.GlassQuality.minimal,
      tabs: [
        navigationTab(Icons.home_outlined, Icons.home, '首页'),
        navigationTab(Icons.route_outlined, Icons.route, '课程'),
        lg.GlassTab(icon: _StudyRoomNavigationIcon(isUnlocked: isStudyRoomUnlocked),
          label: '自习室', semanticLabel: '自习室，${isStudyRoomUnlocked ? '已解锁' : '未解锁'}'),
        navigationTab(Icons.refresh_rounded, Icons.refresh_rounded, '复习'),
        navigationTab(Icons.person_outline, Icons.person, '我的'),
      ],
    ));
  }
}

class _StudyRoomNavigationIcon extends StatelessWidget {
  const _StudyRoomNavigationIcon({required this.isUnlocked});
  final bool isUnlocked;

  @override
  Widget build(BuildContext context) => SizedBox.square(dimension: _studyRoomIconSize,
    child: CustomPaint(painter: _StudyRoomIconPainter(
      IconTheme.of(context).color ?? Theme.of(context).colorScheme.primary, isUnlocked)));
}

/// A transparent book: closed while locked, layered open pages when unlocked.
class _StudyRoomIconPainter extends CustomPainter {
  const _StudyRoomIconPainter(this.color, this.isUnlocked);
  final Color color;
  final bool isUnlocked;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 68, size.height / 68);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (!isUnlocked) {
      // Upright cover with a deeper page block and horizontal page edges.
      canvas.drawPath(Path()
        ..moveTo(21, 14)
        ..lineTo(51, 14)
        ..quadraticBezierTo(54, 14, 54, 17)
        ..lineTo(54, 59)
        ..lineTo(21, 59)
        ..quadraticBezierTo(14, 59, 14, 52)
        ..lineTo(14, 21)
        ..quadraticBezierTo(14, 14, 21, 14), stroke);
      canvas.drawPath(Path()
        ..moveTo(22, 14)
        ..lineTo(22, 45)
        ..lineTo(54, 45), stroke);
      canvas.drawPath(Path()
        ..moveTo(22, 45)
        ..quadraticBezierTo(14, 45, 14, 52), stroke);
      for (final y in [49.0, 53.0, 56.0]) {
        canvas.drawLine(Offset(23, y), Offset(50, y), stroke);
      }
      canvas.drawLine(const Offset(29, 26), const Offset(45, 26), stroke);
      canvas.restore();
      return;
    }

    // Three separated page edges on each side keep the extra leaves visible.
    for (final offset in [0.0, 5.0, 10.0]) {
      canvas.drawPath(Path()
        ..moveTo(10, 29 + offset)
        ..lineTo(10, 43 + offset)
        ..quadraticBezierTo(23, 43 + offset, 34, 51 + offset)
        ..quadraticBezierTo(45, 43 + offset, 58, 43 + offset)
        ..lineTo(58, 29 + offset), stroke);
    }
    canvas.drawPath(Path()
      ..moveTo(34, 36)
      ..quadraticBezierTo(25, 28, 15, 27)
      ..lineTo(15, 42)
      ..quadraticBezierTo(25, 43, 34, 51)
      ..quadraticBezierTo(43, 43, 53, 42)
      ..lineTo(53, 27)
      ..quadraticBezierTo(43, 28, 34, 36)
      ..close(), stroke);
    canvas.drawLine(const Offset(34, 36), const Offset(34, 60), stroke);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_StudyRoomIconPainter oldDelegate) =>
    oldDelegate.color != color || oldDelegate.isUnlocked != isUnlocked;
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.controller});
  final List<Widget> children;
  final ScrollController? controller;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: children,
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontSize: 18, fontWeight: FontWeight.w600, height: 1.4),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Equal-height cards that grow with their text instead of fixing a height.
class StudyCardRow extends StatelessWidget {
  const StudyCardRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  );
}

class QuickCard extends StatelessWidget {
  const QuickCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.subtitleColor,
    this.subtitleMaxLines,
  });
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  final Color? subtitleColor;
  final int? subtitleMaxLines;
  @override
  Widget build(BuildContext context) => StudyCard(
    child: InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Center(child: Padding(
        padding: const EdgeInsets.all(17),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(icon, color: vermilion),
            const SizedBox(height: 15),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              maxLines: subtitleMaxLines,
              overflow: subtitleMaxLines == null ? null : TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: subtitleColor),
            ),
          ],
        ),
      )),
    ),
  );
}

class StudyStat extends StatelessWidget {
  const StudyStat({required this.value, required this.label});
  final String value, label;
  @override
  Widget build(BuildContext context) => StudyCard(
    child: Center(child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700, color: vermilion),
          ),
          const SizedBox(height: 3),
          Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    )),
  );
}


Widget keepSpace(bool visible, Widget child) => Visibility(
  visible: visible, maintainState: true, maintainAnimation: true, maintainSize: true, child: child,
);

String plainJapanese(String text) => text
    .replaceAllMapped(
      RegExp(r'!([^!\s()]+)\([^)]*\)'),
      (match) => match.group(1)!,
    )
    .replaceAll('!', '')
    .trim();
