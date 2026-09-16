import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import 'privacy_policy_screen.dart';

/// Settings → About. Version is read from the platform package info
/// (which reflects pubspec.yaml's version/build number) rather than
/// hardcoded, so this screen never goes stale on its own.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _versionLabel = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _versionLabel = 'Version ${info.version} (${info.buildNumber})');
  }

  Future<void> _emailSupport() async {
    final uri = Uri(scheme: 'mailto', path: 'merq@prohubapps.com');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(title: const Text('About')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset('assets/icon/icon.png', width: 88, height: 88),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'MERQ POS',
                style: AppTextStyles.mono(size: 20, weight: FontWeight.w700, letterSpacing: 1.5),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Sell faster. Run smarter.',
                style: AppTextStyles.body(size: 13, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 6),
            if (_versionLabel.isNotEmpty)
              Center(
                child: Text(
                  _versionLabel,
                  style: AppTextStyles.mono(size: 11.5, color: AppColors.textMuted),
                ),
              ),
            const SizedBox(height: 28),
            _AboutTile(
              icon: Icons.mail_outline,
              label: 'Contact support',
              value: 'merq@prohubapps.com',
              onTap: _emailSupport,
            ),
            _AboutTile(
              icon: Icons.privacy_tip_outlined,
              label: 'Privacy Policy',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
              ),
            ),
            _AboutTile(
              icon: Icons.description_outlined,
              label: 'Open-source licenses',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'MERQ POS',
                applicationVersion: _versionLabel,
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: Text(
                'Made for Philippine small businesses 🇵🇭',
                style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                '© 2026 ProHubApps',
                style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? value;
  final VoidCallback onTap;

  const _AboutTile({required this.icon, required this.label, required this.onTap, this.value});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.slateField,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.slateBorder),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.ledAmber),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.body(size: 14, weight: FontWeight.w600)),
                  if (value != null) ...[
                    const SizedBox(height: 2),
                    Text(value!, style: AppTextStyles.body(size: 12, color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
