import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Steps of the first-run guided tour, in order. Each step spotlights one
/// real button (see [TourKeys]) and waits for the user to tap it — the
/// screen that owns that button calls [TourProvider.advanceFrom] from
/// the button's own handler, so the tour only moves forward when the
/// real action actually happened (e.g. a category was saved, not just
/// the dialog opened).
enum TourStep {
  none,
  openSettings,
  openCategories,
  addCategory,
  leaveCategories,
  openRegister,
  addProduct,
  checkout,
}

/// Targets the tour spotlights. Static because the steps span separate
/// widgets and routes (HomeShell header, SettingsPanel, CategoriesPanel,
/// RegisterScreen); each key is mounted in exactly one place at a time.
class TourKeys {
  TourKeys._();
  static final settingsIcon = GlobalKey(debugLabel: 'tour-settings-icon');
  static final registerIcon = GlobalKey(debugLabel: 'tour-register-icon');
  static final categoriesRow = GlobalKey(debugLabel: 'tour-categories-row');
  static final addCategory = GlobalKey(debugLabel: 'tour-add-category');
  static final categoriesBack = GlobalKey(debugLabel: 'tour-categories-back');
  static final addProduct = GlobalKey(debugLabel: 'tour-add-product');
  static final checkout = GlobalKey(debugLabel: 'tour-checkout');
}

class TourProvider extends ChangeNotifier {
  // Per-device, like the other SharedPreferences-backed settings — a
  // second register for the same store gets the tour once too, which is
  // harmless and easy to skip.
  static const String _doneKey = 'merq_guided_tour_done_v1';

  TourStep _step = TourStep.none;
  TourStep _startStep = TourStep.openSettings;

  TourStep get step => _step;
  bool get isActive => _step != TourStep.none;

  /// 1-based position of the current step, counted from wherever this
  /// run of the tour started (a store that already has categories
  /// starts at [TourStep.addProduct]).
  int get stepNumber => _step.index - _startStep.index + 1;
  int get totalSteps => TourStep.values.last.index - _startStep.index + 1;

  /// Starts the full tour once for a brand-new store (no categories and
  /// no products yet). Existing stores never get it automatically.
  Future<void> maybeAutoStart({required bool isNewStore}) async {
    if (!isNewStore || isActive) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_doneKey) ?? false) return;
    _begin(TourStep.openSettings);
  }

  /// Manual start from Register's "Guided tour" button.
  void start({required bool hasCategories}) {
    _begin(hasCategories ? TourStep.addProduct : TourStep.openSettings);
  }

  void _begin(TourStep first) {
    _startStep = first;
    _step = first;
    notifyListeners();
  }

  /// Moves to the next step, but only if [from] is the current one — so
  /// a button calling this outside the tour (or out of order) is a no-op.
  void advanceFrom(TourStep from) {
    if (_step != from) return;
    if (from == TourStep.values.last) {
      finish();
      return;
    }
    _step = TourStep.values[from.index + 1];
    notifyListeners();
  }

  /// Steps back to [step] — used when the user leaves a screen before
  /// finishing its step (e.g. backs out of Categories without adding one).
  void rewindTo(TourStep step) {
    if (!isActive || step.index >= _step.index) return;
    _step = step;
    notifyListeners();
  }

  Future<void> finish() async {
    _step = TourStep.none;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_doneKey, true);
    } catch (e) {
      debugPrint('Could not save guided tour state: $e');
    }
  }
}
