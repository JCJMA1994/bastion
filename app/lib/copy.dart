import 'package:rules_engine/rules_engine.dart';

/// Textos de interfaz de la guía de copy. El motor solo devuelve códigos.
abstract final class Copy {
  static String rank(Rank rank) => switch (rank) {
        Rank.recluta => 'Recluta',
        Rank.regular => 'Regular',
        Rank.veterana => 'Veterana',
        Rank.elite => 'Élite',
      };

  static String order(OrderType order) => switch (order) {
        OrderType.repetid => '¡Repetid!',
        OrderType.avanceForzado => 'Avance forzado',
        OrderType.cuerpoATierra => 'Cuerpo a tierra',
        OrderType.arenga => 'Arenga',
        OrderType.fuegoCobertura => 'Fuego de cobertura',
        OrderType.contraataque => 'Contraataque',
        OrderType.fuegoConcentrado => 'Fuego concentrado',
        OrderType.doblePaso => 'Doble paso',
      };

  static String nodeKind(NodeKind kind) => switch (kind) {
        NodeKind.batalla => 'Batalla',
        NodeKind.suministros => 'Suministros',
        NodeKind.encuentro => 'Encuentro',
        NodeKind.fortin => 'Fortín',
      };

  static String mission(String id) => switch (id) {
        'dominio' => 'Dominio: controla objetivos durante 5 rondas',
        'defensa_vado' => 'Defensa del vado: defiende el puente 4 rondas',
        'reconocimiento' => 'Reconocimiento: descubre qué objetivos son reales',
        _ => id,
      };

  /// "Lanceros 2" para la segunda escuadra de Lanceros; el nombre solo si es
  /// la única.
  static String squadName(String id, String profileName) {
    final parts = id.split('_');
    final n = int.tryParse(parts.last);
    return n == null || n == 1 ? profileName : '$profileName $n';
  }

  static String effect(AppliedEffect e, String Function(String id) squadName) =>
      switch (e.type) {
        'requisas' => e.amount >= 0
            ? '+${e.amount} requisas'
            : '${e.amount} requisas',
        'orden' => 'Orden nueva en la mano',
        'curar' => 'La compañía se recupera por completo',
        'experiencia' =>
          '${squadName(e.squadId!)} gana ${e.amount} de experiencia',
        'bajas' => '${squadName(e.squadId!)} pierde ${e.amount} '
            '${e.amount == 1 ? 'soldado' : 'soldados'}',
        'azar_exito' => 'Sale bien.',
        'azar_fallo' => 'Sale mal.',
        _ => e.type,
      };

  static String violation(ViolationCode code) => switch (code) {
        ViolationCode.fueraDeAlcance => 'Fuera de alcance.',
        ViolationCode.sinVision => 'Sin visión: algo se interpone.',
        ViolationCode.solapamiento =>
          'No cabe ahí: las peanas no pueden solaparse.',
        ViolationCode.movimientoExcesivo =>
          'Demasiado lejos: el círculo muestra hasta dónde llega.',
        ViolationCode.coherencia =>
          'La escuadra se separa: cada soldado debe quedar a 2" de otro.',
        ViolationCode.trabadaEnCombate =>
          'Trabada en combate: solo puede combatir o retirarse.',
        ViolationCode.cargaSinContacto => 'No llega al contacto.',
        ViolationCode.escuadraYaActivada => 'Esa escuadra ya actuó esta ronda.',
        ViolationCode.lejosDeObjetivo => 'Acércate a 3" de un objetivo.',
        ViolationCode.puntosDeMandoInsuficientes => 'No tienes PM suficientes.',
        ViolationCode.ordenSinObjetivo =>
          'Selecciona una escuadra tuya válida para esa orden.',
        ViolationCode.ordenFueraDeMomento => 'Esa orden se juega antes de mover.',
        ViolationCode.movioAntesDeDisparar =>
          'El cañón no puede mover y disparar.',
        ViolationCode.desmoralizada => 'Desmoralizada: no puede hacer eso.',
        ViolationCode.fueraDeZona => 'Fuera de tu zona de despliegue.',
        ViolationCode.fueraDelTablero => 'Fuera del tablero.',
        ViolationCode.nadaQueDeshacer =>
          'No hay movimiento que deshacer (o ya hubo disparos).',
        ViolationCode.sinArmaParaVigilar =>
          'Esta escuadra no tiene un arma con la que vigilar.',
        _ => 'No se puede hacer eso ahora.',
      };

  /// Porcentaje en formato español: "35 %" → "35%"; menos de 1 → "<1%".
  static String pct(double p) {
    if (p > 0 && p < 0.01) return '<1%';
    if (p < 1 && p > 0.99) return '>99%';
    return '${(p * 100).round()}%';
  }

  /// Número con coma decimal: 1.25 → "1,3".
  static String dec(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  /// "4+" con el modificador, si lo hay: "4+ (−1)".
  static String target(int? on, {int modifier = 0}) {
    if (on == null) return 'automático';
    if (modifier == 0) return '$on+';
    return '$on+ (${modifier > 0 ? '+' : '−'}${modifier.abs()})';
  }
}
