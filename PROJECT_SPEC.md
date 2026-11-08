# PolarSense Extension — App Technical Specification & Agent Prompt

## 1. Project Overview & Objectives
Build a cross-platform (iOS & Android) Flutter application that extends the Polar Verity Sense optical heart rate sensor. The app fills key feature gaps not supported by the official Polar Flow app:
- **Sedentary Reminder (久坐提醒)**: Uses the sensor's 3-axis accelerometer on the arm to accurately detect prolonged sitting and triggers alerts on the smartphone.
- **Sleep & Recovery Monitoring (睡眠与恢复评估)**: Uses overnight PPI (pulse-to-pulse interval) and accelerometer streams to calculate sleep stages (Wake, Light, Deep, REM), resting heart rate (RHR), HRV (RMSSD), and generate a 0-100 Recovery Score.
- **Health Ecosystem Sync**: Syncs finished sleep sessions and resting metrics into Apple HealthKit and Google Health Connect.

## 2. Technology Stack & Key Packages
- **Framework**: Flutter (Channel stable, Dart 3.x)
- **Hardware SDK**: `polar: ^7.11.0` (official Polar BLE SDK wrapper)
- **Background Execution**:
  - Android: `flutter_foreground_task: ^8.0.0`
  - iOS: Native CoreBluetooth Background Central (`UIBackgroundModes: [bluetooth-central]`)
- **Local Storage**: `sqflite: ^2.3.0` (for 30s epoch health time-series) / `path: ^1.9.0`
- **State Management**: `flutter_riverpod: ^2.5.0`
- **Notifications**: `flutter_local_notifications: ^17.0.0`
- **Charts & UI**: `fl_chart: ^0.70.0`
- **Health Sync**: `health: ^11.0.0`

## 3. Directory Structure
```
lib/
├── core/
│   ├── ble/
│   │   ├── polar_ble_manager.dart       # Scan, connect, reconnect, stream routing
│   │   └── polar_constants.dart
│   ├── background/
│   │   └── background_service.dart     # Android foreground service & iOS lifecycle
│   ├── notifications/
│   │   └── notification_service.dart   # Local alerts and alarms
│   ├── database/
│   │   ├── health_database.dart        # Local storage for daily summary & raw epochs
│   │   └── models/
│   │       ├── sleep_record.dart
│   │       └── sedentary_event.dart
├── features/
│   ├── sedentary/
│   │   ├── sedentary_engine.dart       # ACC signal processing, VMU math, state machine
│   │   └── sedentary_notifier.dart
│   ├── sleep/
│   │   ├── sleep_engine.dart           # PPI filtering, 30s epoch, HRV (RMSSD), staging
│   │   ├── hrv_calculator.dart         # RMSSD, SDNN, baseline comparisons
│   │   ├── sleep_staging_model.dart    # Heuristic or rule-based sleep classification
│   │   ├── recovery_score_calculator.dart # Nightly Recovery Score (0-100)
│   │   └── sleep_session_controller.dart
│   └── health_sync/
│       └── health_export_service.dart  # Export to Apple HealthKit / Health Connect
└── presentation/
    ├── theme/
    │   └── app_theme.dart
    ├── home/
    │   └── home_screen.dart
    ├── device/                         # Device pairing and live sensor signal screen
    │   └── device_screen.dart
    ├── sleep/                          # Sleep stages hypnogram chart, recovery breakdown
    │   └── sleep_screen.dart
    ├── settings/
    │   └── settings_screen.dart
    └── widgets/
        ├── recovery_gauge.dart
        ├── hypnogram_chart.dart
        ├── sedentary_progress_bar.dart
        └── metric_card.dart
```

## 4. Native Permissions & Configuration

### iOS Configuration (`ios/Runner/Info.plist`)
Must configure CoreBluetooth background mode to prevent the app from disconnecting when the user sleeps with their phone locked:
```xml
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
    <string>processing</string>
</array>
<key>NSBluetoothAlwaysUsageDescription</key>
<string>App requires continuous Bluetooth connection to Polar Verity Sense for sedentary tracking and sleep analysis.</string>
<key>NSHealthShareUsageDescription</key>
<string>We need access to read baseline resting heart rate for sleep comparison.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>We write your overnight sleep stages and HRV metrics to Apple Health.</string>
```

### Android Configuration (`android/app/src/main/AndroidManifest.xml`)
Must support Bluetooth permissions for Android 12+ and foreground service:
```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

## 5. Mathematical Models & State Machines

### Module A: Sedentary Engine (`sedentary_engine.dart`)
- **Input**: Accelerometer data stream at 26 Hz (`PolarAccData`).
- **Window Feature Extraction**:
  Calculate Vector Magnitude Unit ($VMU$) for each sample:
  $$VMU_i = \left\vert{} \sqrt{x_i^2 + y_i^2 + z_i^2} - 1.0g \right\vert{}$$
  Aggregate across a sliding window of 5 seconds:
  $$\overline{VMU}_{5s} = \frac{1}{N} \sum_{i=1}^{N} VMU_i$$
- **State Machine**:
  - **Sedentary State**: If $\overline{VMU}_{5s} < 0.04g$ for consecutive windows, increment the sedentary timer.
  - **Active / Walking State**: If $\overline{VMU}_{5s} \ge 0.15g$ continuously for $\ge 90$ seconds (or user takes equivalent active steps), reset the sedentary timer.
  - **Alert Condition**: When the sedentary timer reaches the user threshold (default: 45 or 60 minutes), trigger a local notification with audio and vibration: "Time to move! You've been stationary for 45 minutes.".

### Module B: Sleep & HRV Engine (`sleep_engine.dart`)
- **Input Streams**:
  - `startOhrPPIStreaming(deviceId)` (Beat-to-beat intervals in ms).
  - `startAccStreaming(deviceId)` (Set to 26Hz for arm movement detection).
- **Data Cleaning**:
  - Discard any PPI sample where `sample.blockerBit == true` or where $PPI < 300\text{ms}$ or $PPI > 2000\text{ms}$.
- **Epoch Processing (30-second window)**: For every 30-second window, compute:
  - Mean HR (bpm): $60000 / \text{mean}(PPI)$.
  - RMSSD (ms):
    $$RMSSD = \sqrt{\frac{1}{M-1} \sum_{k=1}^{M-1} (PPI_{k+1} - PPI_k)^2}$$
  - Epoch Movement Index: $\sum VMU$ from accelerometer during the 30 seconds.
- **Sleep Stage Classification Heuristic**:
  - **Wake**: High movement index ($> 0.08g$) OR heart rate elevated ($> \text{baseline} + 15\text{ bpm}$).
  - **Deep Sleep (SWS)**: Very low movement ($< 0.01g$), low HR ($\le \text{baseline} + 5\text{ bpm}$), and high RMSSD ($\ge 1.2 \times \text{baseline RMSSD}$).
  - **REM**: Negligible body movement, but HR shows elevated irregularity and lower RMSSD than Deep Sleep.
  - **Light Sleep**: Default intermediate state between Wake and Deep/REM.
- **Nightly Recovery Score (0 - 100)**:
  - **Sleep Duration Score (30%)**: Target 7–9 hours.
  - **Deep + REM Sleep Ratio (30%)**: Target combined Deep (15-25%) + REM (20-25%).
  - **HRV / ANS Score (40%)**: Compare the night's average RMSSD to the user's personal 14-day rolling average:
    $$\text{HRV Factor} = \frac{\text{Night RMSSD}}{\text{14-Day Baseline RMSSD}}$$
    Scaled from 0 to 100.
