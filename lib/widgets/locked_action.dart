import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/store_provider.dart';

/// Wraps any action widget (a button, a card, a whole panel) and locks
/// it when the store's trial has expired: dims it and swallows taps,
/// showing a small explanation on tap instead of silently doing nothing.
///
/// Usage -- wrap just the widget(s) you want gated, not the whole screen:
///   LockedAction(
///     child: ElevatedButton(onPressed: _checkout, child: Text('Checkout')),
///   )
///
/// Which actions to lock is a product decision, not a technical one --
/// drop this around checkout, "+ Add product", etc. as you decide.
class LockedAction extends StatelessWidget {
  final Widget child;
  final String? lockedMessage;

  const LockedAction({
    super.key,
    required this.child,
    this.lockedMessage,
  });

  @override
  Widget build(BuildContext context) {
    final isExpired = context.watch<StoreProvider>().isExpired;

    if (!isExpired) return child;

    return Stack(
      children: [
        Opacity(opacity: 0.4, child: IgnorePointer(child: child)),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    lockedMessage ??
                        'This is disabled until your trial is renewed.',
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
