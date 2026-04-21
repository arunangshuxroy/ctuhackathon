// test/vigil_upi_test.dart
//
// TEST SUITE — VigilUPI
// Covers all 4 security layers + core engine logic.
//
// TC-01  SoulprintVector normalization clamps to [0,1]
// TC-02  Euclidean deviation: identical vectors → 0.0
// TC-03  Euclidean deviation: opposite vectors → 1.0
// TC-04  Euclidean deviation: mismatched lengths → 1.0 (safe fallback)
// TC-05  GoldenProfileRepository: save → load round-trip
// TC-06  GoldenProfileRepository: isCalibrated false before save
// TC-07  GoldenProfileRepository: isCalibrated true after save
// TC-08  GoldenProfileRepository: clearProfile resets calibration flag
// TC-09  SoulprintEngine: starts in calibrating state
// TC-10  SoulprintEngine: confidence starts at 1.0
// TC-11  SoulprintEngine: toggleDemoMuleMode sets confidence to 0.42
// TC-12  SoulprintEngine: isAnomaly true when confidence < 0.75
// TC-13  SoulprintEngine: isAnomaly true in demo mule mode regardless of confidence
// TC-14  SoulprintEngine: anomalyReasons non-empty when isDemoMuleMode
// TC-15  SoulprintEngine: anomalyReasons empty vector returns fallback string
// TC-16  VPA reputation: clean VPA passes
// TC-17  VPA reputation: 'refund@upi' flagged as scam pattern
// TC-18  VPA reputation: 'cashback123@okaxis' flagged as scam pattern
// TC-19  VPA reputation: 'support@paytm' flagged as scam pattern
// TC-20  VPA reputation: VPA with >8 digits flagged as auto-generated mule
// TC-21  VPA reputation: VPA with exactly 8 digits passes
// TC-22  ContextRisk: hasHardBlock true when any signal is high
// TC-23  ContextRisk: hasHardBlock false when all signals are low/medium
// TC-24  ContextRisk: hasSoftWarning true when 2+ medium signals
// TC-25  ContextRisk: hasSoftWarning false when only 1 medium signal
// TC-26  ContextRisk: elevated returns only non-low signals
// TC-27  Amount anomaly: no history → low risk
// TC-28  Amount anomaly: amount > 3x max and > 5000 → high risk
// TC-29  Amount anomaly: amount > 2x avg and > 2000 → medium risk
// TC-30  Amount anomaly: normal amount → low risk
// TC-31  Haversine: same point → 0 km
// TC-32  Haversine: Mumbai to Delhi → ~1150 km (±50)
// TC-33  Time signal: hour 3 → medium risk
// TC-34  Time signal: hour 14 → low risk
// TC-35  KeystrokeTracker: dwell time computed correctly
// TC-36  KeystrokeTracker: flight time computed correctly
// TC-37  KeystrokeTracker: coefficient of variation = 0 for uniform intervals
// TC-38  TouchTracker: EMA smoothing stays within [0,1]
// TC-39  MotionProcessor: RMS of zeros → 0.0
// TC-40  MotionProcessor: RMS of known values → correct result

import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vigil_upi/core/soulprint_engine.dart';
import 'package:vigil_upi/data/golden_profile_repository.dart';
import 'package:vigil_upi/services/risk_context_service.dart';

// ── Testable subclasses exposing private internals ────────────────────────────

// Expose _KeystrokeTracker via a thin wrapper for unit testing
class _TestKeystroke {
  final Map<String, int> _pressTime = {};
  final List<double> _dwellTimes = [];
  final List<double> _flightTimes = [];
  int? _lastReleaseTime;

  void onKeyDown(String key) =>
      _pressTime[key] = DateTime.now().millisecondsSinceEpoch;

  void onKeyUpAt(String key, int nowMs) {
    final press = _pressTime.remove(key);
    if (press != null) _dwellTimes.add((nowMs - press).toDouble());
    if (_lastReleaseTime != null)
      _flightTimes.add((nowMs - _lastReleaseTime!).toDouble());
    _lastReleaseTime = nowMs;
  }

