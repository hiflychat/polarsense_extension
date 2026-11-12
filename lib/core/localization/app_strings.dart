import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../background/background_service.dart';
import '../database/health_database.dart';
import '../database/models/sleep_record.dart';
import '../notifications/notification_service.dart';

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
  String get appTitle => isZh ? '晴雨脉' : 'PolarSense';
  String get sedentaryTracker => isZh ? '久坐实时监测' : 'Sedentary Live Tracking';
  String get sedentaryAlert => isZh ? '该站起来活动一下了！' : 'Time to stand up and move!';
  String get sedentaryAlertDesc => isZh
      ? '您已静坐超过设定时间，请起身走动以重置计时器。'
      : 'You have been sedentary past your threshold. Walk to reset.';
  String get resetManually => isZh ? '手动重置' : 'Reset Timer';
  String get walkingResetTip => isZh ? '连续活动或走动 60 秒可自动重置计时' : 'Move arms or walk for 60s to auto-reset';
  String get sedentaryStationary => isZh ? '静止坐姿' : 'Stationary';
  String get sedentaryTyping => isZh ? '工位办公' : 'Desk Work';
  String get sedentaryMovingArm => isZh ? '手臂活动' : 'Active (Arms)';
  String get sedentaryWalking => isZh ? '走动中' : 'Walking';
  String get sedentaryDisconnected => isZh ? '手环未连接' : 'Sensor Disconnected';
  String get liveMotionVmu => isZh ? '姿态动量' : 'Motion VMU';
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
  String get walkingStreak => isZh ? '持续活动' : 'Active Streak';
  String get min => isZh ? '分钟' : 'min';
  String get sec => isZh ? '秒' : 'sec';
  String get hrs => isZh ? '小时' : 'hrs';
  String get bpm => isZh ? '次/分' : 'BPM';
  String get ms => isZh ? '毫秒' : 'ms';
  String get limit => isZh ? '提醒阈值' : 'Limit';
  String get goal90s => isZh ? '目标: 60秒重置' : 'Goal: 60 sec reset';
  String get ok => isZh ? '确定' : 'OK';
  String get gotIt => isZh ? '知道了' : 'Got it';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get deleteLabel => isZh ? '删除' : 'Delete';
  String get vmuSedentaryLegend => isZh
      ? '图注：姿态动量 VMU 阈值 <0.035g 判定静坐，≥0.070g (主动活动/走动) 满 60 秒自动重置'
      : 'Legend: VMU < 0.035g = Stationary · ≥ 0.070g (active arms/walking) for 60s resets timer';

  // Sensor Screen
  String get sensorTitle => 'Polar Verity Sense';
  String get pairedDevice => isZh ? '已配对设备' : 'Paired Device';
  String get noDeviceConnected => isZh ? '未连接手环设备' : 'No Device Connected';
  String get status => isZh ? '连接状态' : 'Status';
  String get connected => isZh ? '已连接' : 'Connected';
  String get streaming => isZh ? '数据传输中' : 'Streaming';
  String get connecting => isZh ? '正在连接...' : 'Connecting...';
  String get disconnected => isZh ? '未连接' : 'Disconnected';
  String get autoConnecting => isZh ? '正在自动连接已配对设备...' : 'Auto-connecting to saved device...';
  String get scanBle => isZh ? '扫描蓝牙' : 'Scan BLE';
  String get scanning => isZh ? '扫描中...' : 'Scanning...';
  String get scanningBtn => isZh ? '正在扫描...' : 'Scanning...';
  String get disconnect => isZh ? '断开连接' : 'Disconnect';
  String get connect => isZh ? '连接' : 'Connect';
  String get reconnectNow => isZh ? '立即重连' : 'Reconnect Now';
  String get signalQuality => isZh ? '信号质量' : 'Signal';
  String get signalExcellent => isZh ? '极佳' : 'Excellent';
  String get signalGood => isZh ? '良好' : 'Good';
  String get signalFair => isZh ? '一般' : 'Fair';
  String get signalWeak => isZh ? '较弱' : 'Weak';
  String get walkingGraceActive => isZh ? '活动缓冲中' : 'Grace Pause';
  String get readingDeviceExercisesStep => isZh ? '步骤 1/3: 正在读取手环存储列表...' : 'Step 1/3: Checking Sense recordings...';
  String get fetchingExerciseSamplesStep => isZh ? '步骤 2/3: 正在高速下载睡眠采样数据...' : 'Step 2/3: Downloading sleep samples...';
  String get analyzingSleepEpochsStep => isZh ? '步骤 3/3: 正在进行 30秒 睡眠分期与 HRV 计算...' : 'Step 3/3: Analyzing 30s sleep stages & HRV...';
  String get forgetDevice => isZh ? '解除配对' : 'Forget Device';
  String get bluetoothPermissionPrompt => isZh
      ? '需要授予蓝牙和定位权限才能连接手环'
      : 'Bluetooth permissions required to connect to sensor';
  String get grantPermission => isZh ? '去授权' : 'Grant';
  String get bluetoothDisabled => isZh ? '手机蓝牙未开启，请先开启蓝牙' : 'Bluetooth is turned off. Please enable Bluetooth.';
  String get discoveredDevices => isZh ? '发现的 Polar 设备' : 'Discovered Polar Devices';
  String get realtimeTelemetry => isZh ? '实时传感器遥测' : 'Real-Time Sensor Telemetry';
  String get sensorBattery => isZh ? '传感器电量' : 'Sensor Battery';
  String get cachedStatus => isZh ? '历史' : 'Cached';
  String get chargingStatus => isZh ? '充电中' : 'Charging';
  String get opticalHr => isZh ? '光学实时心率' : 'Optical HR';
  String get accStreamTitle => isZh ? '26/52 Hz 自适应姿态流' : 'ACC Stream (26/52 Hz)';
  String get accActive => isZh ? '26/52 Hz 姿态同步中 (防久坐与体动检测)' : 'Active (26/52 Hz posture synced)';
  String get accWaiting => isZh ? '等待手环加速度采样...' : 'Waiting for samples...';
  String get hardwareSimulator => isZh ? '硬件模拟器 (开发者模式)' : 'Hardware Simulator (Developer Mode)';
  String get hardwareSimulatorDesc => isZh
      ? '无需连接实体手环即可模拟生成 52Hz 加速度和心率脉冲数据。'
      : 'Simulate 52 Hz accelerometer and PPI streams without physical Polar Verity Sense.';
  String get simulateWalking => isZh ? '模拟行走动作 (VMU ≥ 0.15g)' : 'Simulate Active Walking (VMU ≥ 0.15g)';
  String get walking => isZh ? '行走中' : 'Walking';
  String get stationary => isZh ? '静止中' : 'Stationary';
  String get deviceGlossaryTitle => isZh ? '传感器专业缩写图注' : 'Sensor Telemetry Legend';
  String get deviceGlossaryBody => isZh
      ? '• BPM：每分钟心跳次数 (Beats Per Minute)\n• ACC (52 Hz)：每秒 52 次三轴加速度采样，用于静坐与手臂活动识别\n• PPI：连续两次脉搏心跳间隔毫秒数，用于高精度 HRV 计算\n• RSSI (dBm)：蓝牙信号强度，数值越接近 0 表示信号越稳'
      : '• BPM: Beats Per Minute\n• ACC (52 Hz): Triaxial accelerometry for posture & sedentary detection\n• PPI: Optical pulse-to-pulse intervals (ms) for true HRV\n• RSSI (dBm): Bluetooth signal strength (closer to 0 = stronger)';
  String get syncStopFailed => isZh ? '停止录制失败，请确认手环处于蓝灯模式' : 'Failed to stop recording';
  String get syncStartFailed => isZh ? '开启手环离线录制失败，请重试' : 'Failed to start offline recording';
  String deviceIdLabel(String id) => isZh ? '设备编号: $id' : 'ID: $id';
  String signalRssiLabel(int rssi) => isZh ? '信号强度: $rssi dBm' : 'RSSI: $rssi dBm';

  // Sleep Screen
  String get sleepRecoveryTitle => isZh ? '睡眠与身心恢复' : 'Sleep & Recovery';
  String get stageDistribution => isZh ? '睡眠分期比例' : 'Stage Distribution';
  String get sleepHypnogram => isZh ? '睡眠时序图 (Hypnogram)' : 'Sleep Hypnogram';
  String get deep => isZh ? '深睡眠' : 'Deep';
  String get light => isZh ? '浅睡眠' : 'Light';
  String get rem => isZh ? '快速眼动 (REM)' : 'REM';
  String get wake => isZh ? '清醒' : 'Wake';
  String get stageWakeAxis => isZh ? '清醒' : 'Wake';
  String get stageRemAxis => 'REM';
  String get stageLightAxis => isZh ? '浅睡' : 'Light';
  String get stageDeepAxis => isZh ? '深睡' : 'Deep';
  String get recordingNeed2Epochs => isZh
      ? '监测进行中（累计满 2 个周期 / 约 1 分钟后绘制时序图）...'
      : 'Recording in progress (need at least 2 epochs to graph)...';
  String get hypnogramLegendTitle => isZh ? '图注：' : 'Legend:';
  String get hypnogramLegendWake => isZh ? '清醒 (Wake)' : 'Wake';
  String get hypnogramLegendRem => isZh ? '快速眼动 (REM)' : 'REM';
  String get hypnogramLegendLight => isZh ? '浅睡 (Light)' : 'Light';
  String get hypnogramLegendDeep => isZh ? '深睡 (Deep)' : 'Deep';
  String get hypnogramAxisNote => isZh
      ? '横轴：时间（每格 30 秒） ·  纵轴：深睡 → 浅睡 → REM(快速眼动做梦期) → 清醒'
      : 'X-axis: Time (30s epochs)  ·  Y-axis: Deep → Light → REM → Wake';
  String get recoveryBadgeLabel => isZh ? '恢复评分' : 'RECOVERY';
  String recoveryStatusLabel(int score) {
    if (score >= 85) return isZh ? '最佳恢复状态' : 'Optimal Recovery';
    if (score >= 70) return isZh ? '恢复良好' : 'Good Recovery';
    if (score >= 50) return isZh ? '恢复一般' : 'Moderate Recovery';
    return isZh ? '恢复欠佳 / 疲劳偏高' : 'Suboptimal / High Fatigue';
  }
  String get totalSleep => isZh ? '监测总时长' : 'Time in Bed';
  String actualSleepEfficiencySub(int actualMin, double efficiencyPct) {
    final h = actualMin ~/ 60;
    final m = actualMin % 60;
    return isZh
        ? '有效睡眠 ${h}小时${m}分钟 · 效率 ${efficiencyPct.round()}%'
        : 'Asleep ${h}h ${m}m · Efficiency ${efficiencyPct.round()}%';
  }
  String get restingHrLowest => isZh ? '夜间静息心率' : 'Resting HR';
  String get restingHrDesc => isZh ? '整夜最低 10% 分位心率' : 'Overnight lowest 10%';
  String get hrvTitle => isZh ? '心率变异性 (HRV)' : 'HRV (RMSSD)';
  String get hrvDesc => isZh ? '自主神经系统修复指标' : 'Autonomic recovery (RMSSD)';
  String get hrvUnavailableShort => isZh ? '需 PPI' : 'N/A';
  String get hrvUnavailableDesc => isZh
      ? '绿灯离线仅心率模式暂不支持 HRV'
      : 'Unavailable in 1Hz HR-only offline mode';
  String get healthSync => isZh ? '健康生态同步' : 'Health Sync';
  String get healthEcosystemSub => isZh ? 'Apple 健康 / Health Connect' : 'HealthKit / Health Connect';
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
  String durationFactorWeighted(int pct) => isZh ? '时长贡献 ($pct%)' : 'Duration ($pct%)';
  String stageRatioFactorWeighted(int pct) => isZh ? '深度+REM贡献 ($pct%)' : 'Deep+REM ($pct%)';
  String get hrvFactorUnavailable => isZh ? 'HRV 指数 (需 PPI 模式)' : 'HRV Index (Needs PPI)';

  String dataSourceLabel(String source) {
    switch (source) {
      case SleepSession.sourceOfflinePpi:
        return isZh ? '数据来源：手环离线 PPI 精确录制' : 'Source: Offline Sensor PPI';
      case SleepSession.sourceOfflineHrOnly:
        return isZh ? '数据来源：手环绿灯离线录制 (仅 1Hz 心率)' : 'Source: Green-LED Offline (1Hz HR)';
      default:
        return isZh ? '数据来源：实时蓝牙高精度监测 (ACC + PPI)' : 'Source: Live BLE Precision (ACC + PPI)';
    }
  }

  String get hrOnlyModeNotice => isZh
      ? '说明：绿灯独立录制仅存储 1Hz 每分钟心率 (BPM)，不含原始脉搏间期 (PPI) 与三轴加速度。当前分期已自动采用“个人静息心率+短时心率波动率”模型估算，恢复评分按睡眠时长 50% + 深睡/REM 比例 50% 公平权重计算，未伪造 RMSSD 数值。'
      : 'Note: Standalone Green-LED mode records 1Hz HR (BPM) without raw PPI or ACC streams. Sleep stages are estimated from nocturnal HR nadir & short-term variability, and Recovery Score uses 50% Duration + 50% Deep/REM weighting.';

  String get metricGlossaryTitle => isZh ? '名词与缩写图注' : 'Terminology Legend';
  List<({String term, String desc})> get glossaryItems => isZh
      ? [
          (term: 'REM (快速眼动期)', desc: '大脑活跃与做梦阶段，心率波动较大，主要完成情绪调节与记忆巩固，健康成人通常占 20%–25%。'),
          (term: 'HRV / RMSSD', desc: '心率变异性与相邻心跳间期差值的均方根（单位：毫秒 ms），数值越高通常代表副交感神经修复越充分，须基于 PPI 脉冲间期测量。'),
          (term: 'RHR / BPM', desc: '夜间静息心率（取整夜最低 10% 分位）与每分钟心跳次数（Beats Per Minute）。'),
          (term: '恢复评分构成', desc: '基于 7–9 小时睡眠时长、深睡+REM 目标占比（35%–50%）及 14 天个人 HRV 基线综合评估；缺 PPI 时按时长与结构 50%/50% 计分。'),
        ]
      : [
          (term: 'REM Sleep', desc: 'Rapid Eye Movement sleep; vivid dreaming and memory consolidation phase (~20–25% of sleep).'),
          (term: 'HRV / RMSSD', desc: 'Root Mean Square of Successive PPI Differences (ms); reflects vagal/parasympathetic recovery (requires PPI intervals).'),
          (term: 'Resting HR (BPM)', desc: '10th-percentile lowest overnight heart rate in Beats Per Minute.'),
          (term: 'Recovery Score', desc: 'Weighted composite of Duration (7–9h target), Deep+REM ratio (35–50%), and Night RMSSD vs. 14-day baseline.'),
        ];

  String get deleteSessionTitle => isZh ? '删除本地记录' : 'Delete Local Record';
  String get deleteSessionConfirm => isZh
      ? '仅删除手机本地该条分析记录（手环内部原数据不会被清除，可随时点击同步重新导入运算）。是否继续？'
      : 'Delete this record from local phone storage? (The sensor copy remains intact if you wish to re-sync.)';
  String get sessionDeleted => isZh ? '已清除本地记录' : 'Local record deleted';

  // Sync progress messages
  String get syncProgressPreparing => isZh ? '正在准备蓝牙传输通道与检查手环状态...' : 'Preparing transfer channel & checking sensor...';
  String get syncProgressListing => isZh ? '正在读取手环内置存储列表...' : 'Reading sensor internal storage...';
  String get syncProgressAlreadyDone => isZh ? '手环内记录此前已全部同步完毕' : 'All sensor records are already synced';
  String syncProgressDownloading(int current, int total) => isZh
      ? '正在下载睡眠数据 ($current/$total)...'
      : 'Downloading sleep data ($current/$total)...';
  String syncProgressAnalyzing(int current, int total) => isZh
      ? '正在本地分析 30 秒分期与 HRV ($current/$total)...'
      : 'Analyzing 30s sleep stages & HRV ($current/$total)...';

  // Offline Sleep & Standalone Recording
  String get offlineSyncTitle => isZh ? '手环离线睡眠同步' : 'Sense Offline Sync';
  String get syncOfflineSleep => isZh ? '从手环同步离线睡眠' : 'Sync Sleep from Sense';
  String get syncOfflineSleepDesc => isZh
      ? '下载手环内部存储的昨夜睡眠数据，自动完成本地 30 秒分期与身心恢复评分'
      : 'Download recorded sleep from Sense flash memory & analyze stages & recovery';
  String get offlineRecording => isZh ? '手环独立录制' : 'Standalone Recording';
  String get startOfflineRecord => isZh ? '开启手环离线录制' : 'Start Sensor Recording';
  String get stopOfflineRecord => isZh ? '停止手环离线录制' : 'Stop Sensor Recording';
  String get offlineRecordingActive => isZh ? '手环正在独立录制中 (绿灯模式)' : 'Sensor is recording internally (Green LED)';
  String get offlineRecordingIdle => isZh ? '手环未在录制' : 'Sensor recording is idle';
  String get recordingStatus => isZh ? '正在独立录制' : 'Recording';
  String get readingDeviceExercises => isZh ? '正在读取手环存储列表...' : 'Checking Sense storage...';
  String get preparingSyncChannel => isZh ? '正在暂停实时流，释放手环传输通道...' : 'Pausing streams & releasing BLE transfer channel...';
  String get allExercisesAlreadySynced => isZh ? '手环内记录此前已全部同步完毕，已展示最新睡眠分析。' : 'All sensor records already synced. Displaying latest analysis.';
  String get pleaseConnectSenseFirst => isZh ? '请先连接手环再同步离线数据' : 'Please connect Polar Verity Sense before syncing';
  String get fetchingExerciseSamples => isZh ? '正在高速下载睡眠采样数据...' : 'Downloading sleep samples...';
  String get analyzingSleepEpochs => isZh ? '正在进行 30秒 睡眠分期与 HRV 计算...' : 'Analyzing 30s sleep stages & HRV...';
  String get offlineSyncSuccess => isZh ? '昨夜离线睡眠已成功同步并完成深度分析！' : 'Last night sleep synced and analyzed successfully!';
  String get noExercisesFound => isZh ? '手环中未检测到新的离线睡眠记录。' : 'No offline recordings found on Sense.';
  String get offlineGuideDialogTitle => isZh ? 'Polar Verity Sense 离线使用指南' : 'Polar Verity Sense Offline Guide';
  String get offlineGuideStep1 => isZh
      ? '1. 睡前开机：短按机身侧边圆形电源键开机。'
      : '1. Power on: Short press the round side button to turn on.';
  String get offlineGuideStep2 => isZh
      ? '2. 切换绿灯：再次短按电源键，将侧面 3 颗 LED 指示灯切换至【绿色】（独立记录模式）。'
      : '2. Green LED: Short press button to switch LED to GREEN (standalone recording mode).';
  String get offlineGuideStep3 => isZh
      ? '3. 佩戴入睡：佩戴在上臂或手腕入睡。手机可关机或关闭蓝牙，手环内部 16MB 芯片静默记录整夜。'
      : '3. Wear to sleep: Wear on arm or wrist. Phone can be off; Sense records silently overnight.';
  String get offlineGuideStep4 => isZh
      ? '4. 醒来同步：晨起开机连接后点击【从手环同步离线睡眠】，1分钟内即可获取完整睡眠时序图与恢复分析报告！'
      : '4. Wake & Sync: In the morning, connect and tap "Sync Sleep from Sense" to analyze in seconds!';
  String get deviceMemory => isZh ? '手环内置闪存' : 'Sensor Flash Memory';
  String get memoryDetail => isZh ? '16 MB 存储容量 (约可存 600 小时睡眠)' : '16 MB storage (~600 hours recording)';
  String get storedExercises => isZh ? '手环中存储的记录' : 'Stored Records';
  String get clearStorage => isZh ? '清除手环记录' : 'Delete from Sensor';
  String get clearStorageConfirm => isZh ? '确认从手环内部存储中删除此记录吗？' : 'Delete this record from sensor memory?';
  String get generateMockOffline => isZh ? '模拟生成 7.5小时 离线睡眠数据' : 'Simulate 7.5h Offline Sleep';
  String get offlineTrackingMode => isZh ? '离线睡眠模式' : 'Offline Sleep Mode';
  String get liveTrackingMode => isZh ? '实时蓝牙在线' : 'Real-Time Streaming';

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
  String get aboutPolarSense => isZh ? '关于晴雨脉' : 'About PolarSense';
  String get aboutAppName => isZh ? '晴雨脉 (Polar Verity Sense 睡眠与久坐健康助手)' : 'PolarSense (Verity Sense Sleep & Sedentary)';
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
      final isZh = saved != 'en';
      state = isZh ? AppLanguage.zh : AppLanguage.en;
      NotificationService().setLanguage(isZh: isZh);
      BackgroundService().setLanguage(isZh: isZh);
    } catch (_) {}
  }

  Future<void> setLanguage(AppLanguage lang) async {
    state = lang;
    final isZh = lang == AppLanguage.zh;
    NotificationService().setLanguage(isZh: isZh);
    BackgroundService().setLanguage(isZh: isZh);
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
