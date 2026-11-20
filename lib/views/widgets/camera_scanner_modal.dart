import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/constants/app_colors.dart';

/// Modalité de scan vidéo caméra (Mobile / PWA Web) avec overlay de centrage médical
class CameraScannerModal extends StatefulWidget {
  const CameraScannerModal({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CameraScannerModal(),
    );
  }

  @override
  State<CameraScannerModal> createState() => _CameraScannerModalState();
}

class _CameraScannerModalState extends State<CameraScannerModal> {
  late final MobileScannerController _controller;
  bool _hasDetected = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasDetected) return;
    final barcode = capture.barcodes.firstOrNull;
    final rawValue = barcode?.rawValue;

    if (rawValue != null && rawValue.trim().isNotEmpty) {
      _hasDetected = true;
      Navigator.of(context).pop(rawValue.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanWindowSize = size.width * 0.75;

    return Container(
      height: size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.slateDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Poignée et en-tête
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 48,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 24),
                    SizedBox(width: 10),
                    Text(
                      'Scanner l\'échantillon médical',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Text(
              'Pointez l\'appareil vers le DataMatrix GS1 ou le code EAN-13 sur la boîte.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),

          // Zone caméra avec cadre de ciblage
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                ),

                // Cadre de visée
                Container(
                  width: scanWindowSize,
                  height: scanWindowSize,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.primaryLight, width: 2.5),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: AppColors.primaryAccent.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),

                // Bouton Torche / Flash
                Positioned(
                  bottom: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
                          onPressed: () => _controller.toggleTorch(),
                          tooltip: 'Activer / désactiver la lumière',
                        ),
                        IconButton(
                          icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white),
                          onPressed: () => _controller.switchCamera(),
                          tooltip: 'Changer de caméra',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
