/// Reglas puras de dados. Sin estado: fáciles de probar y de reutilizar en la
/// UI para mostrar probabilidades.
library;

/// Valor necesario para herir según F del arma contra RES del objetivo.
int woundTarget(int strength, int toughness) {
  if (strength >= toughness * 2) return 2;
  if (strength > toughness) return 3;
  if (strength == toughness) return 4;
  if (strength * 2 <= toughness) return 6;
  return 5;
}

/// Los modificadores a impactar se suman, pero el total queda entre -1 y +1.
int clampModifier(int total) => total.clamp(-1, 1).toInt();

/// Un 1 natural siempre falla y un 6 natural siempre tiene éxito.
bool rollSucceeds(int roll, int target, {int modifier = 0}) {
  if (roll == 1) return false;
  if (roll == 6) return true;
  return roll + modifier >= target;
}

/// Valor necesario para salvar, o nulo si no hay salvación posible (pasa de 6).
int? saveTarget(int save, int ap, {int bonus = 0}) {
  final target = save + ap - bonus;
  return target > 6 ? null : target;
}
