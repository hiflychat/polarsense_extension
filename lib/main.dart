import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/background/background_service.dart';
import 'core/localization/app_strings.dart';
import 'core/notifications/notification_service.dart';
import 'presentation/device/device_screen.dart';
import 'presentation/home/home_screen.dart';
import 'presentation/settings/settings_screen.dart';
import 'presentation/sleep/sleep_screen.dart';
import 'presentation/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Custom ErrorWidget to prevent blank white screens on runtime errors
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF12121A),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.info_outline, color: Colors.orangeAccent, size: 48),
              const SizedBox(height: 16),
              const Text(
                'Notice / 提示',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                details.exceptionAsString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  };

  // Catch any unhandled framework errors
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };

  // Catch any unhandled platform asynchronous errors
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PlatformDispatcherError] $error\n$stack');
    return true;
  };

  // Set system UI overlay style
  try {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.darkCard,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  } catch (e) {
    debugPrint('[Main] SystemUI error: $e');
  }

  // Initialize notification channels safely
  try {
    final notificationService = NotificationService();
    await notificationService.initialize();
  } catch (e) {
    debugPrint('[Main] NotificationService error: $e');
  }

  // Initialize background execution safely
  try {
    final backgroundService = BackgroundService();
    await backgroundService.initialize();
  } catch (e) {
    debugPrint('[Main] BackgroundService error: $e');
  }

  runApp(
    const ProviderScope(
      child: PolarSenseApp(),
    ),
  );
}

class PolarSenseApp extends ConsumerWidget {
  const PolarSenseApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(stringsProvider);
    return MaterialApp(
      title: strings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends ConsumerStatefulWidget {
  const MainNavigationShell({super.key});

  @override
  ConsumerState<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    SleepScreen(),
    DeviceScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(stringsProvider);

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(_screens.length, (i) {
          return TickerMode(
            enabled: _currentIndex == i,
            child: _screens[i],
          );
        }),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.dashboard_outlined),
            activeIcon: const Icon(Icons.dashboard),
            label: strings.tabHome,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.nightlight_outlined),
            activeIcon: const Icon(Icons.nightlight_round),
            label: strings.tabSleep,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.bluetooth_searching),
            activeIcon: const Icon(Icons.bluetooth_connected),
            label: strings.tabSensor,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.settings_outlined),
            activeIcon: const Icon(Icons.settings),
            label: strings.tabSettings,
          ),
        ],
      ),
    );
  }
}