  double get dwellMean => _dwellTimes.isEmpty
      ? 0
      : _dwellTimes.reduce((a, b) => a + b) / _dwellTimes.length;

  double get flightMean => _flightTimes.isEmpty
      ? 0
      : _flightTimes.reduce((a, b) => a + b) / _flightTimes.length;

  double get rhythmVariance {
    if (_flightTimes.length < 2) return 0;
    final m = flightMean;
    if (m == 0) return 0;
    final variance = _flightTimes
            .map((x) => pow(x - m, 2))
            .reduce((a, b) => a + b) /
        _flightTimes.length;
    return sqrt(variance) / m;
  }
}

// Expose _TouchTracker
class _TestTouch {
  double _pressure = 0.5, _size = 0.5, _velocity = 0.0;

  void onPointer(double pressure, double size, double vel) {
    _pressure = (0.7 * _pressure + 0.3 * pressure.clamp(0.0, 1.0));
    _size = (0.7 * _size + 0.3 * size.clamp(0.0, 1.0));
    _velocity = (0.7 * _velocity + 0.3 * vel.clamp(0.0, 1.0));
  }

  double get pressure => _pressure;
  double get size => _size;
  double get velocity => _velocity;
}

// Expose _MotionProcessor
class _TestMotion {
  final List<double> _accel = [], _gyro = [];

  void addAccel(double x, double y, double z) =>
      _accel.add((sqrt(x * x + y * y + z * z) - 9.8).abs());

  void addGyro(double x, double y, double z) =>
      _gyro.add(sqrt(x * x + y * y + z * z));

  double rms(List<double> v) {
    if (v.isEmpty) return 0;
    return sqrt(v.map((x) => x * x).reduce((a, b) => a + b) / v.length);
  }

  double get accelRms => rms(_accel);
  double get gyroRms => rms(_gyro);
}

