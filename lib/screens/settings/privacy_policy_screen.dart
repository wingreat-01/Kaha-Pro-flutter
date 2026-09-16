import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';

/// Privacy Policy, rendered natively (not a WebView) so it matches the
/// rest of the app's look instead of dropping the user into a
/// browser-styled page. Content mirrors privacy.html verbatim —
/// update both places together if the policy changes. Last updated
/// September 11, 2026.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  Future<void> _emailSupport() async {
    final uri = Uri(scheme: 'mailto', path: 'merq@prohubapps.com');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.charcoal,
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Last updated September 11, 2026',
              style: AppTextStyles.body(size: 12, color: AppColors.textMuted),
            ),
            const SizedBox(height: 16),
            _Paragraph(
              'Merq POS ("Merq", "the app", "we", "us") is developed and operated by ProHubApps. '
              'This policy explains what information the app collects, how it\'s used, and who it\'s '
              'shared with. It applies to the Merq POS mobile and web app.',
            ),

            _SectionHeading('Who this policy covers'),
            _Paragraph(
              'Merq POS is a point-of-sale app for small business owners. It has two kinds of users: '
              'store owners, who create an account and manage a store, and staff, who are added by an '
              'owner and sign in with a PIN inside that owner\'s store. This policy covers both.',
            ),

            _SectionHeading('Information we collect'),
            _Paragraph(
              'Account information (store owners). When you create a store, we collect the email '
              'address and password you sign up with, and the store name you choose. Your password '
              'is handled entirely by our backend provider, Supabase, using industry-standard hashing '
              '— we never see or store your plain-text password.',
            ),
            _Paragraph(
              'Staff PINs. When an owner adds a staff member, that staff member\'s PIN is stored as a '
              'one-way cryptographic hash, not in plain text. PINs are used only to let staff sign in '
              'to their owner\'s store and are never shared outside the app.',
            ),
            _Paragraph(
              'Business data you enter. Products, inventory levels, categories, transactions, and '
              'sales records you create while using the app are stored so the app can function — this '
              'is the core data the POS system runs on.',
            ),
            _Paragraph(
              'Product photos. If you attach a photo to a product, the app requests access to your '
              'device\'s camera or photo library to let you pick or take that image. Photos are only '
              'used for the product listing you attach them to.',
            ),
            _Paragraph(
              'AI Assistant messages. If you use the in-app AI Assistant, the text you send and the '
              'business data needed to answer your question (e.g. sales figures, stock levels) are '
              'sent to our backend, which forwards them to a third-party AI provider to generate a '
              'reply. See "Third-party services" below.',
            ),
            _Paragraph(
              'Information stored only on your device. The app keeps a local cache of your AI '
              'Assistant conversation history and some app preferences on your device using standard '
              'local storage. This data is not something we collect on our servers unless you send it '
              'as part of an AI Assistant message.',
            ),
            _Paragraph(
              'Connection status. The app checks whether your device is online or offline so it can '
              'queue actions while offline and sync later. This check happens on-device and is not '
              'transmitted anywhere.',
            ),

            _SectionHeading('How we use this information'),
            _BulletList(const [
              'To create and secure your account and let staff sign in under it',
              'To operate the core POS features: recording sales, tracking inventory, generating reports',
              'To respond to AI Assistant requests you initiate',
              'To provide customer support when you contact us',
              'To keep the service secure and diagnose technical problems',
            ]),
            _Paragraph('We do not sell your data, and we do not use your business data or account information for advertising.'),

            _SectionHeading('Third-party services'),
            _Paragraph('Merq POS relies on the following third parties to operate:'),
            _BulletList(const [
              'Supabase — our backend provider. Supabase hosts our database, handles account authentication, and stores uploaded product photos. Supabase\'s own privacy practices apply to data while it\'s on their infrastructure.',
              'AI providers — when you use the AI Assistant, your message and relevant business data are sent to one of the following providers to generate a response: Groq, Mistral, Google Gemini, OpenRouter, DeepSeek, or OpenAI. Only one provider is used per request. These providers process the request text but are not given ongoing access to your account.',
            ]),
            _Paragraph(
              'We don\'t control these providers\' own data practices; if you\'d like details on how a '
              'specific provider handles data, we recommend checking that provider\'s own privacy policy.',
            ),

            _SectionHeading('Data retention and deletion'),
            _Paragraph(
              'We keep your account and business data for as long as your account is active. If you\'d '
              'like your account and associated data deleted, contact us at the email below and we\'ll '
              'process the request.',
            ),

            _SectionHeading('Children\'s privacy'),
            _Paragraph('Merq POS is a business tool and is not directed at children. We don\'t knowingly collect information from children under 13.'),

            _SectionHeading('Your choices'),
            _BulletList(const [
              'You can review and edit most of your business data (products, store details) directly in the app.',
              'You can request a copy of your data, a correction, or full deletion by contacting us.',
              'You can decline camera/photo permissions — product photos are optional and the app works without them.',
            ]),

            _SectionHeading('Changes to this policy'),
            _Paragraph(
              'If this policy changes, we\'ll update the "Last updated" date at the top of this page. '
              'Continued use of the app after a change means you accept the updated policy.',
            ),

            _SectionHeading('Contact us'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: AppColors.slateField,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.slateBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ProHubApps', style: AppTextStyles.body(size: 13, weight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: _emailSupport,
                    child: Text(
                      'merq@prohubapps.com',
                      style: AppTextStyles.body(size: 13, color: AppColors.ledAmber, weight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '© 2026 ProHubApps. This policy applies to the Merq POS app and merq.prohubapps.com.',
              style: AppTextStyles.body(size: 11.5, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  final String text;
  const _SectionHeading(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.slateBorder, width: 1)),
        ),
        padding: const EdgeInsets.only(top: 16),
        child: Text(text, style: AppTextStyles.body(size: 15, weight: FontWeight.w700)),
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  final String text;
  const _Paragraph(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: AppTextStyles.body(size: 13.5, color: AppColors.textSecondary)),
    );
  }
}

class _BulletList extends StatelessWidget {
  final List<String> items;
  const _BulletList(this.items);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: AppTextStyles.body(size: 13.5, color: AppColors.textSecondary)),
                  Expanded(
                    child: Text(item, style: AppTextStyles.body(size: 13.5, color: AppColors.textSecondary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
