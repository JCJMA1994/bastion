import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/env.dart';

/// Estilo gráfico del tablero. [auto] usa el que diga la configuración remota.
enum ArtStyle { auto, vector, sprites }

enum AnimationSpeed {
  normal(1),
  rapida(2.5),
  ninguna(0);

  const AnimationSpeed(this.factor);

  /// Multiplicador de velocidad; 0 = sin animaciones.
  final double factor;
}

/// Ajustes del jugador, guardados en el dispositivo.
class SettingsController extends ChangeNotifier {
  SettingsController(this._prefs) {
    _soundOn = _prefs.getBool(_soundKey) ?? true;
    _volume = _prefs.getDouble(_volumeKey) ?? 0.8;
    _speed = AnimationSpeed.values
            .where((s) => s.name == _prefs.getString(_speedKey))
            .firstOrNull ??
        AnimationSpeed.normal;
    _largeText = _prefs.getBool(_largeTextKey) ?? false;
    _boardAsText = _prefs.getBool(_boardTextKey) ?? false;
    _serverUrl = _prefs.getString(_serverKey) ?? defaultServerUrl;
    _consentDecided = _prefs.getBool(_consentDecidedKey) ?? false;
    _diagnostics = _prefs.getBool(_diagnosticsKey) ?? false;
    _analytics = _prefs.getBool(_analyticsKey) ?? false;
    _artStyle = ArtStyle.values
            .where((s) => s.name == _prefs.getString(_artStyleKey))
            .firstOrNull ??
        ArtStyle.auto;
  }

  static Future<SettingsController> open() async =>
      SettingsController(await SharedPreferences.getInstance());

  /// Servidor del entorno de compilación (ver `env/`).
  static const defaultServerUrl = Env.serverUrl;

  static const _soundKey = 'bastion.settings.sound';
  static const _volumeKey = 'bastion.settings.volume';
  static const _speedKey = 'bastion.settings.speed';
  static const _largeTextKey = 'bastion.settings.largeText';
  static const _boardTextKey = 'bastion.settings.boardAsText';
  static const _serverKey = 'bastion.settings.server';
  static const _consentDecidedKey = 'bastion.privacy.decided';
  static const _diagnosticsKey = 'bastion.privacy.diagnostics';
  static const _analyticsKey = 'bastion.privacy.analytics';
  static const _artStyleKey = 'bastion.settings.artStyle';

  final SharedPreferences _prefs;

  late bool _soundOn;
  late double _volume;
  late AnimationSpeed _speed;
  late bool _largeText;
  late bool _boardAsText;
  late String _serverUrl;
  late bool _consentDecided;
  late bool _diagnostics;
  late bool _analytics;
  late ArtStyle _artStyle;

  /// Se aplica a partir de la próxima batalla.
  ArtStyle get artStyle => _artStyle;

  set artStyle(ArtStyle value) {
    _artStyle = value;
    _prefs.setString(_artStyleKey, value.name);
    notifyListeners();
  }

  /// El jugador ya respondió a la petición de consentimiento.
  bool get consentDecided => _consentDecided;

  /// Enviar errores y registros técnicos al servidor.
  bool get diagnosticsConsent => _diagnostics;

  /// Enviar estadísticas de uso anónimas al servidor.
  bool get analyticsConsent => _analytics;

  void setConsent({required bool diagnostics, required bool analytics}) {
    _consentDecided = true;
    _diagnostics = diagnostics;
    _analytics = analytics;
    _prefs
      ..setBool(_consentDecidedKey, true)
      ..setBool(_diagnosticsKey, diagnostics)
      ..setBool(_analyticsKey, analytics);
    notifyListeners();
  }

  bool get soundOn => _soundOn;
  double get volume => _volume;
  AnimationSpeed get speed => _speed;
  bool get largeText => _largeText;

  /// Lista accesible del tablero, además del lienzo. Se activa sola con el
  /// lector de pantalla.
  bool get boardAsText => _boardAsText;
  String get serverUrl => _serverUrl;

  set soundOn(bool value) {
    _soundOn = value;
    _prefs.setBool(_soundKey, value);
    notifyListeners();
  }

  set volume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _prefs.setDouble(_volumeKey, _volume);
    notifyListeners();
  }

  set speed(AnimationSpeed value) {
    _speed = value;
    _prefs.setString(_speedKey, value.name);
    notifyListeners();
  }

  set largeText(bool value) {
    _largeText = value;
    _prefs.setBool(_largeTextKey, value);
    notifyListeners();
  }

  set boardAsText(bool value) {
    _boardAsText = value;
    _prefs.setBool(_boardTextKey, value);
    notifyListeners();
  }

  set serverUrl(String value) {
    _serverUrl = value.trim();
    _prefs.setString(_serverKey, _serverUrl);
    notifyListeners();
  }
}
