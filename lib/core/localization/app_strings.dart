import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/health_database.dart';

enum AppLanguage {
  zh, // 简体中文
  en, // English
}

class AppStrings {
  final AppLanguage language;

  AppStrings(this.language);

  bool get isZh => language == AppLanguage.zh;

  // Bottom Tabs
  String get tabHome => isZh ? '首页' : 'Home';
  String get tabSleep => isZh ? '夜间睡眠' : 'Sleep';
  String get tabSensor => isZh ? '传感器' : 'Sensor';
  String get tabSettings => isZh ? '系统设置' : 'Settings';

  // Home Screen
  String get appTitle => isZh ? 'PolarSense 极地感应' : 'PolarSense';
  String get sedentaryTracker => isZh ? '久坐实时监测' : 'Sedentary Live Tracking';
  String get sedentaryAlert => isZh ? '该站起来活动一下了！' : 'Time to stand up and move!';
  String get sedentaryAlertDesc => isZh
      ? '您已静坐超过设定时间，请起身走动以重置计时器。'
      : 'You have been sedentary past your threshold. Walk to reset.';
  String get resetManually => isZh ? '手动重置' : 'Reset Timer';
  String get walkingResetTip => isZh ? '连续走动 90 秒可自动重置计时' : 'Walk for 90 seconds to auto-reset';
  String get trackOvernightSleep => isZh ? '追踪夜间睡眠' : 'Track Overnight Sleep';
  String get recordsPpiRmssd => isZh
      ? '记录微秒级 PPI、RMSSD 及 30 秒睡眠分期'
      : 'Records PPI, RMSSD, and 30s sleep epochs';
  String get startSleepTracking => isZh ? '开始睡眠监测' : 'Start';
  String get connectBleFirst => isZh ? '请先连接手环' : 'Connect BLE';
  String get sleepTrackingActive => isZh ? '正在记录睡眠中...' : 'Sleep Session Active';
  String get wakeUpAndSave => isZh ? '醒来并保存' : 'Wake Up';
  String get elapsed => isZh ? '已记录' : 'Elapsed';
  String get stage => isZh ? '当前状态' : 'Stage';
  String get lastNightRecovery => isZh ? '昨夜恢复评分' : 'Last Night Recovery';
  String get noSleepRecorded => isZh ? '暂无睡眠数据' : 'No sleep session recorded yet';
  String get noSleepRecordedDesc => isZh
      ? '今晚佩戴 Polar Verity Sense 入睡，点击“开始睡眠监测”即可获得专属恢复评分。'
      : 'Wear your Polar Verity Sense to bed and tap Start to record sleep stages & recovery.';
  String get currentSitting => isZh ? '当前静坐' : 'Current Sitting';
  String get walkingStreak => isZh ? '连续走动' : 'Walking Streak';
  String get min => isZh ? '分钟' : 'min';
  String get sec => isZh ? '秒' : 'sec';
  String get hrs => isZh ? '小时' : 'hrs';
  String get bpm => 'BPM';
  String get ms => 'ms';
  String get limit => isZh ? '提醒阈值' : 'Limit';
  String get goal90s => isZh ? '目标: 90秒重置' : 'Goal: 90 sec reset';

  // Sensor Screen
  String get sensorTitle => 'Polar Verity Sense';
  String get pairedDevice => isZh ? '已配对设备' : 'Paired Device';
  String get noDeviceConnected => isZh ? '未连接手环设备' : 'No Device Connected';
  String get status => isZh ? '连接状态' : 'Status';
  String get autoConnecting => isZh ? '正在自动连接已配对设备...' : 'Auto-connecting to saved device...';
  String get scanBle => isZh ? '扫描蓝牙' : 'Scan BLE';
  String get scanning => isZh ? '扫描中...' : 'Scanning...';
  String get disconnect => isZh ? '断开连接' : 'Disconnect';
  String get connect => isZh ? '连接' : 'Connect';
  String get forgetDevice => isZh ? '解除配对' : 'Forget Device';
  String get discoveredDevices => isZh ? '发现的 Polar 设备' : 'Discovered Polar Devices';
  String get realtimeTelemetry => isZh ? '实时传感器遥测' : 'Real-Time Sensor Telemetry';
  String get sensorBattery => isZh ? '传感器电量' : 'Sensor Battery';
  String get opticalHr => isZh ? '光学实时心率' : 'Optical HR';
  String get accStreamTitle => isZh ? '26 Hz 运动姿态流' : 'ACC Stream 26 Hz';
  String get accActive => isZh ? '26 Hz 姿态同步中 (手臂运动检测)' : 'Active (arm posture synced)';
  String get accWaiting => isZh ? '等待手环加速度采样...' : 'Waiting for samples...';
  String get hardwareSimulator => isZh ? '硬件模拟器 (开发者模式)' : 'Hardware Simulator (Developer Mode)';
  String get hardwareSimulatorDesc => isZh
      ? '无需连接实体手环即可模拟生成 26Hz 加速度和心率脉冲数据。'
      : 'Simulate 26 Hz accelerometer and PPI streams without physical Polar Verity Sense.';
  String get simulateWalking => isZh ? '模拟行走动作 (VMU ≥ 0.15g)' : 'Simulate Active Walking (VMU ≥ 0.15g)';
  String get walking => isZh ? '行走中' : 'Walking';
  String get stationary => isZh ? '静止中' : 'Stationary';

