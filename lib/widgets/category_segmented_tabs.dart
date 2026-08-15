import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Full-width segmented tab bar for phone widths. The first 4 tabs are
/// each sized to roughly a quarter of the available width so they read
/// as "maximized" / evenly filling the bar. A 5th+ tab keeps that same
/// width instead of shrinking to fit, so it overflows the bar and is
/// reached by horizontal scroll/swipe rather than squeezing everyone
/// down to stay visible.
///
/// Works with touch swipe (phone) AND mouse click-drag + scroll wheel
/// (desktop/web) — Flutter's default ScrollBehavior only allows touch
/// drag, so desktop needs an explicit opt-in (see _MouseDragScrollBehavior
/// below) plus a wheel-to-horizontal-scroll handler.
class CategorySegmentedTabs extends StatefulWidget {
  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelected;

  const CategorySegmentedTabs({
    super.key,
    required this.categories,
    required this.selected,
    required this.onSelected,
  });

  @override
  State<CategorySegmentedTabs> createState() => _CategorySegmentedTabsState();
}

class _CategorySegmentedTabsState extends State<CategorySegmentedTabs> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleScroll(PointerSignalEvent event) {
    if (event is PointerScrollEvent && _controller.hasClients) {
      // Let a vertical mouse-wheel/trackpad scroll move this horizontal
      // bar — otherwise desktop users have no way to reach hidden tabs
      // besides dragging.
      final target = (_controller.offset + event.scrollDelta.dy)
          .clamp(_controller.position.minScrollExtent, _controller.position.maxScrollExtent);
      _controller.jumpTo(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Always divide by 4, even if there are fewer than 4 categories —
        // that keeps tabs at a consistent "maximized" width instead of
        // stretching wider when the list happens to be short.
        final tabWidth = constraints.maxWidth / 4;

        return Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.slateBorder, width: 1)),
          ),
          child: Listener(
            onPointerSignal: _handleScroll,
            child: ScrollConfiguration(
              behavior: _MouseDragScrollBehavior(),
              child: Scrollbar(
                controller: _controller,
                thumbVisibility: false,
                child: SingleChildScrollView(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final category in widget.categories)
                        _SegmentedTab(
                          label: category,
                          isSelected: category == widget.selected,
                          onTap: () => widget.onSelected(category),
                          width: tabWidth,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Adds mouse to the set of devices allowed to drag-scroll. Flutter's
/// default behavior only recognizes touch/stylus, so without this a
/// desktop/web user has no way to click-and-drag the bar.
class _MouseDragScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

class _SegmentedTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final double width;

  const _SegmentedTab({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: width,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppColors.ledAmber : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.body(
            size: 13.5,
            weight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.ledAmber : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
