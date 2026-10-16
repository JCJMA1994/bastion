import 'package:rules_engine/rules_engine.dart';

import 'board_controller.dart';

/// Despliegue: el jugador elige una escuadra suya y toca el tablero para
/// colocarla dentro de su zona.
class DeploymentController extends BoardController {
  DeploymentController(this.state,
      {this.mySide = Side.jugador, this.hideOpponent = false})
      : _deployment = Deployment(state) {
    selectedSquadId = state.aliveSquadsOf(mySide).firstOrNull?.id;
  }

  @override
  final Side mySide;

  /// En multijugador no se ve dónde despliega el rival.
  final bool hideOpponent;

  @override
  bool isHidden(Squad squad) => hideOpponent && squad.side != mySide;

  /// Centro actual de cada escuadra propia, para enviarlo al servidor.
  Map<String, Vec2> get centers => {
        for (final s in ownSquads) s.id: s.centroid,
      };

  @override
  final BattleState state;
  final Deployment _deployment;

  @override
  String? selectedSquadId;
  ViolationCode? lastError;

  List<Squad> get ownSquads => state.aliveSquadsOf(mySide).toList();

  bool get isValid => Battlefield(state).invalidDeployments().isEmpty;

  @override
  void select(String squadId) {
    if (state.squadById(squadId).side != mySide) return;
    selectedSquadId = squadId;
    lastError = null;
    notifyListeners();
  }

  @override
  void tapBoard(Vec2 point) {
    final id = selectedSquadId;
    if (id == null) return;
    try {
      _deployment.place(state.squadById(id), point);
      lastError = null;
      // Pasa a la siguiente escuadra para agilizar el despliegue.
      final squads = ownSquads;
      final index = squads.indexWhere((s) => s.id == id);
      selectedSquadId = squads[(index + 1) % squads.length].id;
    } on RuleViolation catch (v) {
      lastError = v.code;
    }
    notifyListeners();
  }

  void autoDeploy() {
    _deployment.autoDeploy(mySide);
    lastError = null;
    notifyListeners();
  }
}
