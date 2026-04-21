// lib/services/upi_gateway.dart
//
// SAFETY GATE: Every UPI transaction passes through a 4-layer security stack.
//
//   Layer 1 — Behavioral Firewall    : SoulprintEngine confidence < 0.75 → block
//   Layer 2 — VPA Reputation         : scam pattern / mule account → block
//   Layer 3 — Context Risk           : call active / location jump / amount spike
//   Layer 4 — Face Liveness          : required for transactions above ₹10,000

import 'package:flutter/material.dart';
import 'package:upi_india/upi_india.dart';

import '../core/soulprint_engine.dart';
import 'face_liveness_service.dart';
import 'risk_context_service.dart';

enum TransactionResult {
  success,
  failure,
  anomalyBlocked,    // Layer 1: behavioral
  vpaBlocked,        // Layer 2: VPA reputation
  contextBlocked,    // Layer 3: environment risk
  livenessBlocked,   // Layer 4: face liveness failed
  submitted,
}

class UpiGateway {
  final UpiIndia _upi = UpiIndia();

  Future<List<UpiApp>?> getInstalledApps() async =>
      await _upi.getAllUpiApps(mandatoryTransactionId: false);

  Future<({TransactionResult result, String message, UpiResponse? response})>
      initiatePayment({
    required SoulprintEngine engine,
    required RiskContextService riskService,
    required BuildContext context,
    required UpiApp app,
    required String vpa,
    required String amount,
    String note = 'VigilUPI Payment',
  }) async {
    final amountVal = double.tryParse(amount) ?? 0.0;

    // ── Layer 1: Behavioral Firewall ──────────────────────────────────────
    if (engine.isAnomaly) {
      return (
        result: TransactionResult.anomalyBlocked,
        message: 'Blocked by Soulprint™ Engine — behavioral anomaly.',
        response: null,
      );
    }

    // ── Layer 2: VPA Reputation ───────────────────────────────────────────
    final vpaRep = riskService.checkVpa(vpa);
    if (vpaRep.isFlagged) {
      return (
        result: TransactionResult.vpaBlocked,
        message: 'Recipient flagged: ${vpaRep.reason}',
        response: null,
      );
    }

    // ── Layer 3: Context Risk ─────────────────────────────────────────────
    final contextRisk =
        await riskService.evaluate(amount: amountVal, vpa: vpa);
    if (contextRisk.hasHardBlock) {
      final reason = contextRisk.elevated.first.reason;
      return (
        result: TransactionResult.contextBlocked,
        message: 'Context risk: $reason',
        response: null,
      );
    }

    // ── Layer 4: Face Liveness (high-value only) ──────────────────────────
    if (amountVal >= kLivenessThreshold) {
      // ignore: use_build_context_synchronously
      final passed = await LivenessCheckDialog.show(context);
      if (!passed) {
        return (
          result: TransactionResult.livenessBlocked,
          message: 'Face liveness check failed for ₹$amount transaction.',
          response: null,
        );
      }
    }

    // ── All layers passed — launch UPI intent ─────────────────────────────
    try {
      // Pass amount as whole integer value — no decimals.
      // "10" not "10.0" or "10.00" to avoid bank/app parsing issues.
      final wholeAmount = amountVal.truncate().toDouble();
      final response = await _upi.startTransaction(
        app: app,
        receiverUpiId: vpa,
        receiverName: 'VigilUPI Merchant',
        transactionRefId: 'VIGIL_${DateTime.now().millisecondsSinceEpoch}',
        transactionNote: note,
        amount: wholeAmount,
      );

      final result = _mapStatus(response.status);
      await riskService.recordTransaction(
        vpa: vpa,
        amount: amountVal,
        blocked: false,
      );
      return (
        result: result,
        message: response.status ?? 'Unknown status',
        response: response,
      );
    } catch (e) {
      return (
        result: TransactionResult.failure,
        message: 'UPI error: ${e.toString()}',
        response: null,
      );
    }
  }

  TransactionResult _mapStatus(String? status) {
    switch (status?.toUpperCase()) {
      case 'SUCCESS':
        return TransactionResult.success;
      case 'SUBMITTED':
        return TransactionResult.submitted;
      default:
        return TransactionResult.failure;
    }
  }
}
