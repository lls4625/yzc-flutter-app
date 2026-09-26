import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../playback_scaffold.dart';
import '../../system_errors.dart';
import '../../ui.dart';

class DeveloperTipProduct {
  const DeveloperTipProduct({required this.id, required this.name, required this.price});
  final String id, name, price;

  static DeveloperTipProduct? fromNative(Object? value) {
    if (value is! Map) return null;
    final id = value['id'] as String?;
    final name = value['name'] as String?;
    final price = value['price'] as String?;
    return id == null || name == null || price == null ? null
        : DeveloperTipProduct(id: id, name: name, price: price);
  }
}

class DeveloperTipCelebration {
  const DeveloperTipCelebration({required this.productId, required this.transactionId});
  final String productId, transactionId;

  static DeveloperTipCelebration? fromNative(Object? value) {
    if (value is! Map) return null;
    final productId = value['productId'] as String?;
    final transactionId = value['transactionId'] as String?;
    return productId == null || transactionId == null ? null
        : DeveloperTipCelebration(productId: productId, transactionId: transactionId);
  }
}

/// Dedicated consumable-tip flow. It intentionally shares no entitlement or
/// restore behavior with the study-room non-consumable purchase.
class DeveloperTipController extends ChangeNotifier with WidgetsBindingObserver {
  DeveloperTipController() {
    _channel.setMethodCallHandler(_onNativeCall);
    WidgetsBinding.instance.addObserver(this);
  }

  static const _channel = MethodChannel('yuzhichu/developer_tip');
  static const _displayOrder = [
    'com.javalee.nihongoPath.v31.tip.medium',
    'com.javalee.nihongoPath.v31.tip.small',
    'com.javalee.nihongoPath.v31.tip.xlarge',
    'com.javalee.nihongoPath.v31.tip.large',
    'com.javalee.nihongoPath.v31.tip.strong',
    'com.javalee.nihongoPath.v31.tip.premium',
  ];
  final List<DeveloperTipProduct> _products = [];
  bool _initialized = false, _loading = false, _busy = false, _canPay = false, _disposed = false;
  int _revision = -1;
  String? _message, _thanks, _processingProductId;
  DeveloperTipCelebration? _celebration;

  List<DeveloperTipProduct> get products => List.unmodifiable(_products);
  bool get initialized => _initialized;
  bool get loading => _loading;
  bool get busy => _busy;
  bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  bool get canPay => _canPay;
  String? get message => _message;
  String? get thanks => _thanks;
  String? get processingProductId => _processingProductId;
  DeveloperTipCelebration? get celebration => _celebration;

  void _notify() { if (!_disposed) notifyListeners(); }