  // Sleep Screen
  String get sleepRecoveryTitle => isZh ? '睡眠与身心恢复' : 'Sleep & Recovery';
  String get stageDistribution => isZh ? '睡眠分期比例' : 'Stage Distribution';
  String get sleepHypnogram => isZh ? '睡眠时序图 (Hypnogram)' : 'Sleep Hypnogram';
  String get deep => isZh ? '深睡眠' : 'Deep';
  String get light => isZh ? '浅睡眠' : 'Light';
  String get rem => isZh ? '快速眼动 (REM)' : 'REM';
  String get wake => isZh ? '清醒' : 'Wake';
  String get totalSleep => isZh ? '总睡眠时长' : 'Total Sleep';
  String get restingHrLowest => isZh ? '静息心率' : 'Resting HR';
  String get restingHrDesc => isZh ? '夜间最低 10% 均值' : 'Overnight lowest 10%';
  String get hrvTitle => isZh ? '心率变异性 (RMSSD)' : 'HRV (RMSSD)';
  String get hrvDesc => isZh ? '自主神经系统恢复指标' : 'Autonomic recovery';
  String get healthSync => isZh ? '健康生态同步' : 'Health Sync';
  String get synced => isZh ? '已同步' : 'Synced';
  String get localOnly => isZh ? '本地存储' : 'Local';
  String get exportTooltip => isZh ? '导出至系统健康生态' : 'Export to HealthKit / Health Connect';
  String get syncSuccess => isZh ? '已成功同步至系统健康生态！' : 'Successfully synced session to Health ecosystem!';
  String get syncFail => isZh ? '同步失败，请检查健康数据写入权限。' : 'Could not sync. Ensure Health permissions are granted.';
  String get noSleepEmpty => isZh ? '暂无睡眠记录' : 'No Sleep Sessions Recorded';
  String get noSleepEmptyDesc => isZh
      ? '今晚佩戴手环入睡，在首页点击“开始睡眠监测”，晨起即可查看详细恢复分析。'
      : 'Connect your Polar Verity Sense and tap "Start Sleep Session" on the Home tab to record your overnight sleep stages.';
  String get noEpochData => isZh ? '该会话无详细分期数据' : 'No epoch data recorded for this session';

  // Recovery breakdown
  String get durationFactor => isZh ? '时长贡献 (30%)' : 'Duration (30%)';
  String get stageRatioFactor => isZh ? '深度+REM贡献 (30%)' : 'Deep+REM (30%)';
  String get hrvFactor => isZh ? 'HRV指数贡献 (40%)' : 'HRV Index (40%)';

  // Settings Screen
  String get settingsTitle => isZh ? '系统设置' : 'Settings';
  String get languageSetting => isZh ? '语言设置 / Language' : 'Language';
  String get simplifiedChinese => '简体中文';
  String get english => 'English';
  String get sedentaryAlertInterval => isZh ? '久坐提醒间隔' : 'Sedentary Alert Interval';
  String get minutesSuffix => isZh ? '分钟' : 'minutes';
  String get backgroundExecution => isZh ? '后台长连接保活' : 'Background Execution';
  String get backgroundDesc => isZh
      ? '开启后使用 Android 前台常驻通知，锁屏时仍保持手环连接与防久坐监测。'
      : 'Maintains continuous Bluetooth connection with Polar Verity Sense while app is in background.';
  String get serviceActive => isZh ? '前台保活服务运行中' : 'Foreground service active';
  String get serviceStopped => isZh ? '服务已停止' : 'Service stopped';
  String get stopService => isZh ? '停止' : 'Stop';
  String get startService => isZh ? '开启' : 'Start';
  String get healthPermissions => isZh ? '健康生态数据授权' : 'Health Ecosystem Permissions';
  String get healthPermissionsDesc => isZh
      ? '授权写入 Apple HealthKit / Google Health Connect 睡眠与心率数据。'
      : 'Grants access to export sleep stages, resting HR, and HRV to Apple HealthKit / Google Health Connect.';
  String get requestAuth => isZh ? '申请授权' : 'Request Permissions';
  String get syncAllSessions => isZh ? '一键同步所有未同步会话' : 'Sync All Unsynced Sessions';
  String get sessionsSynced => isZh ? '已同步会话' : 'sessions synced';
  String get aboutPolarSense => isZh ? '关于 PolarSense' : 'About PolarSense';
  String get version => isZh ? '版本' : 'Version';
}

class AppLanguageNotifier extends StateNotifier<AppLanguage> {
  final HealthDatabase _database = HealthDatabase();

  AppLanguageNotifier() : super(AppLanguage.zh) {
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    try {
      final saved = await _database.getSetting('app_language');
      if (saved == 'en') {
        state = AppLanguage.en;
      } else {
        state = AppLanguage.zh;
      }
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage lang) async {
    state = lang;
    try {
      await _database.setSetting('app_language', lang == AppLanguage.en ? 'en' : 'zh');
    } catch (_) {}
  }
}

final appLanguageProvider = StateNotifierProvider<AppLanguageNotifier, AppLanguage>((ref) {
  return AppLanguageNotifier();
});

final stringsProvider = Provider<AppStrings>((ref) {
  final lang = ref.watch(appLanguageProvider);
  return AppStrings(lang);
});
