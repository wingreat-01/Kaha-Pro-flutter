import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/store_provider.dart';
import '../theme/app_colors.dart'; // adjust path if your color constants live elsewhere

/// Persistent bar shown at the top of HomeShell (or wherever your main
/// scaffold lives) when the store's plan is 'expired'. Not dismissible --
/// a trial-expired state should stay visible, not be closeable once and
/// forgotten. Renders nothing (SizedBox.shrink) when not expired, so it's
/// safe to drop into the widget tree unconditionally.
class TrialExpiredBanner extends StatelessWidget {
  const TrialExpiredBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final isExpired = context.watch<StoreProvider>().isExpired;

    if (!isExpired) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.ledgerRed, // swap for your actual red constant if named differently
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Your trial has expired. Some actions are disabled until you upgrade.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              // TODO: point this at the actual upgrade/plans screen once it exists
            },
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: const Text(
              'Upgrade',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
