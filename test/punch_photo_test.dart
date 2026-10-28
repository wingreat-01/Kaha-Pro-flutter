import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:kahapro_flutter/services/punch_photo.dart';

/// A camera-sized JPEG with some detail (a gradient), so the size check
/// isn't flattered by a blank image compressing to nothing.
Uint8List _cameraShot(int w, int h) {
  final image = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      image.setPixelRgb(x, y, (x * 255) ~/ w, (y * 255) ~/ h, ((x + y) * 7) % 256);
    }
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 92));
}

void main() {
  test('landscape shot is scaled to 320 px wide and gets much smaller', () async {
    final original = _cameraShot(1280, 720);
    final small = await shrinkPunchPhoto(original);
    final decoded = img.decodeImage(small)!;
    expect(decoded.width, kPunchPhotoMaxSide);
    expect(decoded.height, 180);
    expect(small.length, lessThan(original.length ~/ 4));
    expect(small.length, lessThan(30 * 1024));
  });

  test('portrait shot is scaled by its height', () async {
    final decoded = img.decodeImage(await shrinkPunchPhoto(_cameraShot(480, 640)))!;
    expect(decoded.height, kPunchPhotoMaxSide);
    expect(decoded.width, 240);
  });

  test('undecodable bytes pass through untouched instead of failing the punch', () async {
    final junk = Uint8List.fromList([1, 2, 3, 4]);
    expect(await shrinkPunchPhoto(junk), junk);
  });
}
