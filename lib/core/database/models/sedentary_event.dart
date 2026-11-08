class SedentaryEvent {
  final int? id;
  final DateTime startTime;
  final DateTime endTime;
  final int durationMinutes;
  final bool triggeredAlert;
  final bool resolvedByWalking;

  SedentaryEvent({
    this.id,
    required this.startTime,
    required this.endTime,
    required this.durationMinutes,
    required this.triggeredAlert,
    required this.resolvedByWalking,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'startTime': startTime.millisecondsSinceEpoch,
      'endTime': endTime.millisecondsSinceEpoch,
      'durationMinutes': durationMinutes,
      'triggeredAlert': triggeredAlert ? 1 : 0,
      'resolvedByWalking': resolvedByWalking ? 1 : 0,
    };
  }

  factory SedentaryEvent.fromMap(Map<String, dynamic> map) {
    return SedentaryEvent(
      id: map['id'] as int?,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['startTime'] as int),
      endTime: DateTime.fromMillisecondsSinceEpoch(map['endTime'] as int),
      durationMinutes: map['durationMinutes'] as int,
      triggeredAlert: (map['triggeredAlert'] as int) == 1,
      resolvedByWalking: (map['resolvedByWalking'] as int) == 1,
    );
  }
}

class DailySedentarySummary {
  final DateTime date;
  final int totalSedentaryMinutes;
  final int totalActiveMinutes;
  final int alertCount;

  DailySedentarySummary({
    required this.date,
    required this.totalSedentaryMinutes,
    required this.totalActiveMinutes,
    required this.alertCount,
  });

  double get sedentaryHours => totalSedentaryMinutes / 60.0;
  double get activeHours => totalActiveMinutes / 60.0;
}
