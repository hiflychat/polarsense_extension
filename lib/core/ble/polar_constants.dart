class PolarConstants {
  /// Default accelerometer sampling rate for Polar Verity Sense sedentary & sleep detection
  /// Polar Verity Sense standard accelerometer streaming operates at 52 Hz
  static const int accSampleRate = 52;

  /// Accelerometer range in G (+-8G typical for arm movement)
  static const int accRange = 8;

  /// Normalization factor for Polar accelerometer millig (mg) values to g
  /// Polar Verity Sense returns values where 1000 mg = 1.0g
  static const double mgToG = 1.0 / 1000.0;

  /// Auto-reconnect configuration
  static const int maxReconnectAttempts = 5;
  static const Duration initialReconnectDelay = Duration(seconds: 2);
}
