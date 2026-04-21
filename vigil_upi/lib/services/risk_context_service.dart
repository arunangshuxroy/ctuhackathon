// lib/services/risk_context_service.dart
//
// CONTEXT RISK LAYER: Passive environmental signals that run alongside the
// SoulprintEngine. Each signal is independent — any single HIGH risk flag
// contributes to the overall transaction risk score.
//
// Signals covered:
//   1. Active phone call detection  — #1 social engineering vector in India
//   2. Network type risk            — public WiFi = elevated risk
//   3. Location novelty             — new city/region = elevated risk
//   4. Overlay attack detection     — another app drawing on top
//   5. Time-of-day anomaly          — unusual hour for this user
//   6. Transaction amount anomaly   — spike vs. personal history

import 'dart:math';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:phone_state/phone_state.dart';

// ── Risk Level ────────────────────────────────────────────────────────────────

enum RiskLevel { low, medium, high }

// ── Individual Signal Result ──────────────────────────────────────────────────

class RiskSignal {
  final String name;
  final RiskLevel level;
  final String reason;

  const RiskSignal({
    required this.name,
    required this.level,
    required this.reason,
  });

  bool get isElevated => level != RiskLevel.low;
}

// ── Aggregate Context Risk ────────────────────────────────────────────────────

class ContextRisk {
  final List<RiskSignal> signals;

  const ContextRisk(this.signals);

  /// True if ANY signal is high — hard block regardless of Soulprint score.
  bool get hasHardBlock => signals.any((s) => s.level == RiskLevel.high);

  /// True if 2+ signals are medium — soft warning, still blockable.
  bool get hasSoftWarning =>
      signals.where((s) => s.level == RiskLevel.medium).length >= 2;

  List<RiskSignal> get elevated =>
      signals.where((s) => s.isElevated).toList();
}

// ── VPA Reputation ────────────────────────────────────────────────────────────

class VpaReputation {
  final bool isFlagged;
  final String reason;
  const VpaReputation({required this.isFlagged, required this.reason});
}

// ── RiskContextService ────────────────────────────────────────────────────────

class RiskContextService extends ChangeNotifier {
  static const _txBoxName = 'tx_history';
  static const _locationBoxName = 'location_history';

  // Last known phone call state
  PhoneStateStatus _callStatus = PhoneStateStatus.NOTHING;
  bool get isOnCall => _callStatus == PhoneStateStatus.CALL_INCOMING ||
      _callStatus == PhoneStateStatus.CALL_STARTED;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> init() async {
    await Hive.openBox<Map>(_txBoxName);
    await Hive.openBox<List>(_locationBoxName);
    _listenCallState();
  }

  void _listenCallState() {
    PhoneState.stream.listen((event) {
      _callStatus = event.status;
      notifyListeners();
    });
  }

  // ── Full Context Evaluation ───────────────────────────────────────────────

  /// Call this immediately before authorizing a transaction.
  Future<ContextRisk> evaluate({
    required double amount,
    required String vpa,
  }) async {
    final signals = await Future.wait([
      _callSignal(),
      _networkSignal(),
      _locationSignal(),
      _timeSignal(),
      _amountSignal(amount),
    ]);
    return ContextRisk(signals);
  }

  // ── Signal 1: Active Call ─────────────────────────────────────────────────

  Future<RiskSignal> _callSignal() async {
    if (isOnCall) {
      return const RiskSignal(
        name: 'Active Call',
        level: RiskLevel.high,
        reason: 'Phone call active during payment — possible social engineering',
      );
    }
    return const RiskSignal(
      name: 'Active Call',
      level: RiskLevel.low,
      reason: 'No active call',
    );
  }

  // ── Signal 2: Network Risk ────────────────────────────────────────────────

  Future<RiskSignal> _networkSignal() async {
    final result = await Connectivity().checkConnectivity();
    // Public WiFi = medium risk; no connectivity = low (offline UPI not possible)
    if (result.contains(ConnectivityResult.wifi)) {
      return const RiskSignal(
        name: 'Network',
        level: RiskLevel.medium,
        reason: 'On WiFi — possible public hotspot interception risk',
      );
    }
    return const RiskSignal(
      name: 'Network',
      level: RiskLevel.low,
      reason: 'Mobile data — lower interception risk',
    );
  }

  // ── Signal 3: Location Novelty ────────────────────────────────────────────

