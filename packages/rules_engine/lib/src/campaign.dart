import 'battle_state.dart';
import 'battlefield.dart';
import 'profiles.dart';

enum Rank { recluta, regular, veterana, elite }

Rank rankFor(int experience) {
  if (experience >= 9) return Rank.elite;
  if (experience >= 5) return Rank.veterana;
  if (experience >= 2) return Rank.regular;
  return Rank.recluta;
}

/// Experiencia que gana una escuadra al terminar la batalla: +1 por
/// sobrevivir, +1 por cada escuadra enemiga destruida y +1 si controlaba un
/// objetivo. Una escuadra destruida no gana nada: cae.
int battleExperience(Squad squad, Battlefield field) {
  if (squad.destroyed) return 0;
  return 1 + squad.squadsDestroyed + (field.holdsObjective(squad) ? 1 : 0);
}

/// Perfil con las mejoras acumuladas por rango:
/// Regular +1 MOR; Veterana además PUN mejora en 1 (mínimo 2+);
/// Élite además +1 A en su arma principal (la primera de la lista).
UnitProfile rankedProfile(UnitProfile base, Rank rank) {
  if (rank == Rank.recluta) return base;
  var stats = base.stats.copyWith(mor: base.stats.mor + 1);
  if (rank.index >= Rank.veterana.index) {
    stats = stats.copyWith(pun: base.stats.pun > 2 ? base.stats.pun - 1 : 2);
  }
  var weapons = base.weapons;
  if (rank == Rank.elite && weapons.isNotEmpty) {
    weapons = [
      weapons.first.copyWith(attacks: weapons.first.attacks + 1),
      ...weapons.skip(1),
    ];
  }
  return base.copyWith(stats: stats, weapons: weapons);
}
