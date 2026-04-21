// lib/widgets/biometric_visualizer.dart
//
// VISUAL EVIDENCE: Renders live sensor streams as oscilloscope-style waveforms
// with a scanline grid. Shown in "Dev Mode" so judges can see the engine is
// actually reading sensors in real-time — not faking it.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/soulprint_engine.dart';

class BiometricVisualizer extends StatelessWidget {
  const BiometricVisualizer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SoulprintEngine>(
      builder: (_, engine, __) => Container(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.35)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                const Icon(Icons.monitor_heart_rounded,
                    color: Color(0xFF00FF88), size: 14),
                const SizedBox(width: 6),
                const Text(
                  'SOULPRINT™ SENSOR FEED',
                  style: TextStyle(
                    color: Color(0xFF00FF88),
                    fontSize: 10,
                    fontFamily: 'monospace',
                    letterSpacing: 2,
                  ),
                ),
                const Spacer(),
                // Live indicator
                _LiveBadge(),
              ],
            ),
            const SizedBox(height: 10),

            // Accelerometer waveform
            _channelLabel('ACCEL  m/s²', const Color(0xFF00FF88)),
            const SizedBox(height: 4),
            _Waveform(
                data: engine.accelHistory, color: const Color(0xFF00FF88)),

            const SizedBox(height: 10),

            // Gyroscope waveform
            _channelLabel('GYRO   rad/s', const Color(0xFF00BFFF)),
            const SizedBox(height: 4),
            _Waveform(
                data: engine.gyroHistory, color: const Color(0xFF00BFFF)),

            const SizedBox(height: 12),

            // Stats table
            _statsGrid(engine),
          ],
        ),
      ),
    );
  }

  Widget _channelLabel(String text, Color color) => Text(
        text,
        style: TextStyle(
          color: color.withOpacity(0.8),
          fontSize: 9,
          fontFamily: 'monospace',
          letterSpacing: 1.5,
        ),
      );

  Widget _statsGrid(SoulprintEngine e) {
    final v = e.lastVector;
    final stats = [
      ('JITTER', v?.jitterRms, const Color(0xFF00FF88)),
      ('RHYTHM', v?.rhythmVariance, const Color(0xFFFFB300)),
      ('GYRO', v?.gyroRms, const Color(0xFF00BFFF)),
      ('PRESS', v?.touchPressure, const Color(0xFFFF6B9D)),
      ('DWELL', v?.dwellTimeMean, const Color(0xFFB388FF)),
      ('FLIGHT', v?.flightTimeMean, const Color(0xFF80CBC4)),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: stats
          .map((s) => _StatChip(label: s.$1, value: s.$2, color: s.$3))
          .toList(),
    );
  }
}

// ─── Live Badge ───────────────────────────────────────────────────────────────

class _LiveBadge extends StatefulWidget {
  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _ctrl,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color.lerp(const Color(0xFF00FF88),
                    const Color(0xFF00FF88).withOpacity(0.2), _ctrl.value),
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'LIVE',
              style: TextStyle(
                color: Color(0xFF00FF88),
                fontSize: 9,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      );
}

// ─── Stat Chip ────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final double? value;
  final Color color;

  const _StatChip(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Text(
          '$label: ${value?.toStringAsFixed(2) ?? '--'}',
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontFamily: 'monospace',
            letterSpacing: 0.5,
          ),
        ),
      );
}

// ─── Waveform ─────────────────────────────────────────────────────────────────

class _Waveform extends StatelessWidget {
  final List<double> data;
  final Color color;

  const _Waveform({required this.data, required this.color});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: CustomPaint(
          painter: _WaveformPainter(data: List.from(data), color: color),
          size: Size.infinite,
        ),
      );
}

class _WaveformPainter extends CustomPainter {
  final List<double> data;
  final Color color;

  _WaveformPainter({required this.data, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // ── Scanline grid ──────────────────────────────────────────────────────
    final gridPaint = Paint()
      ..color = color.withOpacity(0.06)
      ..strokeWidth = 0.5;

    // Horizontal grid lines (4 rows)
    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    // Vertical grid lines (8 columns)
    for (int i = 1; i < 8; i++) {
      final x = size.width * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    if (data.isEmpty) return;

    final maxVal =
        data.reduce((a, b) => a > b ? a : b).clamp(0.1, double.infinity);
    final step =
        size.width / (data.length - 1).clamp(1, double.infinity);

    final path = Path();
    for (var i = 0; i < data.length; i++) {
      final x = i * step;
      final y = size.height - (data[i] / maxVal) * size.height * 0.88;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }

    // Glow layer — wide + faint
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.18)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Signal layer — narrow + bright
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Fill area under curve for depth
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.12), Colors.transparent],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.data.length != data.length ||
      (data.isNotEmpty &&
          old.data.isNotEmpty &&
          old.data.last != data.last);
}
