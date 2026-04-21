// lib/data/golden_profile_repository.dart
//
// THE VAULT: Persists the user's behavioral baseline ("Golden Profile") to
// Hive. On first run the profile is empty — the engine operates in
// "learning mode" and builds the baseline over the first N interactions.
// After calibration, every new SoulprintVector is compared against this
// stored baseline to compute deviation.

import 'package:hive_flutter/hive_flutter.dart';

class GoldenProfileRepository {
  static const _boxName = 'soulprint_profile';
  static const _key = 'golden_vector';
  static const _calibratedKey = 'is_calibrated';

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns the stored baseline vector, or null if not yet calibrated.
  List<double>? loadBaseline() {
    final box = Hive.box<List>(_boxName);
    final raw = box.get(_key);
    return raw?.cast<double>();
  }

  bool get isCalibrated {
    final box = Hive.box<List>(_boxName);
    final flag = box.get(_calibratedKey);
    return flag != null && flag.isNotEmpty && flag[0] == 1.0;
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Saves a new baseline vector after calibration window completes.
  Future<void> saveBaseline(List<double> vector) async {
    final box = Hive.box<List>(_boxName);
    await box.put(_key, vector);
    await box.put(_calibratedKey, [1.0]);
  }

  /// Resets the profile — used when a new user enrolls on the same device.
  Future<void> clearProfile() async {
    final box = Hive.box<List>(_boxName);
    await box.delete(_key);
    await box.delete(_calibratedKey);
  }

  // ── Euclidean Deviation ───────────────────────────────────────────────────

  /// Computes normalized Euclidean distance between current vector and baseline.
  /// Returns 0.0 (identical) → 1.0 (highly deviant).
  /// Threshold > 0.25 triggers anomaly in SoulprintEngine.
  double computeDeviation(List<double> current, List<double> baseline) {
    if (current.length != baseline.length) return 1.0;
    double sumSq = 0;
    for (int i = 0; i < current.length; i++) {
      sumSq += (current[i] - baseline[i]) * (current[i] - baseline[i]);
    }
    return (sumSq / current.length).clamp(0.0, 1.0);
  }
}
