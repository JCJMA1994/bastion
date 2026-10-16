import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'settings_controller.dart';

enum Sfx {
  click('click.wav'),
  dice('dice.wav'),
  shot('shot.wav'),
  cannon('cannon.wav'),
  victory('victory.wav'),
  defeat('defeat.wav'),
  charge('charge.wav'),
  order('order.wav'),
  objective('objective.wav'),
  morale('morale.wav');

  const Sfx(this.file);
  final String file;
}

/// Efectos de sonido. Sin inicializar (por ejemplo, en los tests) no suena
/// nada: [instance] es un servicio mudo.
class Sounds {
  Sounds._(this._settings);

  static Sounds instance = Sounds._(null);

  /// Activa el sonido con los ajustes del jugador.
  static void init(SettingsController settings) =>
      instance = Sounds._(settings);

  final SettingsController? _settings;

  /// Varios reproductores para que los sonidos se puedan solapar.
  final List<AudioPlayer> _pool = [];
  int _next = 0;
  static const _poolSize = 4;

  void play(Sfx sfx, {Duration delay = Duration.zero}) {
    final settings = _settings;
    if (settings == null || !settings.soundOn || settings.volume == 0) return;
    if (delay == Duration.zero) {
      _play(sfx, settings.volume);
    } else {
      Future<void>.delayed(delay, () => _play(sfx, settings.volume));
    }
  }

  Future<void> _play(Sfx sfx, double volume) async {
    try {
      if (_pool.length < _poolSize) {
        _pool.add(AudioPlayer()..setReleaseMode(ReleaseMode.stop));
      }
      final player = _pool[_next % _pool.length];
      _next++;
      await player.stop();
      await player.play(AssetSource('audio/${sfx.file}'), volume: volume);
    } on Object catch (error) {
      // El sonido nunca debe romper la partida.
      debugPrint('Sonido no disponible: $error');
    }
  }
}
