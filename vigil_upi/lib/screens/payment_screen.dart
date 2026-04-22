// lib/screens/payment_screen.dart
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('⏳ Soulprint calibrating — keep typing to complete.'),
        backgroundColor: AppTheme.warningContainer,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Please fill all fields and select a UPI app.'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    final amountVal = double.tryParse(_amountController.text.trim()) ?? 0.0;
    final contextRisk = await riskService.evaluate(
        amount: amountVal, vpa: _vpaController.text.trim());
    if (contextRisk.hasSoftWarning && mounted) {
      final proceed = await _showContextRiskWarning(contextRisk);
      if (!proceed) return;
    }

    setState(() => _isLoading = true);

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
      backgroundColor:
          isSuccess ? AppTheme.successContainer : AppTheme.dangerContainer,
      content: Text(msg,
          style: TextStyle(
              color: isSuccess
                  ? AppTheme.onSuccessContainer
                  : AppTheme.onDangerContainer)),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  void _showBlockedSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppTheme.dangerContainer,
      content: Text(msg, style: const TextStyle(color: AppTheme.onDangerContainer)),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 4),
    ));
  }

  // ── Context Risk Warning Dialog ───────────────────────────────────────────

  Future<bool> _showContextRiskWarning(ContextRisk risk) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.warning_amber_rounded,
                color: AppTheme.warning, size: 28),
            title: const Text('Risk Warning'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Elevated risk signals detected:',
                    style: Theme.of(context).textTheme.bodySmall),
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
                                style: Theme.of(context).textTheme.bodySmall),
                          ),
                        ],
                      ),
                    )),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.warningContainer,
                    foregroundColor: AppTheme.onWarningContainer),
                child: const Text('Proceed Anyway'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // ── Anomaly Block Overlay ─────────────────────────────────────────────────

  void _showAnomalyOverlay(SoulprintEngine engine) {
    HapticFeedback.heavyImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _AnomalyBlockSheet(engine: engine),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.3, -0.5),
            radius: 1.2,
            colors: [cs.primaryContainer.withOpacity(0.15), cs.surface],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _topBar(),
                const SizedBox(height: 20),
                _soulprintCard(),
                const SizedBox(height: 12),
                _calibrationBanner(),
                const SizedBox(height: 16),
                _paymentCard(),
                const SizedBox(height: 16),
                _authorizeButton(),
                const SizedBox(height: 20),
                _devModeSection(),
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
                Center(
                  child: Text(
                    'CTU Hackathon!',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.18),
                          letterSpacing: 1.5,
                        ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Top Bar ───────────────────────────────────────────────────────────────

  Widget _topBar() => Row(
        children: [
          _AppIcon(size: 36),
          const SizedBox(width: 10),
          Text('VigilUPI',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
          const Spacer(),
          _buildAppSelector(),
        ],
      ).animate().fadeIn(delay: 100.ms).slideY(begin: -0.2);

  // ── UPI App Selector ──────────────────────────────────────────────────────

  Widget _buildAppSelector() {
    if (_upiApps.isEmpty) {
      return Text('No UPI apps',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return DropdownMenu<UpiApp>(
      initialSelection: _selectedApp,
      hintText: 'Select App',
      width: 140,
      textStyle: Theme.of(context).textTheme.bodySmall,
      inputDecorationTheme: const InputDecorationTheme(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(),
      ),
      dropdownMenuEntries: _upiApps
          .map((app) => DropdownMenuEntry(value: app, label: app.name))
          .toList(),
      onSelected: (app) => setState(() => _selectedApp = app),
    );
  }

  // ── Soulprint Confidence Card ─────────────────────────────────────────────

  Widget _soulprintCard() => Consumer<SoulprintEngine>(
        builder: (_, engine, __) {
          final pct = (engine.confidence * 100).toStringAsFixed(0);
          final color = engine.isAnomaly
              ? AppTheme.danger
              : engine.confidence > 0.9
                  ? AppTheme.success
                  : AppTheme.warning;

          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SOULPRINT™ CONFIDENCE',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(letterSpacing: 1.2)),
                        const SizedBox(height: 2),
                        Text(
                          engine.isCalibrating
                              ? 'Calibrating… (${engine.calibrationProgress}/10)'
                              : engine.isAnomaly
                                  ? 'ANOMALY DETECTED'
                                  : '$pct% — Verified',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color: color, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(
                      value: engine.isCalibrating
                          ? engine.calibrationProgress / 10.0
                          : engine.confidence,
                      strokeWidth: 4,
                      color: color,
                      backgroundColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
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
          return Card(
            color: AppTheme.warningContainer,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.fingerprint_rounded,
                      color: AppTheme.onWarningContainer, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Learning your Soulprint™ — type in the fields below to calibrate (${engine.calibrationProgress}/10)',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.onWarningContainer),
                    ),
                  ),
                ],
              ),
            ),
          ).animate().fadeIn(duration: 300.ms);
        },
      );

  // ── Payment Form Card ─────────────────────────────────────────────────────

  Widget _paymentCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('SEND MONEY',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(letterSpacing: 2)),
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
        ),
      ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.1);

  // ── Authorize Button ──────────────────────────────────────────────────────

  Widget _authorizeButton() => Consumer<SoulprintEngine>(
        builder: (_, engine, __) {
          final blocked = engine.isAnomaly;
          final calibrating = engine.isCalibrating;

          final icon = blocked
              ? Icons.block_rounded
              : calibrating
                  ? Icons.hourglass_top_rounded
                  : Icons.fingerprint_rounded;

          final label = blocked
              ? 'BLOCKED — Anomaly Detected'
              : calibrating
                  ? 'Calibrating Soulprint™…'
                  : 'Authorize with Soulprint™';

          return SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              onPressed: _isLoading ? null : _onAuthorize,
              style: FilledButton.styleFrom(
                backgroundColor: blocked
                    ? AppTheme.dangerContainer
                    : calibrating
                        ? AppTheme.warningContainer
                        : null,
                foregroundColor: blocked
                    ? AppTheme.onDangerContainer
                    : calibrating
                        ? AppTheme.onWarningContainer
                        : null,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Icon(icon),
              label: Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .shimmer(
                    duration: 2400.ms,
                    color: Colors.white.withOpacity(0.08)),
          );
        },
      );

  // ── Dev Mode Section ──────────────────────────────────────────────────────

  Widget _devModeSection() => Consumer<SoulprintEngine>(
        builder: (_, engine, __) => Consumer<RiskContextService>(
          builder: (_, riskService, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  FilterChip(
                    label: const Text('Dev Mode'),
                    avatar: const Icon(Icons.developer_mode_rounded, size: 16),
                    selected: _devMode,
                    onSelected: (_) =>
                        setState(() => _devMode = !_devMode),
                  ),
                  FilterChip(
                    label: const Text('Demo: Mule'),
                    avatar: const Icon(Icons.warning_amber_rounded, size: 16),
                    selected: engine.isDemoMuleMode,
                    selectedColor: AppTheme.dangerContainer,
                    checkmarkColor: AppTheme.onDangerContainer,
                    labelStyle: engine.isDemoMuleMode
                        ? const TextStyle(color: AppTheme.onDangerContainer)
                        : null,
                    onSelected: (_) {
                      engine.toggleDemoMuleMode();
                      if (engine.isDemoMuleMode) _showAnomalyOverlay(engine);
                    },
                  ),
                ],
              ),
              if (riskService.isOnCall) ...[
                const SizedBox(height: 10),
                Card(
                  color: AppTheme.dangerContainer,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.call_rounded,
                            color: AppTheme.onDangerContainer, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '⚠️ Active phone call detected — payments blocked during calls',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.onDangerContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  // ── Transaction History Card ──────────────────────────────────────────────

  Widget _txHistoryCard() => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('RECENT ACTIVITY',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(letterSpacing: 2)),
              const SizedBox(height: 8),
              ..._txHistory.map((tx) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      tx.blocked
                          ? Icons.block_rounded
                          : Icons.check_circle_rounded,
                      color: tx.blocked ? AppTheme.danger : AppTheme.success,
                      size: 20,
                    ),
                    title: Text(tx.vpa,
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis),
                    trailing: Text(
                      '₹${tx.amount}',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: tx.blocked ? AppTheme.danger : AppTheme.success,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  )),
            ],
          ),
        ),
      ).animate().fadeIn(delay: 100.ms);
}

