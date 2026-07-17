import 'dart:io';

import 'package:camera/camera.dart';
import 'package:card_scanner/pages/result_page.dart';
import 'package:card_scanner/utils/string_utils.dart';
import 'package:card_scanner/widgets/credit_card_widget.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:card_scanner/utils/input_image_from_camera_image.dart';
import 'package:vibration/vibration.dart';

class ScannerPage extends StatefulWidget {
  final void Function(String cardNumber, String expiryDate)? onCardScanned;

  const ScannerPage({super.key, this.onCardScanned});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  CameraController? _controller;
  final TextRecognizer _textRecognizer = TextRecognizer();
  bool _isScanBusy = false;
  bool _isCardFound = false;
  String _cardNumber = "";
  String _expiryDate = "";
  bool _isCameraInitialized = false;

  Future<void> _startScanning() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      await _initializeCamera();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Camera permission is required to scan cards.'),
          ),
        );
      }
    }
  }

  Future<void> _stopScanning() async {
    await _controller?.stopImageStream();
    await _controller?.dispose();
    setState(() {
      _controller = null;
      _isCameraInitialized = false;
      _isCardFound = false;
      _cardNumber = "";
      _expiryDate = "";
    });
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    _controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );

    try {
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isCameraInitialized = true;
        });
        _controller!.startImageStream(_processImage);
      }
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  Future<void> _processImage(CameraImage image) async {
    if (_isScanBusy || _isCardFound || _controller == null) return;
    _isScanBusy = true;

    try {
      final inputImage = inputImageFromCameraImage(image, _controller!);
      if (inputImage == null) return;

      final recognizedText = await _textRecognizer.processImage(inputImage);

      String? cNum;
      String? cExp;

      final cardRegex = RegExp(r'\b(?:\d[ -]*?){13,16}\b');
      final dateRegex = RegExp(r'\b(0[1-9]|1[0-2])[\/\-](\d{2}|\d{4})\b');

      for (TextBlock block in recognizedText.blocks) {
        for (TextLine line in block.lines) {
          final text = line.text;

          if (cNum == null) {
            final cardMatch = cardRegex.firstMatch(text);
            if (cardMatch != null) {
              String potentialNum = cardMatch
                  .group(0)!
                  .replaceAll(RegExp(r'[^0-9]'), '');
              if (potentialNum.length >= 13 && potentialNum.length <= 16) {
                cNum = potentialNum;
              }
            }
          }

          if (cExp == null) {
            final dateMatch = dateRegex.firstMatch(text);
            if (dateMatch != null) {
              cExp = dateMatch.group(0);
            }
          }
        }
      }

      if (cNum != null && cExp != null) {
        setState(() {
          _isCardFound = true;
        });
        // await _stopScanning();

        _cardNumber = StringUtils.formatCardNumber(cNum);
        _expiryDate = StringUtils.formatExpiryDate(cExp);

        if (await Vibration.hasVibrator()) {
          Vibration.vibrate(duration: 400);
        }
        Future.delayed(const Duration(milliseconds: 800), () async {
          if (mounted && _cardNumber.isNotEmpty && _expiryDate.isNotEmpty) {
            if (widget.onCardScanned != null) {
              widget.onCardScanned!(_cardNumber, _expiryDate);
              Navigator.pop(context, {'cardNumber': _cardNumber, 'expiryDate': _expiryDate});
            } else {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      ResultPage(
                    cardNumber: _cardNumber,
                    expiryDate: _expiryDate,
                  ),
                  transitionDuration: const Duration(milliseconds: 1200),
                ),
              );
            }
            _isScanBusy = false;
            await _stopScanning();
          }
        });
      }
    } catch (e) {
      debugPrint("Error processing image: $e");
    } finally {
      if (!_isCardFound) {
        _isScanBusy = false;
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool showCamera = _isCameraInitialized && _controller != null;

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              "Scan your card",
              style: GoogleFonts.montserrat(
                fontSize: 25,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 15),

            if (_isCardFound)
              Hero(
                tag: 'scanner',
                child: Material(
                  type: MaterialType.transparency,
                  child: CreditCardWidget(
                    cardNumber: _cardNumber,
                    expiryDate: _expiryDate,
                  ),
                ),
              )
            else
              Container(
                width: MediaQuery.of(context).size.width,
                height: 220,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                  border: showCamera
                      ? Border.all(color: Colors.black, width: 1)
                      : null,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: showCamera
                      ? FittedBox(
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: _controller!.value.previewSize!.height,
                            height: _controller!.value.previewSize!.width,
                            child: CameraPreview(_controller!),
                          ),
                        )
                      : const SizedBox(),
                ),
              ),
          ],
        ),
      ),

      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        child: ElevatedButton(
          onPressed: showCamera ? _stopScanning : _startScanning,
          style: showCamera
              ? ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          child: Text(showCamera ? "Stop Scanning" : "Start Scanning"),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
