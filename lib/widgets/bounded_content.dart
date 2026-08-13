import 'package:flutter/material.dart';

/// Caps content at a sane reading width and centers it on wide
/// (desktop/web) screens, instead of letting it stretch full-bleed
/// across the whole browser window. Below [breakpoint] (phone/tablet
/// width) this is a no-op passthrough.
///
/// Originally written inline, separately, in reports_screen.dart and
/// transactions_panel.dart — pulled out here once the same fix was
/// needed a third and fourth time (Settings, Inventory, Categories,
/// Users), so it's one shared definition instead of five copies that
/// could drift out of sync with each other.
class BoundedContent extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final double breakpoint;

  const BoundedContent({
    super.key,
    required this.child,
    this.maxWidth = 900,
    this.breakpoint = 700,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= breakpoint) return child;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: child,
          ),
        );
      },
    );
  }
}
