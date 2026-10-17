import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';

/// Shows a bottom sheet letting the user choose where a photo comes from
/// (camera or gallery), then opens the picker and returns the selected
/// image. Returns null if the user dismisses the sheet or cancels the picker.
Future<XFile?> pickImageWithSourceChoice(
  BuildContext context, {
  double maxWidth = 800,
  int imageQuality = 85,
}) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: AppColors.slate,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.textMuted.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ListTile(
              leading: Icon(Icons.photo_camera, color: AppColors.ledAmber),
              title: Text('Take a photo',
                  style: AppTextStyles.body(size: 15, color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_outlined, color: AppColors.ledAmber),
              title: Text('Choose from gallery',
                  style: AppTextStyles.body(size: 15, color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    ),
  );
  if (source == null) return null;

  return ImagePicker().pickImage(
    source: source,
    maxWidth: maxWidth,
    imageQuality: imageQuality,
  );
}