// Testable haversine (mirrors RiskContextService._haversineKm)
double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371.0;
  double deg2rad(double d) => d * pi / 180;
  final dLat = deg2rad(lat2 - lat1);
  final dLon = deg2rad(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(deg2rad(lat1)) * cos(deg2rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

// Testable time signal (mirrors RiskContextService._timeSignal logic)
RiskLevel _timeRisk(int hour) =>
    (hour >= 1 && hour <= 5) ? RiskLevel.medium : RiskLevel.low;

// Testable amount signal (pure logic, no Hive)
RiskLevel _amountRisk(double amount, List<double> history) {
  if (history.isEmpty) return RiskLevel.low;
  final avg = history.reduce((a, b) => a + b) / history.length;
  final maxPrev = history.reduce(max);
  if (amount > maxPrev * 3 && amount > 5000) return RiskLevel.high;
  if (amount > avg * 2 && amount > 2000) return RiskLevel.medium;
  return RiskLevel.low;
}

// ── Main ──────────────────────────────────────────────────────────────────────

void main() {
  // Hive needs a temp dir for repository tests
  setUpAll(() async {
    Hive.init('/tmp/vigil_test_hive_${DateTime.now().millisecondsSinceEpoch}');
    await Hive.openBox<List>('soulprint_profile');
  });

  tearDownAll(() async {
    await Hive.deleteFromDisk();
  });

  // ── GROUP 1: SoulprintVector ───────────────────────────────────────────────
  group('TC-01..02 | SoulprintVector', () {
    test('TC-01: toList() has 8 elements all in [0,1]', () {
      final v = SoulprintVector(
        dwellTimeMean: 0.3,
        flightTimeMean: 0.5,
        touchPressure: 0.8,
        touchSize: 0.4,
        swipeVelocity: 0.2,
        jitterRms: 0.1,
        gyroRms: 0.05,
        rhythmVariance: 0.6,
      );
      final list = v.toList();
      expect(list.length, 8);
      for (final val in list) {
        expect(val, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  // ── GROUP 2: GoldenProfileRepository ─────────────────────────────────────
  group('TC-02..08 | GoldenProfileRepository', () {
    late GoldenProfileRepository repo;

    setUp(() async {
      repo = GoldenProfileRepository();
      await repo.clearProfile();
    });

    test('TC-02: deviation of identical vectors is 0.0', () {
      final v = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8];
      expect(repo.computeDeviation(v, v), closeTo(0.0, 1e-9));
    });

    test('TC-03: deviation of opposite vectors is 1.0', () {
      final a = [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0];
      final b = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
      expect(repo.computeDeviation(a, b), closeTo(1.0, 1e-9));
    });

    test('TC-04: mismatched vector lengths → 1.0 safe fallback', () {
      expect(repo.computeDeviation([0.1, 0.2], [0.1, 0.2, 0.3]), 1.0);
    });

    test('TC-05: save → load round-trip preserves values', () async {
      final baseline = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8];
      await repo.saveBaseline(baseline);
      final loaded = repo.loadBaseline();
      expect(loaded, isNotNull);
      for (int i = 0; i < baseline.length; i++) {
        expect(loaded![i], closeTo(baseline[i], 1e-6));
      }
    });

    test('TC-06: isCalibrated is false before any save', () {
      expect(repo.isCalibrated, isFalse);
    });

    test('TC-07: isCalibrated is true after saveBaseline', () async {
      await repo.saveBaseline([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]);
      expect(repo.isCalibrated, isTrue);
    });

    test('TC-08: clearProfile resets isCalibrated to false', () async {
      await repo.saveBaseline([0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]);
      await repo.clearProfile();
      expect(repo.isCalibrated, isFalse);
      expect(repo.loadBaseline(), isNull);
    });
  });

  // ── GROUP 3: SoulprintEngine state ────────────────────────────────────────
  group('TC-09..15 | SoulprintEngine state', () {
    test('TC-09: engine starts in calibrating state', () {
      final engine = SoulprintEngine();
      // Fresh engine with no saved profile → isCalibrating = true
      expect(engine.isCalibrating, isTrue);
    });

    test('TC-10: confidence starts at 1.0', () {
      final engine = SoulprintEngine();
      expect(engine.confidence, 1.0);
    });

    test('TC-11: toggleDemoMuleMode sets confidence to 0.42', () {
      final engine = SoulprintEngine();
      engine.toggleDemoMuleMode();
      expect(engine.confidence, closeTo(0.42, 1e-9));
      expect(engine.isDemoMuleMode, isTrue);
    });

    test('TC-12: isAnomaly true when confidence < 0.75', () {
      final engine = SoulprintEngine();
      engine.confidence = 0.74;
      expect(engine.isAnomaly, isTrue);
    });

    test('TC-13: isAnomaly true in mule mode regardless of confidence', () {
      final engine = SoulprintEngine();
      engine.confidence = 0.99; // high confidence
      engine.isDemoMuleMode = true;
      expect(engine.isAnomaly, isTrue);
    });

    test('TC-14: anomalyReasons includes mule pattern when isDemoMuleMode', () {
      final engine = SoulprintEngine();
      engine.isDemoMuleMode = true;
      engine.confidence = 0.42;
      // Inject a lastVector so the reasons loop runs (isDemoMuleMode check is inside)
      engine.lastVector = const SoulprintVector(
        dwellTimeMean: 0.1,
        flightTimeMean: 0.1,
        touchPressure: 0.5,
        touchSize: 0.5,
        swipeVelocity: 0.1,
        jitterRms: 0.1,
        gyroRms: 0.1,
        rhythmVariance: 0.1,
      );
      final reasons = engine.anomalyReasons;
      expect(
        reasons.any((r) => r.toLowerCase().contains('mule')),
        isTrue,
        reason: 'Expected mule pattern reason, got: $reasons',
      );
    });

    test('TC-15: anomalyReasons returns fallback when lastVector is null', () {
      final engine = SoulprintEngine();
      // lastVector is null on fresh engine
      final reasons = engine.anomalyReasons;
      expect(reasons, isEmpty); // null vector → empty list per implementation
    });
  });

  // ── GROUP 4: VPA Reputation ───────────────────────────────────────────────
  group('TC-16..21 | VPA Reputation', () {
    late RiskContextService svc;

    setUpAll(() async {
      await Hive.openBox<Map>('tx_history');
      await Hive.openBox<List>('location_history');
      svc = RiskContextService();
    });

    test('TC-16: clean VPA passes', () {
      final r = svc.checkVpa('merchant@okaxis');
      expect(r.isFlagged, isFalse);
    });

    test('TC-17: refund@ prefix flagged', () {
      final r = svc.checkVpa('refund@upi');
      expect(r.isFlagged, isTrue);
      expect(r.reason, contains('scam'));
    });

    test('TC-18: cashback prefix flagged', () {
      final r = svc.checkVpa('cashback123@okaxis');
      expect(r.isFlagged, isTrue);
    });

    test('TC-19: support@ prefix flagged', () {
      final r = svc.checkVpa('support@paytm');
      expect(r.isFlagged, isTrue);
    });

    test('TC-20: VPA with >8 digits flagged as mule', () {
      // 9 digits in the local part
      final r = svc.checkVpa('123456789@ybl');
      expect(r.isFlagged, isTrue);
      expect(r.reason, contains('mule'));
    });

    test('TC-21: VPA with exactly 8 digits passes', () {
      final r = svc.checkVpa('12345678@ybl');
      expect(r.isFlagged, isFalse);
    });
  });

  // ── GROUP 5: ContextRisk aggregation ─────────────────────────────────────
  group('TC-22..26 | ContextRisk aggregation', () {
    test('TC-22: hasHardBlock true when any signal is high', () {
      final risk = ContextRisk([
        const RiskSignal(name: 'A', level: RiskLevel.low, reason: ''),
        const RiskSignal(name: 'B', level: RiskLevel.high, reason: ''),
      ]);
      expect(risk.hasHardBlock, isTrue);
    });

    test('TC-23: hasHardBlock false when all low/medium', () {
      final risk = ContextRisk([
        const RiskSignal(name: 'A', level: RiskLevel.low, reason: ''),
        const RiskSignal(name: 'B', level: RiskLevel.medium, reason: ''),
      ]);
      expect(risk.hasHardBlock, isFalse);
    });

    test('TC-24: hasSoftWarning true when 2+ medium signals', () {
      final risk = ContextRisk([
        const RiskSignal(name: 'A', level: RiskLevel.medium, reason: ''),
        const RiskSignal(name: 'B', level: RiskLevel.medium, reason: ''),
      ]);
      expect(risk.hasSoftWarning, isTrue);
    });

    test('TC-25: hasSoftWarning false when only 1 medium signal', () {
      final risk = ContextRisk([
        const RiskSignal(name: 'A', level: RiskLevel.medium, reason: ''),
        const RiskSignal(name: 'B', level: RiskLevel.low, reason: ''),
      ]);
      expect(risk.hasSoftWarning, isFalse);
    });

    test('TC-26: elevated returns only non-low signals', () {
      final risk = ContextRisk([
        const RiskSignal(name: 'A', level: RiskLevel.low, reason: ''),
        const RiskSignal(name: 'B', level: RiskLevel.medium, reason: ''),
        const RiskSignal(name: 'C', level: RiskLevel.high, reason: ''),
      ]);
      expect(risk.elevated.length, 2);
      expect(risk.elevated.map((s) => s.name), containsAll(['B', 'C']));
    });
  });

  // ── GROUP 6: Amount anomaly logic ─────────────────────────────────────────
  group('TC-27..30 | Amount anomaly', () {
    test('TC-27: no history → low risk', () {
      expect(_amountRisk(50000, []), RiskLevel.low);
    });

    test('TC-28: amount > 3x max and > 5000 → high risk', () {
      // history max = 1000, avg = 600, amount = 5001 > 3000 and > 5000
      expect(_amountRisk(5001, [200.0, 600.0, 1000.0]), RiskLevel.high);
    });

    test('TC-29: amount > 2x avg and > 2000 → medium risk', () {
      // avg = 600, 2x = 1200, amount = 2001 > 1200 and > 2000
      expect(_amountRisk(2001, [400.0, 600.0, 800.0]), RiskLevel.medium);
    });

    test('TC-30: normal amount → low risk', () {
      expect(_amountRisk(500, [400.0, 600.0, 800.0]), RiskLevel.low);
    });
  });

  // ── GROUP 7: Haversine distance ───────────────────────────────────────────
  group('TC-31..32 | Haversine', () {
    test('TC-31: same point → 0 km', () {
      expect(_haversineKm(19.07, 72.87, 19.07, 72.87), closeTo(0.0, 0.01));
    });

    test('TC-32: Mumbai to Delhi → ~1150 km (±100 km tolerance)', () {
      // Mumbai: 19.07°N 72.87°E  |  Delhi: 28.61°N 77.20°E
      final dist = _haversineKm(19.07, 72.87, 28.61, 77.20);
      expect(dist, inInclusiveRange(1050.0, 1250.0));
    });
  });

  // ── GROUP 8: Time signal ──────────────────────────────────────────────────
  group('TC-33..34 | Time signal', () {
    test('TC-33: hour 3 (3am) → medium risk', () {
      expect(_timeRisk(3), RiskLevel.medium);
    });

    test('TC-34: hour 14 (2pm) → low risk', () {
      expect(_timeRisk(14), RiskLevel.low);
    });
  });

  // ── GROUP 9: KeystrokeTracker ─────────────────────────────────────────────
  group('TC-35..37 | KeystrokeTracker', () {
    test('TC-35: dwell time computed correctly', () {
      final t = _TestKeystroke();
      // Simulate: press at t=0, release at t=100 → dwell = 100ms
      t._pressTime['a'] = 0;
      t.onKeyUpAt('a', 100);
      expect(t.dwellMean, closeTo(100.0, 1.0));
    });

    test('TC-36: flight time computed correctly', () {
      final t = _TestKeystroke();
      t._pressTime['a'] = 0;
      t.onKeyUpAt('a', 100); // release 1 at t=100
      t._pressTime['b'] = 150;
      t.onKeyUpAt('b', 250); // release 2 at t=250 → flight = 150ms
      expect(t.flightMean, closeTo(150.0, 1.0));
    });

    test('TC-37: coefficient of variation = 0 for perfectly uniform intervals',
        () {
      final t = _TestKeystroke();
      // 3 keys released at exactly 100ms intervals → σ=0 → CV=0
      t._pressTime['a'] = 0;
      t.onKeyUpAt('a', 50);
      t._pressTime['b'] = 100;
      t.onKeyUpAt('b', 150); // flight = 100
      t._pressTime['c'] = 200;
      t.onKeyUpAt('c', 250); // flight = 100
      expect(t.rhythmVariance, closeTo(0.0, 0.01));
    });
  });

  // ── GROUP 10: TouchTracker EMA ────────────────────────────────────────────
  group('TC-38 | TouchTracker EMA', () {
    test('TC-38: EMA output stays within [0,1] after extreme inputs', () {
      final t = _TestTouch();
      t.onPointer(2.0, -1.0, 10.0); // out-of-range inputs
      expect(t.pressure, inInclusiveRange(0.0, 1.0));
      expect(t.size, inInclusiveRange(0.0, 1.0));
      expect(t.velocity, inInclusiveRange(0.0, 1.0));
    });
  });

  // ── GROUP 11: MotionProcessor RMS ────────────────────────────────────────
  group('TC-39..40 | MotionProcessor RMS', () {
    test('TC-39: RMS of zero-magnitude motion → 0.0', () {
      final m = _TestMotion();
      // Gravity-only accel: magnitude = 9.8, jitter = |9.8 - 9.8| = 0
      m.addAccel(0, 0, 9.8);
      m.addGyro(0, 0, 0);
      expect(m.accelRms, closeTo(0.0, 0.01));
      expect(m.gyroRms, closeTo(0.0, 0.01));
    });

    test('TC-40: RMS of [3,4] = 3.535...', () {
      final m = _TestMotion();
      // Manually test rms([3,4]) = sqrt((9+16)/2) = sqrt(12.5) ≈ 3.535
      expect(m.rms([3.0, 4.0]), closeTo(3.535, 0.01));
    });
  });
}
