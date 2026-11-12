import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/localization/app_strings.dart';
import '../theme/app_theme.dart';

class PulseIndicator extends ConsumerStatefulWidget {
  final int? hr;
  final bool isConnected;

  const PulseIndicator({
    super.key,
    required this.hr,
    required this.isConnected,
  });

  @override
  ConsumerState<PulseIndicator> createState() => _PulseIndicatorState();
}

class _PulseIndicatorState extends ConsumerState<PulseIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _scaleAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isConnected) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PulseIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isConnected != oldWidget.isConnected) {
      if (widget.isConnected) {
        if (!_controller.isAnimating) {
          _controller.repeat(reverse: true);
        }
      } else {
        _controller.stop();
      }
    }

    if (widget.hr != null && widget.hr! > 0 && widget.hr != oldWidget.hr) {
      // Adjust pulse animation speed according to real-time BPM only when HR changes
      final msPerBeat = (60000 / widget.hr!).clamp(400, 1500).round();
      final newDuration = Duration(milliseconds: msPerBeat ~/ 2);
      if (_controller.duration != newDuration) {
        _controller.duration = newDuration;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);

    if (!widget.isConnected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bluetooth_disabled, color: Colors.redAccent, size: 14),
            const SizedBox(width: 6),
            Text(
              strings.disconnected,
              style: const TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w600),
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
          RepaintBoundary(
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: const Icon(
                Icons.favorite,
                color: AppTheme.polarRed,
                size: 15,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.hr != null && widget.hr! > 0
                ? '${widget.hr} ${strings.bpm}'
                : strings.connected,
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
