import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'models/sleep_record.dart';
import 'models/sedentary_event.dart';

class HealthDatabase {
  static final HealthDatabase _instance = HealthDatabase._internal();
  factory HealthDatabase() => _instance;
  HealthDatabase._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'polarsense_health.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE sleep_sessions ADD COLUMN dataSource TEXT NOT NULL DEFAULT 'live_acc_ppi'",
      );
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE sleep_sessions (
        id TEXT PRIMARY KEY,
        startTime INTEGER NOT NULL,
        endTime INTEGER NOT NULL,
        durationMinutes INTEGER NOT NULL,
        wakeMinutes INTEGER NOT NULL,
        remMinutes INTEGER NOT NULL,
        lightMinutes INTEGER NOT NULL,
        deepMinutes INTEGER NOT NULL,
        restingHr REAL NOT NULL,
        avgRmssd REAL NOT NULL,
        recoveryScore INTEGER NOT NULL,
        syncedToHealth INTEGER NOT NULL DEFAULT 0,
        dataSource TEXT NOT NULL DEFAULT 'live_acc_ppi'
      )
    ''');

    await db.execute('''
      CREATE TABLE sleep_epochs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        sessionId TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        stage INTEGER NOT NULL,
        meanHr REAL NOT NULL,
        rmssd REAL NOT NULL,
        movementIndex REAL NOT NULL,
        FOREIGN KEY (sessionId) REFERENCES sleep_sessions(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_sleep_epochs_session ON sleep_epochs(sessionId, timestamp)
    ''');

    await db.execute('''
      CREATE TABLE sedentary_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        startTime INTEGER NOT NULL,
        endTime INTEGER NOT NULL,
        durationMinutes INTEGER NOT NULL,
        triggeredAlert INTEGER NOT NULL,
        resolvedByWalking INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE user_baselines (
        date TEXT PRIMARY KEY,
        rolling14DayRmssd REAL NOT NULL,
        restingHr REAL NOT NULL
      )
    ''');
  }

  // --- Sleep Session Operations ---

  Future<void> insertSleepSession(SleepSession session) async {
    final db = await database;
    await db.insert(
      'sleep_sessions',
      session.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertSleepEpochs(List<SleepEpoch> epochs) async {
    if (epochs.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final epoch in epochs) {
      batch.insert('sleep_epochs', epoch.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<List<SleepSession>> getSleepSessions({int limit = 30}) async {
    final db = await database;
    final maps = await db.query(
      'sleep_sessions',
      orderBy: 'startTime DESC',
      limit: limit,
    );
    return maps.map((m) => SleepSession.fromMap(m)).toList();
  }

  Future<SleepSession?> getLatestSleepSession() async {
    final list = await getSleepSessions(limit: 1);
    return list.isNotEmpty ? list.first : null;
  }

  Future<List<SleepEpoch>> getSleepEpochs(String sessionId) async {
    final db = await database;
    final maps = await db.query(
      'sleep_epochs',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
    return maps.map((m) => SleepEpoch.fromMap(m)).toList();
  }

  Future<void> markSleepSessionSynced(String sessionId) async {
    final db = await database;
    await db.update(
      'sleep_sessions',
      {'syncedToHealth': 1},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> deleteSleepSession(String sessionId) async {
    final db = await database;
    await db.delete(
      'sleep_epochs',
      where: 'sessionId = ?',
      whereArgs: [sessionId],
    );
    await db.delete(
      'sleep_sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  // --- Baseline HRV & RHR Queries ---

  /// Returns 14-day rolling baseline RMSSD from qualifying overnight sessions (>= 120 min)
  /// that contain genuine beat-to-beat PPI HRV measurements (excludes HR-only offline proxies).
  Future<double> get14DayBaselineRmssd() async {
    final db = await database;
    final maps = await db.query(
      'sleep_sessions',
      columns: ['avgRmssd'],
      where: "durationMinutes >= 120 AND avgRmssd > 0 AND dataSource != ?",
      whereArgs: [SleepSession.sourceOfflineHrOnly],
      orderBy: 'startTime DESC',
      limit: 14,
    );

    if (maps.isEmpty) {
      return 42.0; // Default population resting RMSSD in ms
    }

    double sum = 0.0;
    for (final m in maps) {
      sum += (m['avgRmssd'] as num).toDouble();
    }
    return sum / maps.length;
  }

  /// Returns 14-day rolling baseline resting HR from qualifying sleep sessions (>= 120 min).
  Future<double> getBaselineRestingHr() async {
    final db = await database;
    final maps = await db.query(
      'sleep_sessions',
      columns: ['restingHr'],
      where: 'durationMinutes >= 120 AND restingHr > 30',
      orderBy: 'startTime DESC',
      limit: 14,
    );

    if (maps.isEmpty) {
      return 60.0; // Default resting HR bpm
    }

    double sum = 0.0;
    for (final m in maps) {
      sum += (m['restingHr'] as num).toDouble();
    }
    return sum / maps.length;
  }

  // --- Sedentary Events Operations ---

  Future<void> insertSedentaryEvent(SedentaryEvent event) async {
    final db = await database;
    await db.insert('sedentary_events', event.toMap());
  }

  Future<DailySedentarySummary> getDailySedentarySummary(DateTime day) async {
    final db = await database;
    final startOfDay = DateTime(day.year, day.month, day.day).millisecondsSinceEpoch;
    final endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59, 999).millisecondsSinceEpoch;

    final maps = await db.query(
      'sedentary_events',
      where: 'startTime >= ? AND startTime <= ?',
      whereArgs: [startOfDay, endOfDay],
    );

    int totalSedentary = 0;
    int totalActive = 0;
    int alertCount = 0;

    for (final m in maps) {
      final duration = m['durationMinutes'] as int;
      final alerted = (m['triggeredAlert'] as int) == 1;
      final resolved = (m['resolvedByWalking'] as int) == 1;

      totalSedentary += duration;
      if (alerted) alertCount++;
      if (resolved) totalActive += 2; // ~2 min per walk break
    }

    return DailySedentarySummary(
      date: day,
      totalSedentaryMinutes: totalSedentary,
      totalActiveMinutes: totalActive,
      alertCount: alertCount,
    );
  }

  // --- App Key-Value Settings Operations ---

  Future<void> _ensureSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await _ensureSettingsTable(db);
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    await _ensureSettingsTable(db);
    final results = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (results.isNotEmpty) {
      return results.first['value'] as String?;
    }
    return null;
  }

  Future<void> removeSetting(String key) async {
    final db = await database;
    await _ensureSettingsTable(db);
    await db.delete(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
  }
}
