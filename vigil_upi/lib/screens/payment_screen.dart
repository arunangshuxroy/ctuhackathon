// lib/screens/payment_screen.dart
//
// THE STAGE: Every interaction on this screen feeds the SoulprintEngine.
// The UI reflects the live confidence score in real-time.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:upi_india/upi_india.dart';

import '../core/soulprint_engine.dart';
import '../services/risk_context_service.dart';
import '../services/upi_gateway.dart';
import '../theme/app_theme.dart';
import '../widgets/biometric_visualizer.dart';

class PaymentScreen extends StatefulWidget {
  const PaymentScreen({super.key});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final _vpaController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _gateway = UpiGateway();

  List<UpiApp> _upiApps = [];
  UpiApp? _selectedApp;
  bool _devMode = false;
  bool _isLoading = false;

  // Recent transaction log — shown in the UI for demo credibility
  final List<({String vpa, String amount, bool blocked, DateTime time})>
      _txHistory = [];

  @override
  void initState() {
    super.initState();
    _loadUpiApps();
  }

  Future<void> _loadUpiApps() async {
    final apps = await _gateway.getInstalledApps();
    if (mounted) setState(() => _upiApps = apps ?? []);
  }

  @override
  void dispose() {
    _vpaController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ── Payment Trigger ───────────────────────────────────────────────────────

  Future<void> _onAuthorize() async {
    final engine = context.read<SoulprintEngine>();
    final riskService = context.read<RiskContextService>();

    if (engine.isCalibrating) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('⏳ Soulprint calibrating — keep typing to complete.'),
        backgroundColor: AppTheme.warning,
      ));
      return;
    }

    if (engine.isAnomaly) {
      _showAnomalyOverlay(engine);
      return;
    }

    if (_selectedApp == null ||
        _vpaController.text.isEmpty ||
        _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please fill all fields and select a UPI app.'),
      ));
      return;
    }

    // Show context risk warning (soft block) before proceeding
    final amountVal = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final contextRisk = await riskService.evaluate(
        amount: amountVal, vpa: _vpaController.text.trim());
    if (contextRisk.hasSoftWarning && mounted) {
      final proceed = await _showContextRiskWarning(contextRisk);
      if (!proceed) return;
    }

    setState(() => _isLoading = true);

    // Strip decimals — pass whole rupee amount only
    final normalizedAmount = amountVal.truncate().toString();

    final result = await _gateway.initiatePayment(
      engine: engine,
      riskService: riskService,
      context: context,
      app: _selectedApp!,
      vpa: _vpaController.text.trim(),
      amount: normalizedAmount,
      note: _noteController.text.trim(),
    );

    if (!mounted) return;
    final blocked = result.result == TransactionResult.anomalyBlocked ||
        result.result == TransactionResult.vpaBlocked ||
        result.result == TransactionResult.contextBlocked ||
        result.result == TransactionResult.livenessBlocked;

    await riskService.recordTransaction(
      vpa: _vpaController.text.trim(),
      amount: amountVal,
      blocked: blocked,
    );

    setState(() {
      _isLoading = false;
      _txHistory.insert(0, (
        vpa: _vpaController.text.trim(),
        amount: normalizedAmount,
        blocked: blocked,
        time: DateTime.now(),
      ));
      if (_txHistory.length > 5) _txHistory.removeLast();
    });

    if (result.result == TransactionResult.anomalyBlocked) {
      _showAnomalyOverlay(engine);
    } else if (blocked) {
      _showBlockedSnackbar(result.message);
    } else {
      _showResultSnackbar(result.result, result.message);
    }
  }

  void _showResultSnackbar(TransactionResult r, String msg) {
    final isSuccess = r == TransactionResult.success;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: isSuccess ? AppTheme.success : AppTheme.danger,
      content: Text(msg, style: const TextStyle(color: Colors.black)),
    ));
  }

  void _showBlockedSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppTheme.danger,
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      duration: const Duration(seconds: 4),
    ));
  }

  // ── Context Risk Warning Dialog ───────────────────────────────────────────

  Future<bool> _showContextRiskWarning(ContextRisk risk) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1040),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: AppTheme.warning, size: 22),
                SizedBox(width: 8),
                Text('Risk Warning',
                    style: TextStyle(
                        color: AppTheme.warning,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Elevated risk signals detected:',
                    style: TextStyle(
                        color: AppTheme.textSecondary, fontSize: 12)),
                const SizedBox(height: 10),
                ...risk.elevated.map((s) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.arrow_right_rounded,
                              color: AppTheme.warning, size: 16),
                          Expanded(
                            child: Text(s.reason,
                                style: const TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 12)),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(color: AppTheme.textSecondary)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Proceed Anyway',
                    style: TextStyle(color: AppTheme.warning)),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Anomaly Block Overlay ─────────────────────────────────────────────────

  void _showAnomalyOverlay(SoulprintEngine engine) {
    HapticFeedback.heavyImpact(); // Tactile alert on anomaly
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnomalyBlockSheet(engine: engine),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _background(),
          SafeArea(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _topBar(),
                  const SizedBox(height: 20),
                  _soulprintPill(),
                  const SizedBox(height: 12),
                  _calibrationBanner(),
                  const SizedBox(height: 16),
                  _paymentCard(),
                  const SizedBox(height: 16),
                  _authorizeButton(),
                  const SizedBox(height: 20),
                  _devModeToggle(),
                  if (_devMode) ...[
                    const SizedBox(height: 12),
                    const BiometricVisualizer()
                        .animate()
                        .fadeIn(duration: 400.ms),
                  ],
                  if (_txHistory.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _txHistoryCard(),
                  ],
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Background ────────────────────────────────────────────────────────────

  Widget _background() => Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.3, -0.5),
            radius: 1.2,
            colors: [Color(0xFF1A1040), AppTheme.bg],
          ),
        ),
      );

  // ── Top Bar ───────────────────────────────────────────────────────────────

  Widget _topBar() => Row(
        children: [
          const Icon(Icons.shield_rounded, color: AppTheme.accent, size: 28),
          const SizedBox(width: 10),
          Text(
            'VigilUPI',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
          ),
          const Spacer(),
          _buildAppSelector(),
        ],
      ).animate().fadeIn(delay: 100.ms).slideY(begin: -0.2);

  // ── UPI App Selector ──────────────────────────────────────────────────────

  Widget _buildAppSelector() {
    if (_upiApps.isEmpty) {
      return const Text('No UPI apps',
          style:
              TextStyle(color: AppTheme.textSecondary, fontSize: 12));
    }
    return DropdownButton<UpiApp>(
      value: _selectedApp,
      hint: const Text('Select App',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      dropdownColor: AppTheme.surface,
      underline: const SizedBox(),
      items: _upiApps
          .map((app) => DropdownMenuItem(
                value: app,
                child: Text(app.name,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13)),
              ))
          .toList(),
      onChanged: (app) => setState(() => _selectedApp = app),
    );
  }

  // ── Soulprint Confidence Pill ─────────────────────────────────────────────

  Widget _soulprintPill() => Consumer<SoulprintEngine>(
        builder: (_, engine, __) {
          final pct = (engine.confidence * 100).toStringAsFixed(0);
          final color = engine.isAnomaly
              ? AppTheme.danger
              : engine.confidence > 0.9
                  ? AppTheme.success
                  : AppTheme.warning;

          return _GlassCard(
            child: Row(
              children: [
                _PulsingDot(color: color),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SOULPRINT™ CONFIDENCE',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.textSecondary,
                            letterSpacing: 1.2,
                          ),
                    ),
                    Text(
                      engine.isCalibrating
                          ? 'Calibrating… (${engine.calibrationProgress}/10)'
                          : engine.isAnomaly
                              ? 'ANOMALY DETECTED'
                              : '$pct% — Verified',
                      style:
                          Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: engine.isCalibrating
                                    ? AppTheme.warning
                                    : color,
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                  ],
                ),
                const Spacer(),
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: engine.isCalibrating
                        ? engine.calibrationProgress / 10.0
                        : engine.confidence,
                    strokeWidth: 4,
                    backgroundColor: AppTheme.glass,
                    valueColor: AlwaysStoppedAnimation(
                        engine.isCalibrating ? AppTheme.warning : color),
                  ),
                ),
              ],
            ),
          ).animate(key: ValueKey(engine.isAnomaly)).shake(
                duration: engine.isAnomaly ? 400.ms : 0.ms,
                hz: 4,
              );
        },
      );

  // ── Calibration Banner ────────────────────────────────────────────────────

  Widget _calibrationBanner() => Consumer<SoulprintEngine>(
        builder: (_, engine, __) {
          if (!engine.isCalibrating) return const SizedBox.shrink();
          return Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.fingerprint_rounded,
                    color: AppTheme.warning, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Learning your Soulprint™ — type in the fields below to calibrate (${engine.calibrationProgress}/10)',
                    style: const TextStyle(
                        color: AppTheme.warning, fontSize: 12),
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms);
        },
      );

  // ── Payment Form Card ─────────────────────────────────────────────────────

  Widget _paymentCard() => _GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SEND MONEY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    letterSpacing: 2,
                  ),
            ),
            const SizedBox(height: 16),
            _SoulprintTextField(
              controller: _vpaController,
              label: 'Recipient VPA',
              hint: 'merchant@upi',
              icon: Icons.alternate_email_rounded,
            ),
            const SizedBox(height: 12),
            _SoulprintTextField(
              controller: _amountController,
              label: 'Amount (₹)',
              hint: '0.00',
              icon: Icons.currency_rupee_rounded,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _SoulprintTextField(
              controller: _noteController,
              label: 'Note (optional)',
              hint: 'Payment for...',
              icon: Icons.notes_rounded,
            ),
          ],
        ),
      ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);

  // ── Authorize Button ──────────────────────────────────────────────────────

  Widget _authorizeButton() => Consumer<SoulprintEngine>(
        builder: (_, engine, __) {
          final blocked = engine.isAnomaly;
          final calibrating = engine.isCalibrating;
          return SizedBox(
            width: double.infinity,
            height: 60,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: blocked
                    ? const LinearGradient(
                        colors: [Color(0xFF8B0000), AppTheme.danger],
                      )
                    : calibrating
                        ? LinearGradient(colors: [
                            AppTheme.warning.withOpacity(0.6),
                            AppTheme.warning
                          ])
                        : const LinearGradient(
                            colors: [Color(0xFF4A3AFF), AppTheme.accent],
                          ),
                boxShadow: [
                  BoxShadow(
                    color: blocked
                        ? AppTheme.danger.withOpacity(0.4)
                        : AppTheme.accentGlow,
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _isLoading ? null : _onAuthorize,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            blocked
                                ? Icons.block_rounded
                                : calibrating
                                    ? Icons.hourglass_top_rounded
                                    : Icons.fingerprint_rounded,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            blocked
                                ? 'BLOCKED — Anomaly Detected'
                                : calibrating
                                    ? 'Calibrating Soulprint™…'
                                    : 'Authorize with Soulprint™',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .shimmer(
                  duration: 2400.ms,
                  color: Colors.white.withOpacity(0.08));
        },
      );

  // ── Dev Mode Toggle ───────────────────────────────────────────────────────

  Widget _devModeToggle() => Consumer<SoulprintEngine>(
        builder: (_, engine, __) => Consumer<RiskContextService>(
          builder: (_, riskService, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _toggleChip(
                    label: 'Dev Mode',
                    icon: Icons.developer_mode_rounded,
                    active: _devMode,
                    onTap: () => setState(() => _devMode = !_devMode),
                  ),
                  const SizedBox(width: 10),
                  _toggleChip(
                    label: 'Demo: Mule',
                    icon: Icons.warning_amber_rounded,
                    active: engine.isDemoMuleMode,
                    activeColor: AppTheme.danger,
                    onTap: () {
                      engine.toggleDemoMuleMode();
                      if (engine.isDemoMuleMode) _showAnomalyOverlay(engine);
                    },
                  ),
                ],
              ),
              // Active call warning banner
              if (riskService.isOnCall) ...
                [
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppTheme.danger.withOpacity(0.5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.call_rounded,
                            color: AppTheme.danger, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚠️ Active phone call detected — payments blocked during calls',
                            style: TextStyle(
                                color: AppTheme.danger, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
            ],
          ),
        ),
      );

  Widget _toggleChip({
    required String label,
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    Color activeColor = AppTheme.accent,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color:
                active ? activeColor.withOpacity(0.2) : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? activeColor : AppTheme.glass,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 14,
                  color: active ? activeColor : AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: active ? activeColor : AppTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );

  // ── Transaction History Card ──────────────────────────────────────────────

  Widget _txHistoryCard() => _GlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RECENT ACTIVITY',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary,
                    letterSpacing: 2,
                  ),
            ),
            const SizedBox(height: 12),
            ..._txHistory.map((tx) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(
                        tx.blocked
                            ? Icons.block_rounded
                            : Icons.check_circle_rounded,
                        color: tx.blocked
                            ? AppTheme.danger
                            : AppTheme.success,
                        size: 16,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          tx.vpa,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '₹${tx.amount}',
                        style: TextStyle(
                          color: tx.blocked
                              ? AppTheme.danger
                              : AppTheme.success,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ).animate().fadeIn(delay: 100.ms);
}

// ─── Anomaly Block Sheet ─────────────────────────────────────────────────────

class _AnomalyBlockSheet extends StatelessWidget {
  final SoulprintEngine engine;
  const _AnomalyBlockSheet({required this.engine});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.danger.withOpacity(0.12),
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(color: AppTheme.danger.withOpacity(0.4)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            const Icon(Icons.gpp_bad_rounded,
                    color: AppTheme.danger, size: 56)
                .animate()
                .scale(
                    begin: const Offset(0.5, 0.5),
                    duration: 400.ms,
                    curve: Curves.elasticOut),
            const SizedBox(height: 16),
            const Text(
              '⚠️ TRANSACTION HALTED',
              style: TextStyle(
                color: AppTheme.danger,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Behavioral Anomaly Detected',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 24),
            // XAI "Why?" section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.4),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: AppTheme.danger.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WHY WAS THIS BLOCKED?',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...engine.anomalyReasons.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.arrow_right_rounded,
                              color: AppTheme.danger, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              r,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Confidence score at time of block
            Text(
              'Confidence at block: ${(engine.confidence * 100).toStringAsFixed(1)}%  |  Threshold: 75%',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.danger),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Understood — Return to Safety',
                  style: TextStyle(color: AppTheme.danger),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Reusable Glassmorphic Card ───────────────────────────────────────────────

class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.glass,
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: child,
          ),
        ),
      );
}

// ─── TextField with Soulprint Behavioral Hooks ───────────────────────────────

class _SoulprintTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType keyboardType;

  const _SoulprintTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType = TextInputType.text,
  });

  @override
  State<_SoulprintTextField> createState() => _SoulprintTextFieldState();
}

