import 'package:audioplayers/audioplayers.dart';

/// The three sounds a barcode scan can make.
///  - success:   one short high beep — item scanned / added.
///  - duplicate: two quick lower beeps — already scanned, already in the
///               cart, or already sold.
///  - error:     one long low tone — barcode not recognised / not added.
enum ScanSound { success, duplicate, error }

class ScanSounds {
  ScanSounds._();

  static const Map<ScanSound, String> _assets = {
    ScanSound.success: 'sounds/scan_success.wav',
    ScanSound.duplicate: 'sounds/scan_duplicate.wav',
    ScanSound.error: 'sounds/scan_error.wav',
  };

  static final Map<ScanSound, AudioPlayer> _players = {};

  /// Plays [sound]. Never throws — a missing audio device or a platform
  /// hiccup must not interrupt scanning.
  static Future<void> play(ScanSound sound) async {
    try {
      final player = _players.putIfAbsent(sound, () {
        final p = AudioPlayer();
        p.setPlayerMode(PlayerMode.lowLatency);
        return p;
      });
      await player.stop();
      await player.play(AssetSource(_assets[sound]!));
    } catch (_) {}
  }
}
