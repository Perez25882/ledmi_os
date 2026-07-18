import 'package:card_scanner/pages/scanner_page.dart';
import 'package:flutter/material.dart';

class CardScannerPage extends StatelessWidget {
  const CardScannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScannerPage(
      onCardScanned: (_, __) {},
    );
  }
}
