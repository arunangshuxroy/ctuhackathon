// lib/services/face_liveness_service.dart
//
// LIVENESS GATE: For transactions above ₹10,000, the user must pass a
// quick blink-detection liveness check using the front camera + ML Kit.
// Fully on-device — no image ever leaves the phone.
//
// Why blink detection?
//   A static photo or screenshot cannot blink. This defeats photo spoofing
//   without requiring 3D depth sensors (which most mid-range phones lack).

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

// Threshold above which face liveness is required
const double kLivenessThreshold = 10000.0;

class FaceLivenessService {
  // Minimum eye-open probability to consider eyes open (ML Kit range: 0.0–1.0)
  static const double _blinkProbabilityThreshold = 0.85;

  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // enables eye open probability
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  /// Returns true if a live blink was detected within [timeoutSeconds].
  Future<bool> verifyLiveness(
    CameraController camera, {
    int timeoutSeconds = 8,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSeconds));
    bool eyesWereOpen = false;

    while (DateTime.now().isBefore(deadline)) {
      try {
        final image = await camera.takePicture();
        final inputImage = InputImage.fromFilePath(image.path);
        final faces = await _detector.processImage(inputImage);

        if (faces.isEmpty) continue;
        final face = faces.first;

        final leftOpen = face.leftEyeOpenProbability ?? 0;
        final rightOpen = face.rightEyeOpenProbability ?? 0;
        final bothOpen = leftOpen > _blinkProbabilityThreshold - 0.15 &&
            rightOpen > _blinkProbabilityThreshold - 0.15;
        final bothClosed = leftOpen < 0.3 && rightOpen < 0.3;

        if (bothOpen) eyesWereOpen = true;

        // A blink = eyes were open, then closed = confirmed liveness
        if (eyesWereOpen && bothClosed) {
          await _detector.close();
          return true;
        }
      } catch (_) {
        // Frame capture failure — retry
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }

    await _detector.close();
    return false;
  }

  void dispose() => _detector.close();
}

// ── Liveness Check Dialog ─────────────────────────────────────────────────────

/// Full-screen dialog that shows the front camera feed and prompts the user
/// to blink. Returns true if liveness confirmed, false if failed/cancelled.
class LivenessCheckDialog extends StatefulWidget {
  const LivenessCheckDialog({super.key});

  static Future<bool> show(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const LivenessCheckDialog(),
        ) ??
        false;
  }

  @override
  State<LivenessCheckDialog> createState() => _LivenessCheckDialogState();
}

class _LivenessCheckDialogState extends State<LivenessCheckDialog> {
  CameraController? _camera;
  final _service = FaceLivenessService();
  String _status = 'Initializing camera…';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    _camera = CameraController(front, ResolutionPreset.medium,
        enableAudio: false);
    await _camera!.initialize();
    if (mounted) {
      setState(() => _status = 'Please blink naturally to confirm identity');
      _startCheck();
    }
  }

  Future<void> _startCheck() async {
    if (_checking || _camera == null) return;
    setState(() => _checking = true);

    final passed = await _service.verifyLiveness(_camera!);
    if (mounted) Navigator.of(context).pop(passed);
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.face_unlock_outlined,
                color: Color(0xFF7C6FFF), size: 36),
            const SizedBox(height: 12),
            const Text(
              'HIGH-VALUE TRANSACTION',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _status,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            if (_camera != null && _camera!.value.isInitialized)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 220,
                  child: CameraPreview(_camera!),
                ),
              )
            else
              const SizedBox(
                height: 220,
                child: Center(
                    child: CircularProgressIndicator(
                        color: Color(0xFF7C6FFF))),
              ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }
}
