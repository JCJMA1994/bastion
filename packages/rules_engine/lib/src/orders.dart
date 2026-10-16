/// Órdenes del MVP. Todas se juegan durante una activación propia, para no
/// interrumpir el turno del rival en móvil.
enum OrderType {
  /// En el próximo ataque de esta activación, repite el primer dado de
  /// impactar fallido.
  repetid('repetid', 1, OrderTarget.activa),

  /// La escuadra activa puede mover 3" más. Antes de mover.
  avanceForzado('avance_forzado', 1, OrderTarget.activa),

  /// Prepara una escuadra propia: +1 a la salvación contra el siguiente
  /// ataque a distancia que reciba antes de su próxima activación.
  cuerpoATierra('cuerpo_a_tierra', 1, OrderTarget.propia),

  /// Una escuadra propia deja de estar Desmoralizada.
  arenga('arenga', 1, OrderTarget.propiaDesmoralizada),

  /// Si el próximo disparo de esta activación impacta, el objetivo tiene
  /// -2" de MOV en su próxima activación.
  fuegoCobertura('fuego_cobertura', 1, OrderTarget.activa),

  /// Prepara una escuadra propia: si la cargan antes de su próxima
  /// activación, golpea primero.
  contraataque('contraataque', 2, OrderTarget.propia),

  /// +1 a herir en el próximo disparo de esta activación si el objetivo ya
  /// recibió disparos esta ronda.
  fuegoConcentrado('fuego_concentrado', 2, OrderTarget.activa),

  /// Al terminar esta activación, activas otra escuadra tuya enseguida.
  doblePaso('doble_paso', 2, OrderTarget.activa);

  const OrderType(this.id, this.cost, this.target);

  /// Identificador en `data/orders.json`.
  final String id;

  /// Coste en PM.
  final int cost;
  final OrderTarget target;

  static OrderType byId(String id) => values.firstWhere((o) => o.id == id,
      orElse: () => throw ArgumentError.value(id, 'id', 'Orden desconocida'));
}

enum OrderTarget {
  /// Afecta a la escuadra activa; no necesita objetivo.
  activa,

  /// Necesita una escuadra propia viva.
  propia,

  /// Necesita una escuadra propia Desmoralizada.
  propiaDesmoralizada,
}
