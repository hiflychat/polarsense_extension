import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import '../../core/database/health_database.dart';
import '../../core/database/models/sleep_record.dart';

class HealthExportService {
  final Health _health = Health();
  final HealthDatabase _database = HealthDatabase();

  static const List<HealthDataType> requiredTypes = [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.RESTING_HEART_RATE,
    HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
  ];

  Future<bool> requestPermissions() async {
    try {
      final permissions = requiredTypes.map((_) => HealthDataAccess.READ_WRITE).toList();
      final granted = await _health.requestAuthorization(requiredTypes, permissions: permissions);
      debugPrint('[HealthSync] Authorization granted: $granted');
      return granted;
    } catch (e) {
      debugPrint('[HealthSync] Permission request failed: $e');
      return false;
    }
  }

  Future<bool> exportSleepSession(SleepSession session) async {
    try {
      final authorized = await requestPermissions();
      if (!authorized) {
        debugPrint('[HealthSync] Cannot export session without permissions');
        return false;
      }

      // 1. Export Total Sleep Session Interval
      await _health.writeHealthData(
        value: 0.0,
        type: HealthDataType.SLEEP_SESSION,
        startTime: session.startTime,
        endTime: session.endTime,
      );

      // 2. Export Resting Heart Rate
      if (session.restingHr > 30 && session.restingHr < 220) {
        await _health.writeHealthData(
          value: session.restingHr,
          type: HealthDataType.RESTING_HEART_RATE,
          startTime: session.startTime,
          endTime: session.endTime,
        );
      }

      // 3. Export HRV (RMSSD)
      if (session.avgRmssd > 0) {
        await _health.writeHealthData(
          value: session.avgRmssd,
          type: HealthDataType.HEART_RATE_VARIABILITY_RMSSD,
          startTime: session.startTime,
          endTime: session.endTime,
        );
      }

      // 4. Export Sleep Epoch Stages
      final epochs = await _database.getSleepEpochs(session.id);
      for (final epoch in epochs) {
        final epochEnd = epoch.timestamp.add(const Duration(seconds: 30));
        HealthDataType? stageType;

        switch (epoch.stage) {
          case SleepStage.wake:
            stageType = HealthDataType.SLEEP_AWAKE;
            break;
          case SleepStage.rem:
            stageType = HealthDataType.SLEEP_REM;
            break;
          case SleepStage.light:
            stageType = HealthDataType.SLEEP_LIGHT;
            break;
          case SleepStage.deep:
            stageType = HealthDataType.SLEEP_DEEP;
            break;
        }

        if (stageType != null) {
          await _health.writeHealthData(
            value: 0.0,
            type: stageType,
            startTime: epoch.timestamp,
            endTime: epochEnd,
          );
        }
      }

      await _database.markSleepSessionSynced(session.id);
      debugPrint('[HealthSync] Successfully exported session ${session.id} to HealthKit / Health Connect');
      return true;
    } catch (e) {
      debugPrint('[HealthSync] Export session error: $e');
      return false;
    }
  }

  Future<int> syncAllUnsyncedSessions() async {
    final sessions = await _database.getSleepSessions(limit: 50);
    int syncedCount = 0;

    for (final s in sessions) {
      if (!s.syncedToHealth) {
        final ok = await exportSleepSession(s);
        if (ok) syncedCount++;
      }
    }
    return syncedCount;
  }
}