  void _apply(Object? value) {
    if (_disposed || value is! Map) return;
    final revision = (value['revision'] as num?)?.toInt() ?? -1;
    if (revision < _revision) return;
    _revision = revision;
    _canPay = value['canPay'] == true;
    _message = value['message'] as String?;
    _thanks = value['thanks'] as String?;
    _celebration = DeveloperTipCelebration.fromNative(value['celebration']);
    final rawProducts = value['products'];
    if (rawProducts is List) {
      final next = rawProducts.map(DeveloperTipProduct.fromNative)
        .whereType<DeveloperTipProduct>().toList()
        ..sort((left, right) => _displayOrder.indexOf(left.id).compareTo(_displayOrder.indexOf(right.id)));
      _products
        ..clear()
        ..addAll(next);
    }
    _initialized = true;
    _notify();
  }

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'state') _apply(call.arguments);
  }

  void _record(Object error, StackTrace stack, String operation) {
    SystemErrors.record(error, stack, module: 'developer_tip', operation: operation);
    _message = error is PlatformException ? error.message ?? '打赏服务暂不可用，请稍后重试' : '打赏服务暂不可用，请稍后重试';
    _notify();
  }

  Future<void> reload() async {
    if (_disposed) return;
    if (!supported) {
      _initialized = true;
      _message = '请在 iPhone 或 iPad 上支持开发者';
      _notify();
      return;
    }
    try {
      _apply(await _channel.invokeMethod<Object?>('refresh'));
    } catch (error, stack) {
      _record(error, stack, '读取打赏服务状态');
    } finally {
      _initialized = true;
      _notify();
    }
    if (!_disposed && _products.isEmpty) unawaited(loadProducts());
  }

  Future<void> loadProducts() async {
    if (_disposed || !supported || _loading || _busy) return;
    _loading = true;
    _message = null;
    _thanks = null;
    _notify();
    try {
      _apply(await _channel.invokeMethod<Object?>('loadProducts'));
    } catch (error, stack) {
      _record(error, stack, '读取打赏内购商品');
    } finally {
      _loading = false;
      _notify();
    }
  }

  Future<void> purchase(DeveloperTipProduct product) async {
    if (_disposed || !supported || _busy || !_canPay || !_products.any((item) => item.id == product.id)) return;
    _busy = true;
    _processingProductId = product.id;
    _message = null;
    _thanks = null;
    _notify();
    try {
      _apply(await _channel.invokeMethod<Object?>('purchase', product.id));
    } catch (error, stack) {
      _record(error, stack, '打赏开发者');
    } finally {
      _busy = false;
      _processingProductId = null;
      _notify();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(reload());
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}

class DeveloperTipPage extends StatefulWidget {
  const DeveloperTipPage(this.tip, {super.key});
  final DeveloperTipController tip;

  @override
  State<DeveloperTipPage> createState() => _DeveloperTipPageState();
}

class _DeveloperTipPageState extends State<DeveloperTipPage> with SingleTickerProviderStateMixin {
  late final AnimationController _fireworkController;
  Timer? _thanksTimer;
  String? _handledTransactionId;
  _TipCelebrationLevel? _level;
  bool _staticThanks = false;

  DeveloperTipController get tip => widget.tip;

  @override
  void initState() {
    super.initState();
    _fireworkController = AnimationController(vsync: this);
    tip.addListener(_onTipChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onTipChanged());
  }

  void _onTipChanged() {
    final event = tip.celebration;
    if (!mounted || event == null || event.transactionId == _handledTransactionId) return;
    final level = _TipCelebrationLevel.forProduct(event.productId);
    if (level == null) return;
    _handledTransactionId = event.transactionId;
    _level = level;
    _staticThanks = MediaQuery.disableAnimationsOf(context) || MediaQuery.accessibleNavigationOf(context);
    _thanksTimer?.cancel();
    _thanksTimer = Timer(const Duration(seconds: 5), _dismissCelebration);
    if (_staticThanks) {
      setState(() {});
    } else {
      _fireworkController.duration = level.duration;
      _fireworkController.forward(from: 0);
      setState(() {});
    }
  }

  void _dismissCelebration() {
    _thanksTimer?.cancel();
    _thanksTimer = null;
    _fireworkController.stop();
    setState(() { _level = null; _staticThanks = false; });
  }

  @override
  void dispose() {
    tip.removeListener(_onTipChanged);
    _thanksTimer?.cancel();
    _fireworkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PlaybackScaffold(
    appBar: StudyAppBar(title: const Text('打赏开发者')),
    body: Stack(children: [
      PageBody(children: [_DeveloperTipContent(tip)]),
      if (_level != null) Positioned.fill(child: _FireworksOverlay(
        level: _level!, controller: _fireworkController, staticThanks: _staticThanks,
        onDismiss: _dismissCelebration,
      )),
    ]),
  );
}

class _DeveloperTipContent extends StatelessWidget {
  const _DeveloperTipContent(this.tip);
  final DeveloperTipController tip;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: tip,
    builder: (context, _) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(top: 22, bottom: 10), child: Text('感谢你的支持',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w600))),
      StudyCard(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('你的每一份鼓励，都是语之初不断完善的动力。'),
          const SizedBox(height: 8),
          Text('打赏为一次性、可重复购买的 App Store 消耗型项目；不解锁额外功能，不可恢复。',
            style: Theme.of(context).textTheme.bodySmall),
        ],
      ))),
      const SizedBox(height: 14),
      if (!tip.initialized || tip.loading) const Center(child: Padding(
        padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
      else if (tip.products.isEmpty) StudyCard(child: Padding(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tip.message ?? '商品暂不可用，请稍后重试'),
          const SizedBox(height: 8),
          StudyButton.outlined(onPressed: tip.busy ? null : tip.loadProducts, child: const Text('重新加载')),
        ],
      )))
      else GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: tip.products.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.24,
        ),
        itemBuilder: (context, index) => _TipCard(
          product: tip.products[index],
          enabled: !tip.busy && tip.canPay,
          processing: tip.processingProductId == tip.products[index].id,
          onTap: () => tip.purchase(tip.products[index]),
        ),
      ),
    ]),
  );
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.product, required this.enabled, required this.processing, required this.onTap});
  final DeveloperTipProduct product;
  final bool enabled, processing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    label: '${product.name}，${product.price}',
    child: StudyCard(child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: enabled ? onTap : null,
        child: SizedBox.expand(child: Center(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(product.name, textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            if (processing) ...[
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 8),
            ],
            Text(product.price, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700)),
          ]),
        ]),
      ))))),
  );
}

