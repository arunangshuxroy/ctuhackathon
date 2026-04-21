// lib/core/soulprint_engine.dart
//
// THE BRAIN: Captures sub-perceptual behavioral signals and fuses them into
// a single "Soulprint Confidence" score (0.0 – 1.0).
//
// Signal pipeline:
//   Raw events → Feature extraction → Normalization → SoulprintVector
//   → Euclidean deviation from Golden Profile → Confidence score
//
// Calibration window: first 10 vectors are averaged into the Golden Profile.
// After calibration, deviation > 0.25 from baseline triggers anomaly.

import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../data/golden_profile_repository.dart';

// ─── Data Structures ────────────────────────────────────────────────────────

/// One normalized feature vector snapshot, produced every 500 ms.
/// All values are clamped to [0.0, 1.0] before scoring.
class SoulprintVector {
  final double dwellTimeMean;   // avg key-hold duration (ms), normalized
  final double flightTimeMean;  // avg inter-key gap (ms), normalized
  final double touchPressure;   // PointerEvent.pressure, already 0–1
  final double touchSize;       // PointerEvent.size, normalized
  final double swipeVelocity;   // px/ms, normalized
  final double jitterRms;       // RMS of accel magnitude variance → hand-shake
  final double gyroRms;         // RMS of gyro magnitude → rotation stress
  final double rhythmVariance;  // coefficient of variation of flight times

  const SoulprintVector({
    required this.dwellTimeMean,
    required this.flightTimeMean,
    required this.touchPressure,
    required this.touchSize,
    required this.swipeVelocity,
    required this.jitterRms,
    required this.gyroRms,
    required this.rhythmVariance,
  });

  /// Flat list fed into TFLite model input tensor [1 × 8].
  List<double> toList() => [
        dwellTimeMean,
        flightTimeMean,
        touchPressure,
        touchSize,
        swipeVelocity,
        jitterRms,
        gyroRms,
        rhythmVariance,
      ];

  @override
  String toString() =>
      'SoulprintVector(jitter:${jitterRms.toStringAsFixed(3)}'
      ' dwell:${dwellTimeMean.toStringAsFixed(3)}'
      ' rhythm:${rhythmVariance.toStringAsFixed(3)})';
}

// ─── Keystroke Dynamics Tracker ─────────────────────────────────────────────

class _KeystrokeTracker {
  final Map<String, int> _pressTime = {};
  final List<double> _dwellTimes = [];
  final List<double> _flightTimes = [];
  int? _lastReleaseTime;

  void onKeyDown(String key) {
    _pressTime[key] = DateTime.now().millisecondsSinceEpoch;
  }

  void onKeyUp(String key) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final press = _pressTime.remove(key);
    if (press != null) {
      // Dwell time: how long the key was physically held
      _dwellTimes.add((now - press).toDouble());
    }
    if (_lastReleaseTime != null) {
      // Flight time: gap between consecutive key releases (typing rhythm)
      _flightTimes.add((now - _lastReleaseTime!).toDouble());
    }
    _lastReleaseTime = now;
  }

  /// Returns (dwellMean, flightMean, rhythmVariance) and clears buffers.
  (double, double, double) flush() {
    final dwell = _mean(_dwellTimes);
    final flight = _mean(_flightTimes);
    final variance = _coefficientOfVariation(_flightTimes);
    _dwellTimes.clear();
    _flightTimes.clear();
    return (dwell, flight, variance);
  }

  double _mean(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  double _coefficientOfVariation(List<double> v) {
    if (v.length < 2) return 0;
    final m = _mean(v);
    if (m == 0) return 0;
    final variance =
        v.map((x) => pow(x - m, 2)).reduce((a, b) => a + b) / v.length;
    return sqrt(variance) / m; // σ/μ — higher = more erratic rhythm
  }
}

// ─── Touch Dynamics Tracker ─────────────────────────────────────────────────

class _TouchTracker {
  double _pressure = 0.5;
  double _size = 0.5;
  double _velocity = 0.0;

  void onPointer({
    required double pressure,
    required double size,
    required double velocityPxPerMs,
  }) {
    // Exponential moving average — smooths noise while tracking real changes
    _pressure = 0.7 * _pressure + 0.3 * pressure.clamp(0.0, 1.0);
    _size = 0.7 * _size + 0.3 * size.clamp(0.0, 1.0);
    _velocity = 0.7 * _velocity + 0.3 * velocityPxPerMs.clamp(0.0, 1.0);
  }

  (double, double, double) snapshot() => (_pressure, _size, _velocity);
}

