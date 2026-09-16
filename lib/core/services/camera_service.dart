import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _availableCameras = [];
  bool _isStreamRunning = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _controller != null && _controller!.value.isInitialized;
  bool get isStreamRunning => _isStreamRunning;

  Future<void> initCamera() async {
    if (_availableCameras.isEmpty) {
      try {
        _availableCameras = await availableCameras();
      } catch (e) {
        debugPrint("Camera listing failed: $e");
      }
    }

    if (_availableCameras.isEmpty) {
      throw Exception("No cameras found");
    }

    final backCamera = _availableCameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => _availableCameras.first,
    );

    _controller = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _controller!.initialize();

    try {
      await _controller!.setFocusMode(FocusMode.auto);
    } catch (e) {
      debugPrint("Autofocus not supported: $e");
    }
  }

  Future<Uint8List?> captureImage() async {
    if (!isInitialized) return null;

    await stopStream();

    try {
      await _controller!.setFocusMode(FocusMode.auto);
      await Future.delayed(const Duration(milliseconds: 150));
    } catch (_) {}

    final XFile photo = await _controller!.takePicture();
    final Uint8List bytes = await photo.readAsBytes();

    try {
      await File(photo.path).delete();
    } catch (_) {}

    return bytes;
  }

  Future<void> startStream(Function(CameraImage) onImage) async {
    if (!isInitialized || _isStreamRunning) return;

    try {
      _isStreamRunning = true;
      await _controller!.startImageStream((CameraImage image) {
        onImage(image);
      });
    } catch (e) {
      _isStreamRunning = false;
      debugPrint("Failed to start stream: $e");
      rethrow;
    }
  }

  Future<void> stopStream() async {
    if (_controller != null && _isStreamRunning) {
      try {
        await _controller!.stopImageStream();
      } catch (_) {}
      _isStreamRunning = false;
    }
  }

  Future<void> disposeCamera() async {
    await stopStream();
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
  }
}