// ─── Anomaly Block Sheet ─────────────────────────────────────────────────────

class _AnomalyBlockSheet extends StatelessWidget {
  final SoulprintEngine engine;
  const _AnomalyBlockSheet({required this.engine});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // M3 drag handle
          const SizedBox(height: 12),
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: cs.onSurfaceVariant.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Icon(Icons.gpp_bad_rounded, color: AppTheme.danger, size: 56)
              .animate()
              .scale(
                  begin: const Offset(0.5, 0.5),
                  duration: 400.ms,
                  curve: Curves.elasticOut),
          const SizedBox(height: 12),
          Text('TRANSACTION HALTED',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.danger, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Behavioral Anomaly Detected',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          // XAI "Why?" card
          Card(
            color: AppTheme.dangerContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('WHY WAS THIS BLOCKED?',
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(
                              color: AppTheme.onDangerContainer, letterSpacing: 2)),
                  const SizedBox(height: 10),
                  ...engine.anomalyReasons.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.arrow_right_rounded,
                              color: AppTheme.onDangerContainer, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(r,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: AppTheme.onDangerContainer)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Confidence at block: ${(engine.confidence * 100).toStringAsFixed(1)}%  |  Threshold: 75%',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.danger),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Understood — Return to Safety'),
            ),
          ),
        ],
      ),
    );
  }
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
      onPointerDown: (e) {
        _pointerDownPos = e.position;
        _pointerDownTime = DateTime.now().millisecondsSinceEpoch;
        engine.onPointerEvent(
            pressure: e.pressure, size: e.size, velocityPxPerMs: 0);
      },
      onPointerUp: (e) {
        if (_pointerDownPos != null && _pointerDownTime != null) {
          final dt =
              DateTime.now().millisecondsSinceEpoch - _pointerDownTime!;
          final dist = (e.position - _pointerDownPos!).distance;
          final vel = dt > 0 ? dist / dt : 0.0;
          engine.onPointerEvent(
              pressure: e.pressure, size: e.size, velocityPxPerMs: vel);
        }
      },
      child: TextField(
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        onChanged: (val) {
          engine.onKeyDown('char');
          Future.delayed(
              const Duration(milliseconds: 80), () => engine.onKeyUp('char'));
        },
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          prefixIcon: Icon(widget.icon, size: 20),
        ),
      ),
    );
  }
}