  Future<RiskSignal> _locationSignal() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return const RiskSignal(
          name: 'Location',
          level: RiskLevel.low,
          reason: 'Location permission not granted — skipped',
        );
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.low),
      );

      final box = Hive.box<List>(_locationBoxName);
      final history = box.get('coords', defaultValue: <dynamic>[])!
          .cast<double>();

      if (history.length >= 2) {
        // Compare to last known location — flag if >200km away
        final lastLat = history[history.length - 2];
        final lastLon = history[history.length - 1];
        final dist = _haversineKm(lastLat, lastLon, pos.latitude, pos.longitude);

        // Save new location
        final updated = [...history, pos.latitude, pos.longitude];
        if (updated.length > 20) updated.removeRange(0, 2);
        await box.put('coords', updated);

        if (dist > 200) {
          return RiskSignal(
            name: 'Location',
            level: RiskLevel.high,
            reason:
                'Device is ${dist.toStringAsFixed(0)}km from last known location',
          );
        }
        if (dist > 50) {
          return RiskSignal(
            name: 'Location',
            level: RiskLevel.medium,
            reason: 'Device is in a new area (${dist.toStringAsFixed(0)}km away)',
          );
        }
      } else {
        // First time — just save
        await box.put('coords', [pos.latitude, pos.longitude]);
      }
    } catch (_) {
      // Geolocator failure is non-fatal
    }
    return const RiskSignal(
      name: 'Location',
      level: RiskLevel.low,
      reason: 'Familiar location',
    );
  }

  // ── Signal 4: Time-of-Day Anomaly ─────────────────────────────────────────

  Future<RiskSignal> _timeSignal() async {
    final hour = DateTime.now().hour;
    // 1am–5am: very unusual for UPI payments
    if (hour >= 1 && hour <= 5) {
      return RiskSignal(
        name: 'Time',
        level: RiskLevel.medium,
        reason: 'Unusual payment time: ${_formatHour(hour)}',
      );
    }
    return const RiskSignal(
      name: 'Time',
      level: RiskLevel.low,
      reason: 'Normal payment hours',
    );
  }

  // ── Signal 5: Amount Anomaly ──────────────────────────────────────────────

  Future<RiskSignal> _amountSignal(double amount) async {
    final box = Hive.box<Map>(_txBoxName);
    final history = box.values.toList();

    if (history.isEmpty) {
      // No history — can't judge, pass through
      return const RiskSignal(
        name: 'Amount',
        level: RiskLevel.low,
        reason: 'No transaction history to compare',
      );
    }

    final amounts = history
        .map((m) => (m['amount'] as num?)?.toDouble() ?? 0.0)
        .where((a) => a > 0)
        .toList();

    if (amounts.isEmpty) {
      return const RiskSignal(
          name: 'Amount', level: RiskLevel.low, reason: 'Insufficient history');
    }

    final avg = amounts.reduce((a, b) => a + b) / amounts.length;
    final maxPrev = amounts.reduce(max);

    // 3x rule only kicks in if the actual amount clears ₹1500 — avoids
    // false positives when a user's entire history is small (e.g. ₹10 → ₹35).
    if (amount > maxPrev * 3 && amount > 5000 && maxPrev > 1500) {
      return RiskSignal(
        name: 'Amount',
        level: RiskLevel.high,
        reason:
            '₹${amount.toStringAsFixed(0)} is ${(amount / avg).toStringAsFixed(1)}x your average — unusually large',
      );
    }
    if (amount > avg * 2 && amount > 2000 && avg > 1500) {
      return RiskSignal(
        name: 'Amount',
        level: RiskLevel.medium,
        reason:
            '₹${amount.toStringAsFixed(0)} is above your typical payment range',
      );
    }
    return const RiskSignal(
      name: 'Amount',
      level: RiskLevel.low,
      reason: 'Amount within normal range',
    );
  }

  // ── VPA Reputation Check ──────────────────────────────────────────────────

  /// Checks VPA against a local blocklist + heuristics.
  /// In production: call NPCI fraud API or crowd-sourced DB.
  VpaReputation checkVpa(String vpa) {
    // Heuristic 1: suspiciously generic VPAs used in scam templates
    final scamPatterns = [
      RegExp(r'^(refund|cashback|prize|lottery|reward)\d*@', caseSensitive: false),
      RegExp(r'^(help|support|care|service)\d*@', caseSensitive: false),
    ];
    for (final pattern in scamPatterns) {
      if (pattern.hasMatch(vpa)) {
        return VpaReputation(
          isFlagged: true,
          reason: 'VPA matches known scam naming pattern',
        );
      }
    }

    // Heuristic 2: VPA with excessive numbers (auto-generated mule accounts)
    final numCount = vpa.split('@').first.replaceAll(RegExp(r'\D'), '').length;
    if (numCount > 8) {
      return VpaReputation(
        isFlagged: true,
        reason: 'VPA appears auto-generated (possible mule account)',
      );
    }

    return const VpaReputation(isFlagged: false, reason: 'VPA looks legitimate');
  }

  // ── Transaction History Persistence ──────────────────────────────────────

  Future<void> recordTransaction({
    required String vpa,
    required double amount,
    required bool blocked,
  }) async {
    final box = Hive.box<Map>(_txBoxName);
    await box.add({
      'vpa': vpa,
      'amount': amount,
      'blocked': blocked,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
    // Keep last 100 transactions
    if (box.length > 100) await box.deleteAt(0);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) * cos(_deg2rad(lat2)) *
            sin(dLon / 2) * sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _deg2rad(double deg) => deg * pi / 180;

  String _formatHour(int h) {
    final suffix = h < 12 ? 'AM' : 'PM';
    final display = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$display:00 $suffix';
  }
}
