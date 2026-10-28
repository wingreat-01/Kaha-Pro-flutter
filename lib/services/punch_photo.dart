import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Longest side of a stored time clock selfie. Enough to recognise who is
/// in the photo; at JPEG quality 70 that's roughly 15–25 KB, versus
/// 60–120 KB for the camera's own medium-resolution shot.
const int kPunchPhotoMaxSide = 320;

/// Downscales a captured selfie before upload. Runs off the UI thread on
/// mobile (compute); on web compute runs inline, which is fine at this size.
/// Falls back to the original bytes if the image can't be decoded, so a
/// punch is never blocked by this step.
Future<Uint8List> shrinkPunchPhoto(Uint8List bytes) => compute(_shrink, bytes);

Uint8List _shrink(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  // Apply the EXIF rotation now — the small copy's metadata may not
  // survive re-encoding, and a sideways face is useless for checking.
  final upright = img.bakeOrientation(decoded);
  final longest = max(upright.width, upright.height);
  final resized = longest <= kPunchPhotoMaxSide
      ? upright
      : img.copyResize(
          upright,
          width: upright.width >= upright.height ? kPunchPhotoMaxSide : null,
          height: upright.height > upright.width ? kPunchPhotoMaxSide : null,
          interpolation: img.Interpolation.average,
        );
  return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
}