// ─── App Icon (matches launcher icon design) ────────────────────────────────

class _AppIcon extends StatelessWidget {
  final double size;
  const _AppIcon({this.size = 36});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final bg    = Theme.of(context).colorScheme.primaryContainer;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.25), // squircle-ish
      ),
      child: CustomPaint(
        painter: _ShieldFingerprintPainter(fg: bg),
      ),
    );
  }
}

class _ShieldFingerprintPainter extends CustomPainter {
  final Color fg;
  const _ShieldFingerprintPainter({required this.fg});

  @override
  void paint(Canvas canvas, Size size) {
    // saveLayer so BlendMode.clear punches through only within this layer
    canvas.saveLayer(Offset.zero & size, Paint());

    final cx = size.width / 2;
    final cy = size.height / 2 - size.height * 0.03;
    final w  = size.width  * 0.62;
    final h  = size.height * 0.72;

    // Shield path
    final shield = Path()
      ..moveTo(cx - w / 2, cy - h / 2 + h * 0.15)
      ..lineTo(cx - w / 2, cy)
      ..lineTo(cx,         cy + h / 2)
      ..lineTo(cx + w / 2, cy)
      ..lineTo(cx + w / 2, cy - h / 2 + h * 0.15)
      ..lineTo(cx + w / 4, cy - h / 2)
      ..lineTo(cx,         cy - h / 2 - h * 0.05)
      ..lineTo(cx - w / 4, cy - h / 2)
      ..close();

    canvas.drawPath(shield, Paint()..color = fg);

    // Fingerprint arcs — drawn in primary color to "cut through" the white shield
    final arcCy = cy + size.height * 0.04;
    final arcPaint = Paint()
      ..color = fg.withOpacity(0)   // transparent = reveal bg color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Use a saveLayer to punch arcs through the shield
    final cutPaint = Paint()
      ..color = const Color(0xFF6750A4) // primary — will be overridden at runtime
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // We draw arcs in the background color to simulate cutouts
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 4; i++) {
      final r = size.width * (0.10 + i * 0.07);
      bgPaint
        ..color = fg.withOpacity(0.0)  // transparent reveals container bg
        ..strokeWidth = size.width * 0.028;
      // Use BlendMode.clear to punch through
      final arcPunch = Paint()
        ..color = const Color(0x006750A4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.030
        ..strokeCap = StrokeCap.round
        ..blendMode = BlendMode.clear;
      final bbox = Rect.fromCircle(center: Offset(cx, arcCy), radius: r);
      canvas.drawArc(bbox, 3.49, 2.44, false, arcPunch);
    }

    // Center dot — punch through
    canvas.drawCircle(
      Offset(cx, arcCy),
      size.width * 0.055,
      Paint()
        ..color = const Color(0x00000000)
        ..blendMode = BlendMode.clear,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShieldFingerprintPainter old) => old.fg != fg;
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
                color: color.withOpacity(0.6), blurRadius: 8, spreadRadius: 2)
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