class _TipCelebrationLevel {
  const _TipCelebrationLevel(this.productId, this.label, this.style, this.bursts, this.particles, this.duration);
  final String productId, label;
  final _FireworkStyle style;
  final int bursts, particles;
  final Duration duration;

  static const all = [
    _TipCelebrationLevel('com.javalee.nihongoPath.v31.tip.small', '一份鼓励', _FireworkStyle.comet, 1, 40, Duration(milliseconds: 1400)),
    _TipCelebrationLevel('com.javalee.nihongoPath.v31.tip.medium', '暖心支持', _FireworkStyle.heart, 2, 70, Duration(milliseconds: 1800)),
    _TipCelebrationLevel('com.javalee.nihongoPath.v31.tip.large', '特别支持', _FireworkStyle.chrysanthemum, 3, 110, Duration(milliseconds: 2200)),
    _TipCelebrationLevel('com.javalee.nihongoPath.v31.tip.xlarge', '大力支持', _FireworkStyle.waterfall, 5, 170, Duration(milliseconds: 2800)),
    _TipCelebrationLevel('com.javalee.nihongoPath.v31.tip.premium', '顶级鼓励', _FireworkStyle.ring, 7, 240, Duration(milliseconds: 3400)),
    _TipCelebrationLevel('com.javalee.nihongoPath.v31.tip.strong', '夯', _FireworkStyle.grandFinale, 10, 360, Duration(milliseconds: 4500)),
  ];

  static _TipCelebrationLevel? forProduct(String id) {
    for (final level in all) {
      if (level.productId == id) return level;
    }
    return null;
  }
}

enum _FireworkStyle { comet, heart, chrysanthemum, waterfall, ring, grandFinale }

class _FireworksOverlay extends StatefulWidget {
  const _FireworksOverlay({required this.level, required this.controller, required this.staticThanks, required this.onDismiss});
  final _TipCelebrationLevel level;
  final AnimationController controller;
  final bool staticThanks;
  final VoidCallback onDismiss;
  @override
  State<_FireworksOverlay> createState() => _FireworksOverlayState();
}

class _FireworksOverlayState extends State<_FireworksOverlay> {
  late final List<_FireworkParticle> _particles = _FireworkParticle.create(widget.level);

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black.withValues(alpha: .58),
    child: Stack(children: [
      if (!widget.staticThanks) Positioned.fill(child: IgnorePointer(child: CustomPaint(
        painter: _FireworkPainter(widget.controller, widget.level.style, _particles),
      ))),
      Center(child: GlassSurface(radius: 28, child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.favorite_rounded, size: 38),
          const SizedBox(height: 12),
          Text('感谢你的「${widget.level.label}」！', textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(widget.staticThanks ? '感谢你的支持。' : '愿每一份热爱都有回响。', textAlign: TextAlign.center),
          const SizedBox(height: 12),
          StudyButton.text(onPressed: widget.onDismiss, child: Text(widget.staticThanks ? '关闭' : '跳过')),
        ]),
      ))),
    ]),
  );
}

class _FireworkParticle {
  const _FireworkParticle(this.x, this.y, this.angle, this.distance, this.delay, this.color);
  final double x, y, angle, distance, delay;
  final Color color;

  static List<_FireworkParticle> create(_TipCelebrationLevel level) {
    final random = math.Random(level.productId.hashCode);
    const colors = [Color(0xFFFFD166), Color(0xFFFF7B7B), Color(0xFF8DE0D5), Color(0xFFB8A1FF), Color(0xFFFFFFFF)];
    return List.generate(level.particles, (index) {
      final burst = index % level.bursts;
      final x = level.bursts == 1 ? .5 : .15 + .7 * (burst / (level.bursts - 1));
      // Keep the main bursts above the thank-you card, in the upper content area.
      final y = level.style == _FireworkStyle.comet ? .18 : .10 + random.nextDouble() * .16;
      return _FireworkParticle(x, y, random.nextDouble() * math.pi * 2,
        .06 + random.nextDouble() * .17, (burst / level.bursts) * .44 + random.nextDouble() * .08,
        colors[random.nextInt(colors.length)]);
    });
  }
}

