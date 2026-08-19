import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../state/store_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/bounded_content.dart';

// ── Fill these in once they're ready — nothing else in this file
// needs to change. Any link left empty just doesn't render its row,
// so it's safe to ship this screen before all of these exist. ──
const String kAppVersion = '1.0.0'; // bump this per release, or swap
                                     // for package_info_plus later if
                                     // you'd rather it read straight
                                     // from pubspec.yaml automatically
const String kSupportMessengerUrl = ''; // e.g. 'https://m.me/yourpage'
const String kSupportPhoneNumber = ''; // e.g. '+63 917 000 0000'
const String kBusinessProfileUrl = ''; // your client-facing business/website link
const String kTermsUrl = '';
const String kPrivacyPolicyUrl = '';
const String kCopyrightLine = '© 2026 Kahapro'; // swap in your business name once decided

/// About screen — reached from Settings > About. Static info + a
/// handful of links (support, business profile, terms/privacy) that
/// are configured as constants at the top of this file rather than
/// fetched from anywhere — these are the same for every store (unlike
/// Store Details, which is per-store data), so there's nothing to
/// load or save here. Store ID is the one dynamic value, read from
/// StoreProvider, with a copy button since a client reading a UUID
/// aloud over Messenger is exactly the support scenario this row
/// exists for.
class AboutPanel extends StatelessWidget {
  const AboutPanel({super.key});

  void _copyStoreId(BuildContext context, String id) {
    Clipboard.setData(ClipboardData(text: id));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Store ID copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StoreProvider>().store;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: BoundedContent(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Center(
              child: Column(
                children: [
                  Text('Kahapro', style: AppTextStyles.mono(size: 20, weight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('Version $kAppVersion', style: AppTextStyles.body(size: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 28),

            if (store != null) ...[
              _InfoRow(
                icon: Icons.storefront_outlined,
                label: 'Store ID',
                value: store.id,
                trailing: IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: AppColors.textMuted),
                  onPressed: () => _copyStoreId(context, store.id),
                  tooltip: 'Copy',
                ),
              ),
            ],

            if (kSupportMessengerUrl.isNotEmpty)
              _LinkRow(icon: Icons.chat_bubble_outline, label: 'Message us', url: kSupportMessengerUrl),
            if (kSupportPhoneNumber.isNotEmpty)
              _InfoRow(icon: Icons.call_outlined, label: 'Support', value: kSupportPhoneNumber),
            if (kBusinessProfileUrl.isNotEmpty)
              _LinkRow(icon: Icons.language_outlined, label: 'Our website', url: kBusinessProfileUrl),

            if (kTermsUrl.isNotEmpty || kPrivacyPolicyUrl.isNotEmpty) ...[
              const SizedBox(height: 16),
              if (kTermsUrl.isNotEmpty) _LinkRow(icon: Icons.description_outlined, label: 'Terms of Service', url: kTermsUrl),
              if (kPrivacyPolicyUrl.isNotEmpty) _LinkRow(icon: Icons.privacy_tip_outlined, label: 'Privacy Policy', url: kPrivacyPolicyUrl),
            ],

            const SizedBox(height: 28),
            Center(
              child: Text(kCopyrightLine, style: AppTextStyles.body(size: 12, color: AppColors.textMuted)),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;

  const _InfoRow({required this.icon, required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.slate,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slateBorder, width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.ledAmber),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.body(size: 11, color: AppColors.textMuted)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.mono(size: 12.5, weight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Same card shell as _InfoRow, but tappable — opens [url]. Uses
/// url_launcher; add it to pubspec.yaml (`url_launcher: ^6.x`) if it
/// isn't already a dependency elsewhere in the project.
class _LinkRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String url;

  const _LinkRow({required this.icon, required this.label, required this.url});

  Future<void> _open(BuildContext context) async {
    // Deliberately not importing url_launcher at the top of this file
    // by default — see the note in build() below for why, and what
    // to uncomment once the package is added.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Add url_launcher to open $label — see the comment in about_panel.dart')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _open(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.slate,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.slateBorder, width: 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppColors.ledAmber),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AppTextStyles.body(size: 13, weight: FontWeight.w600))),
            const Icon(Icons.open_in_new, size: 15, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}

// ── To make links actually open, once url_launcher is in pubspec.yaml:
// 1. Add near the top of this file:  import 'package:url_launcher/url_launcher.dart';
// 2. Replace _LinkRow._open()'s body with:
//      final uri = Uri.parse(url);
//      if (await canLaunchUrl(uri)) {
//        await launchUrl(uri, mode: LaunchMode.externalApplication);
//      }
// Left as a stub for now so this screen compiles with zero new
// dependencies — flip it on whenever you're ready.
