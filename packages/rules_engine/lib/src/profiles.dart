import 'errors.dart';

enum Role {
  mando,
  linea,
  apoyo,
  asalto,
  caballeria,
  artilleria;

  bool get isInfantry => this != caballeria && this != artilleria;
}

/// Cómo resuelve un arma la fase de impactar.
enum HitMode {
  /// Tira contra la PUN de la escuadra (o el "Impacta" del arma CaC).
  normal,

  /// Impacta sin tirar e ignora la cobertura (lanzallamas).
  automatico,

  /// Disparo de dispersión a un punto (cañón).
  dispersion,
}

/// Identificadores de habilidades de perfil.
abstract final class Abilities {
  static const vozDeMando = 'voz_de_mando';
  static const firmes = 'firmes';
  static const infiltracion = 'infiltracion';
  static const ojoDeHalcon = 'ojo_de_halcon';
  static const asalto = 'asalto';
  static const fortificar = 'fortificar';
  static const cargaDevastadora = 'carga_devastadora';
  static const disparoDispersion = 'disparo_dispersion';
}

final class Stats {
  const Stats({
    required this.mov,
    required this.pun,
    required this.res,
    required this.sal,
    required this.her,
    required this.mor,
  });

  factory Stats.fromJson(Map<String, Object?> json) => Stats(
        mov: _int(json, 'mov'),
        pun: _int(json, 'pun'),
        res: _int(json, 'res'),
        sal: _int(json, 'sal'),
        her: _int(json, 'her'),
        mor: _int(json, 'mor'),
      );

  Stats copyWith({int? mov, int? pun, int? res, int? sal, int? her, int? mor}) =>
      Stats(
        mov: mov ?? this.mov,
        pun: pun ?? this.pun,
        res: res ?? this.res,
        sal: sal ?? this.sal,
        her: her ?? this.her,
        mor: mor ?? this.mor,
      );

  /// Movimiento en pulgadas.
  final int mov;

  /// Puntería: impacta a distancia con este valor o más.
  final int pun;

  /// Resistencia.
  final int res;

  /// Salvación: salva con este valor o más.
  final int sal;

  /// Heridas por soldado.
  final int her;

  /// Moral: se supera un chequeo con 2d6 menor o igual a este valor.
  final int mor;
}

final class Weapon {
  const Weapon({
    required this.id,
    required this.name,
    required this.range,
    required this.attacks,
    required this.strength,
    required this.ap,
    required this.damage,
    this.meleeHit,
    this.mode = HitMode.normal,
  });

  factory Weapon.fromJson(Map<String, Object?> json) {
    final weapon = Weapon(
      id: _string(json, 'id'),
      name: _string(json, 'nombre'),
      range: _int(json, 'alcance'),
      meleeHit: (json['impacta'] as num?)?.toInt(),
      attacks: _int(json, 'a'),
      strength: _int(json, 'f'),
      ap: _int(json, 'pa'),
      damage: _int(json, 'd'),
      mode: HitMode.values.byName((json['modo'] as String?) ?? 'normal'),
    );
    if (weapon.isMelee && weapon.meleeHit == null) {
      throw FormatException('El arma CaC "${weapon.id}" no tiene "impacta".');
    }
    return weapon;
  }

  Weapon copyWith({int? attacks}) => Weapon(
        id: id,
        name: name,
        range: range,
        meleeHit: meleeHit,
        attacks: attacks ?? this.attacks,
        strength: strength,
        ap: ap,
        damage: damage,
        mode: mode,
      );

  /// Arma de cuerpo a cuerpo para escuadras que no tienen ninguna.
  static const improvised = Weapon(
    id: 'culata',
    name: 'Culata',
    range: 0,
    meleeHit: 5,
    attacks: 1,
    strength: 3,
    ap: 0,
    damage: 1,
  );

  final String id;
  final String name;

  /// Alcance en pulgadas. 0 significa cuerpo a cuerpo.
  final int range;

  /// Valor de impacto de las armas CaC.
  final int? meleeHit;
  final int attacks;
  final int strength;
  final int ap;
  final int damage;
  final HitMode mode;

  bool get isMelee => range == 0;
}

final class UnitProfile {
  const UnitProfile({
    required this.id,
    required this.name,
    required this.role,
    required this.soldiers,
    required this.stats,
    required this.weapons,
    this.abilities = const {},
    this.cost,
    this.unique = false,
  });

  factory UnitProfile.fromJson(Map<String, Object?> json) => UnitProfile(
        id: _string(json, 'id'),
        name: _string(json, 'nombre'),
        role: Role.values.byName(_string(json, 'rol')),
        soldiers: _int(json, 'soldados'),
        stats: Stats.fromJson(_map(json, 'stats')),
        weapons: [
          for (final w in _list(json, 'armas'))
            Weapon.fromJson(w as Map<String, Object?>),
        ],
        abilities: {
          for (final a in (json['habilidades'] as List<Object?>?) ?? const [])
            a as String,
        },
        cost: (json['coste'] as num?)?.toInt(),
        unique: (json['unica'] as bool?) ?? false,
      );

  final String id;
  final String name;
  final Role role;
  final int soldiers;
  final Stats stats;
  final List<Weapon> weapons;
  final Set<String> abilities;

  /// Coste en requisas. Nulo en perfiles únicos.
  final int? cost;
  final bool unique;

  bool has(String ability) => abilities.contains(ability);

  UnitProfile copyWith({Stats? stats, List<Weapon>? weapons}) => UnitProfile(
        id: id,
        name: name,
        role: role,
        soldiers: soldiers,
        stats: stats ?? this.stats,
        weapons: weapons ?? this.weapons,
        abilities: abilities,
        cost: cost,
        unique: unique,
      );

  Weapon get meleeWeapon {
    for (final w in weapons) {
      if (w.isMelee) return w;
    }
    return Weapon.improvised;
  }

  Weapon weaponById(String weaponId) => weapons.firstWhere(
        (w) => w.id == weaponId,
        orElse: () => throw RuleViolation(ViolationCode.armaDesconocida, weaponId),
      );
}

/// Catálogo de perfiles cargado desde `data/units.json`.
final class ProfileCatalog {
  ProfileCatalog(Iterable<UnitProfile> profiles)
      : _byId = {for (final p in profiles) p.id: p};

  factory ProfileCatalog.fromJson(Map<String, Object?> json) => ProfileCatalog([
        for (final p in _list(json, 'profiles'))
          UnitProfile.fromJson(p as Map<String, Object?>),
      ]);

  final Map<String, UnitProfile> _byId;

  Iterable<UnitProfile> get all => _byId.values;

  UnitProfile operator [](String id) =>
      _byId[id] ?? (throw ArgumentError.value(id, 'id', 'Perfil desconocido'));
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException('Falta el entero "$key".');
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String) return value;
  throw FormatException('Falta el texto "$key".');
}

Map<String, Object?> _map(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is Map<String, Object?>) return value;
  throw FormatException('Falta el objeto "$key".');
}

List<Object?> _list(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is List<Object?>) return value;
  throw FormatException('Falta la lista "$key".');
}
