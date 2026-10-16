/// Entorno de compilación, fijado con
/// `--dart-define-from-file=../env/<entorno>.json` (ver `env/`).
enum AppEnv { dev, qa, prod }

abstract final class Env {
  static const name = String.fromEnvironment('ENV', defaultValue: 'dev');
  static const serverUrl =
      String.fromEnvironment('SERVER_URL', defaultValue: 'http://10.0.2.2:8080');

  /// Versión de la app; la fija CI con `--dart-define=APP_VERSION=…`.
  static const appVersion =
      String.fromEnvironment('APP_VERSION', defaultValue: '0.0.0-dev');
  static const telemetryEnabled =
      bool.fromEnvironment('TELEMETRY', defaultValue: true);

  static AppEnv get current =>
      AppEnv.values.where((e) => e.name == name).firstOrNull ?? AppEnv.dev;

  static bool get isProd => current == AppEnv.prod;
}

/// Compara versiones semánticas "1.2.3" (ignora sufijos como "-dev").
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final x = parts(a);
  final y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}
