import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CameraPreviewWidget extends StatelessWidget {
  final CameraController cameraController;
  final bool isListeningSpeech;
  final bool isProcessingAi;
  final bool isTorchOn;

  const CameraPreviewWidget({
    super.key,
    required this.cameraController,
    required this.isListeningSpeech,
    required this.isProcessingAi,
    required this.isTorchOn,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: cameraController.value.aspectRatio,
      child: Stack(
        children: [
          Positioned.fill(
            child: CameraPreview(cameraController),
          ),
          if (isListeningSpeech)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.mic,
                        color: Colors.amber,
                        size: 48,
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Listening... take your time",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else if (isProcessingAi)
            Positioned.fill(
              child: Container(
                color: Colors.black45,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          if (isTorchOn)
            Positioned(
              top: 16,
              left: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.flash_on,
                      color: Colors.black,
                      size: 14,
                    ),
                    SizedBox(width: 4),
                    Text(
                      "TORCH",
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
