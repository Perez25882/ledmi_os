import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

InputImage? inputImageFromCameraImage(
  CameraImage image,
  CameraController controller,
) {
  final camera = controller.description;
  final sensorOrientation = camera.sensorOrientation;

  InputImageRotation? rotation;
  if (Platform.isIOS) {
    rotation = InputImageRotation.values.firstWhere(
      (e) => e.rawValue == sensorOrientation,
      orElse: () => InputImageRotation.rotation0deg,
    );
  } else if (Platform.isAndroid) {
    var rotationCompensation =
        _orientations[controller.value.deviceOrientation];
    if (rotationCompensation == null) return null;
    if (camera.lensDirection == CameraLensDirection.front) {
      // front-facing
      rotationCompensation = (sensorOrientation + rotationCompensation) % 360;
    } else {
      // back-facing
      rotationCompensation =
          (sensorOrientation - rotationCompensation + 360) % 360;
    }
    rotation = InputImageRotation.values.firstWhere(
      (e) => e.rawValue == rotationCompensation,
      orElse: () => InputImageRotation.rotation0deg,
    );
  }

  if (rotation == null) return null;

  // Handle Image Format
  final format = InputImageFormat.values.firstWhere(
    (e) => e.rawValue == image.format.raw,
    orElse: () =>
        InputImageFormat.nv21, // Default fallback, might need better handling
  );

  if (image.planes.isEmpty) return null;
  final plane = image.planes.first;

  return InputImage.fromBytes(
    bytes: Uint8List.fromList(
      image.planes.fold(
        <int>[],
        (previousValue, element) => previousValue..addAll(element.bytes),
      ),
    ),
    metadata: InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: rotation,
      format: format,
      bytesPerRow: plane.bytesPerRow,
    ),
  );
}

const _orientations = {
  DeviceOrientation.portraitUp: 0,
  DeviceOrientation.landscapeLeft: 90,
  DeviceOrientation.portraitDown: 180,
  DeviceOrientation.landscapeRight: 270,
};
