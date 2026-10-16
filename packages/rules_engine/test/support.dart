import 'package:rules_engine/rules_engine.dart';

const rifle = Weapon(
    id: 'fusil', name: 'Fusil', range: 24, attacks: 1, strength: 3, ap: 0, damage: 1);
const bayonet = Weapon(
    id: 'bayoneta',
    name: 'Bayoneta',
    range: 0,
    meleeHit: 4,
    attacks: 1,
    strength: 3,
    ap: 0,
    damage: 1);

/// Perfil de prueba sin habilidades, para que los modificadores no interfieran.
const lineProfile = UnitProfile(
  id: 'linea_test',
  name: 'Línea',
  role: Role.linea,
  soldiers: 5,
  stats: Stats(mov: 6, pun: 4, res: 3, sal: 5, her: 1, mor: 7),
  weapons: [rifle, bayonet],
);

const cannonProfile = UnitProfile(
  id: 'canon_test',
  name: 'Cañón',
  role: Role.artilleria,
  soldiers: 1,
  stats: Stats(mov: 3, pun: 4, res: 6, sal: 3, her: 4, mor: 7),
  weapons: [
    Weapon(
        id: 'canon',
        name: 'Cañón',
        range: 36,
        attacks: 1,
        strength: 6,
        ap: 2,
        damage: 2,
        mode: HitMode.dispersion),
  ],
);

/// [n] posiciones en columna desde ([x], [y]), separadas 1,5" (peanas de 1").
List<Vec2> column(double x, double y, int n) =>
    [for (var i = 0; i < n; i++) Vec2(x, y + i * 1.5)];

Squad squad(String id, Side side, List<Vec2> positions,
        {UnitProfile profile = lineProfile}) =>
    Squad.deploy(id: id, side: side, profile: profile, positions: positions);

/// Iniciativa para el jugador cuando los PV están empatados: 6 contra 1.
const playerFirst = [6, 1];

const sapperProfile = UnitProfile(
  id: 'zapadores_test',
  name: 'Zapadores',
  role: Role.apoyo,
  soldiers: 3,
  stats: Stats(mov: 5, pun: 4, res: 4, sal: 4, her: 1, mor: 7),
  weapons: [bayonet],
  abilities: {Abilities.fortificar},
);

/// Crea una batalla y ejecuta su inicio (Mando de la ronda 1).
BattleEngine startBattle(
  List<Squad> squads,
  Dice dice, {
  Board board = const Board(),
  Mission? mission,
  Map<Side, List<OrderType>>? hands,
}) {
  final engine = BattleEngine(
    state: BattleState(
        board: board, squads: squads, mission: mission, hands: hands),
    dice: dice,
  );
  engine.start();
  return engine;
}

/// Objetivos de las posiciones estándar del MVP.
const standardObjectives = [
  Objective(id: 'o1', position: Vec2(5, 4)),
  Objective(id: 'o2', position: Vec2(5, 24)),
  Objective(id: 'o3', position: Vec2(22, 14)),
  Objective(id: 'o4', position: Vec2(39, 4)),
  Objective(id: 'o5', position: Vec2(39, 24)),
];
