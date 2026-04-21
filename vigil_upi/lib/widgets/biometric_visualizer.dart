// lib/widgets/biometric_visualizer.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/soulprint_engine.dart';

class BiometricVisualizer extends StatelessWidget {
  const BiometricVisualizer({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SoulprintEngine>(
      builder: (_, engine, __) => Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: Icon(Icons.monitor_heart_rounded,
                  color: Theme.of(context).colorScheme.primary),
              title: Text('SOULPRINT™ SENSOR FEED',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(letterSpacing: 1.5)),
              trailing: _LiveBadge(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('ACCEL  m/s²',
                  style: Theme.of(context).textTheme.labelSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _Waveform(
                  data: engine.accelHistory,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text('GYRO   rad/s',
                  style: Theme.of(context).textTheme.labelSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _Waveform(
                  data: engine.gyroHistory,
                  color: Theme.of(context).colorScheme.tertiary),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _statsGrid(context, engine),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsGrid(BuildContext context, SoulprintEngine e) {
    final cs = Theme.of(context).colorScheme;
    final v = e.lastVector;
    final stats = [
      ('JITTER', v?.jitterRms),
      ('RHYTHM', v?.rhythmVariance),
      ('GYRO', v?.gyroRms),
      ('PRESS', v?.touchPressure),
      ('DWELL', v?.dwellTimeMean),
      ('FLIGHT', v?.flightTimeMean),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: stats
          .map((s) => Chip(
                label: Text(
                  '${s.$1}: ${s.$2?.toStringAsFixed(2) ?? '--'}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                backgroundColor: cs.surfaceContainerHighest,
                side: BorderSide(color: cs.outlineVariant),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                visualDensity: VisualDensity.compact,
              ))
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
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => Chip(
        avatar: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Color.lerp(color, color.withOpacity(0.2), _ctrl.value),
          ),
        ),
        label: Text('LIVE',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: color)),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        side: BorderSide(color: color.withOpacity(0.4)),
        backgroundColor:
            Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
    );
  }
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
    final gridPaint = Paint()
      ..color = color.withOpacity(0.06)
      ..strokeWidth = 0.5;

    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
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

    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.18)
        ..strokeWidth = 5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

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
      (data.isNotEmpty && old.data.isNotEmpty && old.data.last != data.last);
}