class _SoulprintTextFieldState extends State<_SoulprintTextField> {
  Offset? _pointerDownPos;
  int? _pointerDownTime;

  @override
  Widget build(BuildContext context) {
    final engine = context.read<SoulprintEngine>();

    return Listener(
      // Capture touch pressure and size — raw pointer data before gesture system
      onPointerDown: (e) {
        _pointerDownPos = e.position;
        _pointerDownTime = DateTime.now().millisecondsSinceEpoch;
        engine.onPointerEvent(
          pressure: e.pressure,
          size: e.size,
          velocityPxPerMs: 0,
        );
      },
      onPointerUp: (e) {
        if (_pointerDownPos != null && _pointerDownTime != null) {
          final dt =
              DateTime.now().millisecondsSinceEpoch - _pointerDownTime!;
          final dist = (e.position - _pointerDownPos!).distance;
          // velocity in px/ms — captures swipe aggression
          final vel = dt > 0 ? dist / dt : 0.0;
          engine.onPointerEvent(
            pressure: e.pressure,
            size: e.size,
            velocityPxPerMs: vel,
          );
        }
      },
      child: TextField(
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        style: const TextStyle(color: AppTheme.textPrimary),
        // Keystroke dynamics: onChanged fires on each character
        onChanged: (val) {
          // Approximate key events via text change — real dwell/flight
          // requires a custom keyboard or accessibility service in production
          engine.onKeyDown('char');
          Future.delayed(const Duration(milliseconds: 80), () {
            engine.onKeyUp('char');
          });
        },
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: Icon(widget.icon,
              color: AppTheme.textSecondary, size: 20),
        ),
      ),
    );
  }
}

// ─── Pulsing Status Dot ───────────────────────────────────────────────────────

class _PulsingDot extends StatelessWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.6),
                blurRadius: 8,
                spreadRadius: 2)
          ],
        ),
      )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scaleXY(
              begin: 0.8,
              end: 1.2,
              duration: 900.ms,
              curve: Curves.easeInOut);
}
