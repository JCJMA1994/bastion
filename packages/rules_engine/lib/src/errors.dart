/// Motivos por los que el motor rechaza un comando. La UI traduce cada código
/// a un texto de la guía de copy; el motor no contiene textos de interfaz.
enum ViolationCode {
  batallaNoIniciada,
  batallaTerminada,
  pasoIncorrecto,
  activacionEnCurso,
  sinActivacion,
  turnoDelOtroBando,
  escuadraDesconocida,
  escuadraDestruida,
  escuadraYaActivada,
  soldadoDesconocido,
  soldadoEliminado,
  yaMovio,
  accionYaRealizada,
  movimientoExcesivo,
  fueraDelTablero,
  solapamiento,
  coherencia,
  sinPisoElevado,
  retiradaInsuficiente,
  trabadaEnCombate,
  noTrabada,
  armaDesconocida,
  armaNoValida,
  objetivoRequerido,
  objetivoNoEnemigo,
  sinVision,
  fueraDeAlcance,
  movioAntesDeDisparar,
  desmoralizada,
  cargaSinContacto,
  lejosDeObjetivo,
  ordenNoDisponible,
  puntosDeMandoInsuficientes,
  ordenSinObjetivo,
  ordenFueraDeMomento,
  sinHabilidad,
  fueraDeZona,
  nadaQueDeshacer,
  sinArmaParaVigilar,
}

/// Comando inválido. El estado no cambia cuando se lanza.
final class RuleViolation implements Exception {
  const RuleViolation(this.code, [this.detail]);

  final ViolationCode code;

  /// Detalle técnico para depuración (no es texto de interfaz).
  final String? detail;

  @override
  String toString() =>
      'RuleViolation(${code.name}${detail == null ? '' : ': $detail'})';
}