// ─── Motion Dynamics ─────────────────────────────────────────────────────────

/// Computes RMS of accelerometer and gyroscope magnitudes over a window.
/// High RMS = stressed/shaky hand = potential coercion or mule scenario.
class _MotionProcessor {
  final List<double> _accelMags = [];
  final List<double> _gyroMags = [];

  void addAccel(double x, double y, double z) {
    // Subtract gravity (≈9.8 m/s²) to isolate hand-jitter component
    final jitter = sqrt(x * x + y * y + z * z) - 9.8;
    _accelMags.add(jitter.abs());
  }

  void addGyro(double x, double y, double z) {
    _gyroMags.add(sqrt(x * x + y * y + z * z));
  }

  /// RMS = √(mean of squares) — captures energy of micro-tremors
  (double, double) flushRms() {
    final accelRms = _rms(_accelMags);
    final gyroRms = _rms(_gyroMags);
    _accelMags.clear();
    _gyroMags.clear();
    return (accelRms, gyroRms);
  }

  double _rms(List<double> v) {
    if (v.isEmpty) return 0;
    return sqrt(v.map((x) => x * x).reduce((a, b) => a + b) / v.length);
  }
}

// ─── SoulprintEngine (ChangeNotifier = Provider-compatible) ─────────────────

class SoulprintEngine extends ChangeNotifier {
  // ── Public state ──────────────────────────────────────────────────────────
  double confidence = 1.0;         // 0.0–1.0 Soulprint score
  SoulprintVector? lastVector;
  @visibleForTesting
  set testLastVector(SoulprintVector v) => lastVector = v;
  bool isDemoMuleMode = false;      // Hackathon toggle: forces anomaly
  bool isCalibrating = true;        // True during the 10-vector learning window
  int calibrationProgress = 0;      // 0–10 vectors collected so far
  List<double> accelHistory = [];   // For BiometricVisualizer waveform
  List<double> gyroHistory = [];

  // ── Private internals ─────────────────────────────────────────────────────
  final _keystroke = _KeystrokeTracker();
  final _touch = _TouchTracker();
  final _motion = _MotionProcessor();
  final _repo = GoldenProfileRepository();

  // Calibration accumulator — collects vectors during learning window
  final List<List<double>> _calibrationVectors = [];
  static const _calibrationTarget = 10;

  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  Timer? _vectorTimer;

