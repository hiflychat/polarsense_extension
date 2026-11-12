enum SleepStage {
  wake,
  rem,
  light,
  deep,
}

extension SleepStageExtension on SleepStage {
  String get name {
    switch (this) {
      case SleepStage.wake:
        return 'Wake';
      case SleepStage.rem:
        return 'REM';
      case SleepStage.light:
        return 'Light';
      case SleepStage.deep:
        return 'Deep';
    }
  }

  int get code {
    switch (this) {
      case SleepStage.wake:
        return 0;
      case SleepStage.rem:
        return 1;
      case SleepStage.light:
        return 2;
      case SleepStage.deep:
        return 3;
    }
  }

  static SleepStage fromCode(int code) {
    switch (code) {
      case 0:
        return SleepStage.wake;
      case 1:
        return SleepStage.rem;
      case 2:
        return SleepStage.light;
      case 3:
        return SleepStage.deep;
      default:
        return SleepStage.light;
    }
  }
}

class SleepEpoch {
  final int? id;
  final String sessionId;
  final DateTime timestamp;
  final SleepStage stage;
  final double meanHr;
  final double rmssd;
  final double movementIndex;

  SleepEpoch({
    this.id,
    required this.sessionId,
    required this.timestamp,
    required this.stage,
    required this.meanHr,
    required this.rmssd,
    required this.movementIndex,
  });

  SleepEpoch copyWith({
    int? id,
    String? sessionId,
    DateTime? timestamp,
    SleepStage? stage,
    double? meanHr,
    double? rmssd,
    double? movementIndex,
  }) {
    return SleepEpoch(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      timestamp: timestamp ?? this.timestamp,
      stage: stage ?? this.stage,
      meanHr: meanHr ?? this.meanHr,
      rmssd: rmssd ?? this.rmssd,
      movementIndex: movementIndex ?? this.movementIndex,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'sessionId': sessionId,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'stage': stage.code,
      'meanHr': meanHr,
      'rmssd': rmssd,
      'movementIndex': movementIndex,
    };
  }

  factory SleepEpoch.fromMap(Map<String, dynamic> map) {
    return SleepEpoch(
      id: map['id'] as int?,
      sessionId: map['sessionId'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      stage: SleepStageExtension.fromCode(map['stage'] as int),
      meanHr: (map['meanHr'] as num).toDouble(),
      rmssd: (map['rmssd'] as num).toDouble(),
      movementIndex: (map['movementIndex'] as num).toDouble(),
    );
  }
}

class SleepSession {
  static const String sourceLiveAccPpi = 'live_acc_ppi';
  static const String sourceOfflinePpi = 'offline_ppi';
  static const String sourceOfflineHrOnly = 'offline_hr_only';

  final String id;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final int wakeMinutes;
  final int remMinutes;
  final int lightMinutes;
  final int deepMinutes;
  final double restingHr;
  final double avgRmssd;
  final int recoveryScore;
  final bool syncedToHealth;
  final String dataSource;

  SleepSession({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.wakeMinutes,
    required this.remMinutes,
    required this.lightMinutes,
    required this.deepMinutes,
    required this.restingHr,
    required this.avgRmssd,
    required this.recoveryScore,
    this.syncedToHealth = false,
    this.dataSource = sourceLiveAccPpi,
  });

  bool get isHrOnlyOffline => dataSource == sourceOfflineHrOnly;
  bool get hasHrvData => !isHrOnlyOffline && avgRmssd > 0;
  int get actualSleepMinutes => deepMinutes + remMinutes + lightMinutes;
  int get effectiveSleepMinutes => actualSleepMinutes > 0 ? actualSleepMinutes : durationMinutes;
  double get sleepEfficiency => durationMinutes > 0
      ? ((actualSleepMinutes / durationMinutes) * 100.0).clamp(0.0, 100.0)
      : 0.0;

  double get deepPercentage => durationMinutes > 0 ? (deepMinutes / durationMinutes) * 100 : 0.0;
  double get remPercentage => durationMinutes > 0 ? (remMinutes / durationMinutes) * 100 : 0.0;
  double get lightPercentage => durationMinutes > 0 ? (lightMinutes / durationMinutes) * 100 : 0.0;
  double get wakePercentage => durationMinutes > 0 ? (wakeMinutes / durationMinutes) * 100 : 0.0;
  String get durationFormatted => '${durationMinutes ~/ 60}h ${durationMinutes % 60}m';

  String formattedDuration({bool isZh = false}) {
    final h = durationMinutes ~/ 60;
    final m = durationMinutes % 60;
    return isZh ? '${h}小时${m}分钟' : '${h}h ${m}m';
  }

  SleepSession copyWith({
    String? id,
    DateTime? startTime,
    DateTime? endTime,
    int? durationMinutes,
    int? wakeMinutes,
    int? remMinutes,
    int? lightMinutes,
    int? deepMinutes,
    double? restingHr,
    double? avgRmssd,
    int? recoveryScore,
    bool? syncedToHealth,
    String? dataSource,
  }) {
    return SleepSession(
      id: id ?? this.id,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      wakeMinutes: wakeMinutes ?? this.wakeMinutes,
      remMinutes: remMinutes ?? this.remMinutes,
      lightMinutes: lightMinutes ?? this.lightMinutes,
      deepMinutes: deepMinutes ?? this.deepMinutes,
      restingHr: restingHr ?? this.restingHr,
      avgRmssd: avgRmssd ?? this.avgRmssd,
      recoveryScore: recoveryScore ?? this.recoveryScore,
      syncedToHealth: syncedToHealth ?? this.syncedToHealth,
      dataSource: dataSource ?? this.dataSource,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'durationMinutes': durationMinutes,
      'wakeMinutes': wakeMinutes,
      'remMinutes': remMinutes,
      'lightMinutes': lightMinutes,
      'deepMinutes': deepMinutes,
      'restingHr': restingHr,
      'avgRmssd': avgRmssd,
      'recoveryScore': recoveryScore,
      'syncedToHealth': syncedToHealth ? 1 : 0,
      'dataSource': dataSource,
    };
  }

  factory SleepSession.fromMap(Map<String, dynamic> map) {
    final rmssd = (map['avgRmssd'] as num).toDouble();
    final rawSource = map['dataSource'] as String?;
    return SleepSession(
      id: map['id'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['endTime'] as int),
      durationMinutes: map['durationMinutes'] as int,
      wakeMinutes: map['wakeMinutes'] as int,
      remMinutes: map['remMinutes'] as int,
      lightMinutes: map['lightMinutes'] as int,
      deepMinutes: map['deepMinutes'] as int,
      restingHr: (map['restingHr'] as num).toDouble(),
      avgRmssd: rmssd,
      recoveryScore: map['recoveryScore'] as int,
      syncedToHealth: (map['syncedToHealth'] as int) == 1,
      dataSource: rawSource ?? (rmssd <= 0 ? sourceOfflineHrOnly : sourceLiveAccPpi),
    );
  }
}