class _FireworkPainter extends CustomPainter {
  const _FireworkPainter(this.progress, this.style, this.particles) : super(repaint: progress);
  final Animation<double> progress;
  final _FireworkStyle style;
  final List<_FireworkParticle> particles;

  @override
  void paint(Canvas canvas, Size size) {
    if (style == _FireworkStyle.comet) _paintComet(canvas, size);
    for (final particle in particles) {
      final time = ((progress.value - particle.delay) / (1 - particle.delay)).clamp(0.0, 1.0).toDouble();
      if (time <= 0 || time >= 1) continue;
      final point = switch (style) {
        _FireworkStyle.heart => _heartPoint(particle, time, size),
        _FireworkStyle.waterfall => _waterfallPoint(particle, time, size),
        _FireworkStyle.ring => _ringPoint(particle, time, size),
        _FireworkStyle.grandFinale => _finalePoint(particle, time, size),
        _ => _burstPoint(particle, time, size),
      };
      final color = style == _FireworkStyle.heart
        ? (particle.x < .5 ? const Color(0xFFFF7B7B) : const Color(0xFFFFA1B5))
        : style == _FireworkStyle.waterfall || style == _FireworkStyle.grandFinale
          ? const Color(0xFFFFD166) : particle.color;
      final paint = Paint()..color = color.withValues(alpha: (1 - time) * .95);
      canvas.drawCircle(point, 1.6 + (1 - time) * 2.2, paint);
    }
  }

  Offset _burstPoint(_FireworkParticle particle, double time, Size size) {
    final dx = math.cos(particle.angle) * particle.distance * size.width * time;
    final dy = math.sin(particle.angle) * particle.distance * size.width * time + size.height * .11 * time * time;
    return Offset(particle.x * size.width + dx, particle.y * size.height + dy);
  }

  Offset _heartPoint(_FireworkParticle particle, double time, Size size) {
    final angle = particle.angle;
    final scale = .0085 * size.width * time;
    final x = (16 * math.pow(math.sin(angle), 3) * scale).toDouble();
    final y = (-(13 * math.cos(angle) - 5 * math.cos(2 * angle) - 2 * math.cos(3 * angle) - math.cos(4 * angle)) * scale).toDouble();
    final centerX = particle.x < .5 ? size.width * .32 : size.width * .68;
    return Offset(centerX + x, size.height * .18 + y + size.height * .08 * time * time);
  }

  Offset _waterfallPoint(_FireworkParticle particle, double time, Size size) {
    final sourceX = particle.x * size.width;
    final dx = math.cos(particle.angle) * particle.distance * size.width * .4 * time;
    final dy = size.height * (.05 + .62 * time * time);
    return Offset(sourceX + dx, size.height * .15 + dy);
  }

  Offset _ringPoint(_FireworkParticle particle, double time, Size size) {
    final radius = (.045 + particle.distance * .9) * size.width * time;
    return Offset(size.width * .5 + math.cos(particle.angle) * radius,
      size.height * .18 + math.sin(particle.angle) * radius);
  }

  Offset _finalePoint(_FireworkParticle particle, double time, Size size) {
    final point = _burstPoint(particle, time, size);
    final shimmer = math.sin((particle.angle + time * 18) * 2) * 3;
    return Offset(point.dx + shimmer, point.dy + size.height * .17 * time * time);
  }

  void _paintComet(Canvas canvas, Size size) {
    final flight = (progress.value / .4).clamp(0.0, 1.0).toDouble();
    final start = Offset(size.width * .5, size.height * .88);
    final end = Offset(size.width * .5, size.height * .18);
    final head = Offset.lerp(start, end, flight)!;
    final paint = Paint()..strokeWidth = 3..strokeCap = StrokeCap.round
      ..shader = LinearGradient(colors: [const Color(0x00FFD166), const Color(0xFFFFD166)]).createShader(Rect.fromPoints(start, head));
    canvas.drawLine(start, head, paint);
    canvas.drawCircle(head, 5, Paint()..color = const Color(0xFFFFF3BF));
  }

  @override
  bool shouldRepaint(_FireworkPainter oldDelegate) => oldDelegate.style != style || oldDelegate.particles != particles;
}
