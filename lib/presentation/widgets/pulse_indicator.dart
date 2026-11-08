import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PulseIndicator extends StatefulWidget {
  final int? hr;
  final bool isConnected;

  const PulseIndicator({
    super.key,
    required this.hr,
    required this.isConnected,
  });

  @override
  State<PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends State<PulseIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant PulseIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hr != null && widget.hr! > 0) {
      // Adjust pulse animation speed according to real-time BPM
      final msPerBeat = (60000 / widget.hr!).clamp(400, 1500).round();
      _controller.duration = Duration(milliseconds: msPerBeat ~/ 2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isConnected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bluetooth_disabled, color: Colors.redAccent, size: 14),
            SizedBox(width: 6),
            Text(
              'Disconnected',
              style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.polarCyan.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.polarCyan.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ScaleTransition(
            scale: _scaleAnimation,
            child: const Icon(
              Icons.favorite,
              color: AppTheme.polarRed,
              size: 15,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.hr != null && widget.hr! > 0 ? '${widget.hr} BPM' : 'Connected',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