  // Normalization constants (derived from empirical UPI-user study baselines)
  static const _maxDwell = 200.0;   // ms — typical key hold
  static const _maxFlight = 500.0;  // ms — typical inter-key gap
  static const _maxJitter = 3.0;    // m/s² RMS — stressed hand
  static const _maxGyro = 2.0;      // rad/s RMS
  static const _maxVelocity = 5.0;  // px/ms

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  void start() {
    // Check if a Golden Profile already exists from a previous session
    if (_repo.isCalibrated) {
      isCalibrating = false;
      calibrationProgress = _calibrationTarget;
    }
    _startSensors();
    // Vectorize and score every 500 ms — balances responsiveness vs. noise
    _vectorTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _computeAndScore(),
    );
  }

  void stop() {
    _accelSub?.cancel();
    _gyroSub?.cancel();
    _vectorTimer?.cancel();
  }

  // ── Sensor Subscriptions ──────────────────────────────────────────────────

  void _startSensors() {
    _accelSub = accelerometerEventStream(
      samplingPeriod: const Duration(milliseconds: 50), // 20 Hz
    ).listen((e) {
      _motion.addAccel(e.x, e.y, e.z);
      // Keep last 60 samples for waveform display (3 seconds at 20 Hz)
      accelHistory.add(sqrt(e.x * e.x + e.y * e.y + e.z * e.z));
      if (accelHistory.length > 60) accelHistory.removeAt(0);
    });

    _gyroSub = gyroscopeEventStream(
      samplingPeriod: const Duration(milliseconds: 50),
    ).listen((e) {
      _motion.addGyro(e.x, e.y, e.z);
      gyroHistory.add(sqrt(e.x * e.x + e.y * e.y + e.z * e.z));
      if (gyroHistory.length > 60) gyroHistory.removeAt(0);
    });
  }

  // ── Public Event Hooks (called by UI widgets) ─────────────────────────────

  void onKeyDown(String key) => _keystroke.onKeyDown(key);
  void onKeyUp(String key) => _keystroke.onKeyUp(key);

  void onPointerEvent({
    required double pressure,
    required double size,
    required double velocityPxPerMs,
  }) =>
      _touch.onPointer(
        pressure: pressure,
        size: size,
        velocityPxPerMs: velocityPxPerMs,
      );

  void toggleDemoMuleMode() {
    isDemoMuleMode = !isDemoMuleMode;
    if (isDemoMuleMode) confidence = 0.42; // Simulate a caught mule
    notifyListeners();
  }

  // ── Core Vectorization & Scoring ─────────────────────────────────────────

  void _computeAndScore() {
    final (dwell, flight, rhythmVar) = _keystroke.flush();
    final (pressure, size, velocity) = _touch.snapshot();
    final (jitter, gyro) = _motion.flushRms();

    // Normalize all features to [0, 1]
    final vector = SoulprintVector(
      dwellTimeMean: (dwell / _maxDwell).clamp(0.0, 1.0),
      flightTimeMean: (flight / _maxFlight).clamp(0.0, 1.0),
      touchPressure: pressure,
      touchSize: size,
      swipeVelocity: (velocity / _maxVelocity).clamp(0.0, 1.0),
      jitterRms: (jitter / _maxJitter).clamp(0.0, 1.0),
      gyroRms: (gyro / _maxGyro).clamp(0.0, 1.0),
      rhythmVariance: rhythmVar.clamp(0.0, 1.0),
    );

    lastVector = vector;

    if (isDemoMuleMode) {
      notifyListeners();
      return;
    }

    if (isCalibrating) {
      // ── LEARNING MODE: accumulate vectors into Golden Profile ─────────────
      _calibrationVectors.add(vector.toList());
      calibrationProgress = _calibrationVectors.length;

      if (_calibrationVectors.length >= _calibrationTarget) {
        // Average all calibration vectors → Golden Profile baseline
        final baseline = List<double>.filled(8, 0.0);
        for (final v in _calibrationVectors) {
          for (int i = 0; i < 8; i++) {
            baseline[i] += v[i] / _calibrationTarget;
          }
        }
        _repo.saveBaseline(baseline);
        isCalibrating = false;
        confidence = 1.0; // Fresh start after calibration
      }
    } else {
      // ── VERIFICATION MODE: compare against Golden Profile ─────────────────
      final baseline = _repo.loadBaseline();

      double anomalyScore;
      if (baseline != null) {
        // Primary signal: Euclidean deviation from personal baseline
        final deviation = _repo.computeDeviation(vector.toList(), baseline);
        anomalyScore = deviation;
      } else {
        // Fallback heuristic if baseline unavailable
        // High jitter + erratic rhythm = low confidence
        anomalyScore = 0.35 * vector.jitterRms +
            0.30 * vector.rhythmVariance +
            0.20 * vector.gyroRms +
            0.15 * (1.0 - vector.touchPressure);
      }

      // Smooth confidence with EMA to avoid jarring UI jumps
      confidence =
          (confidence * 0.8 + (1.0 - anomalyScore) * 0.2).clamp(0.0, 1.0);
    }

    notifyListeners();
  }

  // ── XAI: Explainable Anomaly Reasons ─────────────────────────────────────

  /// Returns human-readable reasons when confidence < 0.75.
  /// Shown in the "Why?" section of the Block Screen.
  List<String> get anomalyReasons {
    final v = lastVector;
    if (v == null) return [];
    final reasons = <String>[];

    if (v.rhythmVariance > 0.4) {
      final pct = (v.rhythmVariance * 100).toStringAsFixed(0);
      reasons.add('Typing cadence ($pct% deviation from baseline)');
    }
    if (v.jitterRms > 0.5) {
      reasons.add('Hand steadiness: abnormal micro-tremor detected');
    }
    if (v.gyroRms > 0.6) {
      reasons.add('Device orientation: unusual rotation pattern');
    }
    if (v.touchPressure < 0.3) {
      reasons.add('Touch pressure: unusually light (possible bot/stylus)');
    }
    if (isDemoMuleMode) {
      reasons.add('Behavioral profile: matches known mule pattern');
    }

    // Baseline deviation reason
    final baseline = _repo.loadBaseline();
    if (baseline != null) {
      final dev = _repo.computeDeviation(v.toList(), baseline);
      if (dev > 0.25) {
        reasons.add(
            'Aggregate deviation from your profile: ${(dev * 100).toStringAsFixed(0)}%');
      }
    }

    return reasons.isEmpty ? ['Aggregate behavioral deviation > 25%'] : reasons;
  }

  bool get isAnomaly => confidence < 0.75 || isDemoMuleMode;
}
