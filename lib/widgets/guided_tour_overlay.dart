import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../state/tour_provider.dart';
import '../theme/app_theme.dart';

class _TourStepSpec {
  final GlobalKey target;
  final String title;
  final String message;
  // Informational steps get a button instead of waiting for a tap on
  // the target, and leave the rest of the screen tappable.
  final String? actionLabel;

  const _TourStepSpec({
    required this.target,
    required this.title,
    required this.message,
    this.actionLabel,
  });

  bool get waitsForTap => actionLabel == null;
}

_TourStepSpec? _specFor(TourStep step) {
  switch (step) {
    case TourStep.none:
      return null;
    case TourStep.openSettings:
      return _TourStepSpec(
        target: TourKeys.settingsIcon,
        title: 'Open Settings',
        message: 'Let\'s set up your store. Start by tapping the highlighted gear icon.',
      );
    case TourStep.openCategories:
      return _TourStepSpec(
        target: TourKeys.categoriesRow,
        title: 'Open Categories',
        message: 'Products are grouped into categories. Tap Categories to create your first one.',
      );
    case TourStep.addCategory:
      return _TourStepSpec(
        target: TourKeys.addCategory,
        title: 'Add a category',
        message: 'Tap Add category, type a name such as Drinks or Snacks, then tap Add.',
      );
    case TourStep.leaveCategories:
      return _TourStepSpec(
        target: TourKeys.categoriesBack,
        title: 'Category saved',
        message: 'Nice! Tap the back arrow to continue.',
      );
    case TourStep.openRegister:
      return _TourStepSpec(
        target: TourKeys.registerIcon,
        title: 'Go to the Register',
        message: 'Tap the register icon to open your product grid.',
      );
    case TourStep.addProduct:
      return _TourStepSpec(
        target: TourKeys.addProduct,
        title: 'Add your first product',
        message: 'Tap + Add product, enter a name and price, choose the category you made, then save.',
      );
    case TourStep.checkout:
      return _TourStepSpec(
        target: TourKeys.checkout,
        title: 'Ring up a sale',
        message: 'Tap a product to add it to the cart, then tap Checkout here. You can cancel on the payment screen without completing a sale.',
        actionLabel: 'Finish',
      );
  }
}

/// Spotlight layer for the guided tour. Place it as the last child of a
/// full-screen Stack; it shows only while the current [TourStep] is one
/// of [steps] (the steps whose targets live in this route).
///
/// While a waiting step is shown, taps outside the highlighted button are
/// swallowed and taps inside it fall through to the real button, so the
/// only way forward is the action being taught (or Skip tour).
class GuidedTourLayer extends StatefulWidget {
  final Set<TourStep> steps;
  const GuidedTourLayer({super.key, required this.steps});

  @override
  State<GuidedTourLayer> createState() => _GuidedTourLayerState();
}

class _GuidedTourLayerState extends State<GuidedTourLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Rect? _hole;

  @override
  void initState() {
    super.initState();
    // Re-measured every frame while visible so the spotlight follows the
    // target through scrolling, rotation and keyboard/insets changes.
    _ticker = createTicker((_) => _measure());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _measure() {
    final spec = _specFor(context.read<TourProvider>().step);
    Rect? next;
    final targetBox = spec?.target.currentContext?.findRenderObject();
    final layerBox = context.findRenderObject();
    if (targetBox is RenderBox && targetBox.attached && targetBox.hasSize &&
        layerBox is RenderBox && layerBox.attached && layerBox.hasSize) {
      final origin = layerBox.globalToLocal(targetBox.localToGlobal(Offset.zero));
      next = (origin & targetBox.size).inflate(6);
    }
    if (next != _hole) setState(() => _hole = next);
  }

  @override
  Widget build(BuildContext context) {
    final tour = context.watch<TourProvider>();
    final visible = widget.steps.contains(tour.step);
    if (visible && !_ticker.isActive) {
      _ticker.start();
    } else if (!visible && _ticker.isActive) {
      _ticker.stop();
      _hole = null;
    }
    final spec = visible ? _specFor(tour.step) : null;
    if (spec == null) return const SizedBox.shrink();

    final hole = _hole;
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final children = <Widget>[];
          if (hole != null) {
            children.add(IgnorePointer(
              child: CustomPaint(size: size, painter: _SpotlightPainter(hole)),
            ));
            if (spec.waitsForTap) children.addAll(_blockersAround(hole, size));
          }
          children.add(_coachCard(context, tour, spec, hole, size));
          return Stack(children: children);
        },
      ),
    );
  }

  /// Four tap-absorbing panels framing [hole]; the hole itself has none,
  /// so a tap there reaches the real button underneath.
  List<Widget> _blockersAround(Rect hole, Size size) {
    Widget block(Rect r) => Positioned.fromRect(
          rect: r,
          child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () {}),
        );
    final top = hole.top.clamp(0.0, size.height);
    final bottom = hole.bottom.clamp(0.0, size.height);
    final left = hole.left.clamp(0.0, size.width);
    final right = hole.right.clamp(0.0, size.width);
    return [
      block(Rect.fromLTRB(0, 0, size.width, top)),
      block(Rect.fromLTRB(0, bottom, size.width, size.height)),
      block(Rect.fromLTRB(0, top, left, bottom)),
      block(Rect.fromLTRB(right, top, size.width, bottom)),
    ];
  }

  Widget _coachCard(BuildContext context, TourProvider tour, _TourStepSpec spec, Rect? hole, Size size) {
    const cardHeightGuess = 190.0;
    final width = size.width < 480 ? size.width - 32 : 420.0;
    double top;
    if (hole == null) {
      // Target not on screen (e.g. scrolled away) — still show the
      // instructions, pinned to the bottom, with nothing blocked.
      top = size.height - cardHeightGuess - 24;
    } else if (hole.bottom + cardHeightGuess + 16 < size.height) {
      top = hole.bottom + 12;
    } else {
      top = hole.top - cardHeightGuess - 12;
    }
    top = top.clamp(24.0, (size.height - cardHeightGuess).clamp(24.0, double.infinity));
    final left = hole == null
        ? (size.width - width) / 2
        : (hole.center.dx - width / 2).clamp(16.0, (size.width - width - 16).clamp(16.0, double.infinity));

    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Material(
        color: AppColors.slate,
        elevation: 18,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'STEP ${tour.stepNumber} OF ${tour.totalSteps}',
                style: AppTextStyles.mono(size: 10, color: AppColors.ledAmber, weight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(spec.title, style: AppTextStyles.body(size: 16, weight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                hole == null && spec.waitsForTap
                    ? '${spec.message}\n\nScroll to find the highlighted button.'
                    : spec.message,
                style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  TextButton(onPressed: tour.finish, child: const Text('Skip tour')),
                  const Spacer(),
                  if (spec.actionLabel != null)
                    FilledButton(
                      onPressed: () => tour.advanceFrom(tour.step),
                      child: Text(spec.actionLabel!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect hole;
  _SpotlightPainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(hole, const Radius.circular(14));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(rrect)),
      Paint()..color = Colors.black.withValues(alpha: 0.7),
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = AppColors.ledAmber
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) => oldDelegate.hole != hole;
}
