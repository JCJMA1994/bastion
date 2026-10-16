import 'package:rules_engine/rules_engine.dart';
import 'package:rules_engine/src/combat.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  test('D 2 contra soldados de HER 1 no pasa el sobrante al siguiente', () {
    final target = squad('E', Side.enemigo, column(20, 5, 5));
    // impacta 6, hiere 6, salva 1 (falla)
    final resolver = CombatResolver(ScriptedDice([6, 6, 1]));
    final outcome = resolver.resolve(AttackSpec(
      target: target,
      attackCount: 1,
      hitTarget: 4,
      strength: 3,
      ap: 0,
      damage: 2,
    ));
    expect(outcome.killed, 1);
    expect(target.aliveCount, 4);
  });

  test('el daño va primero al soldado ya herido', () {
    final target = Squad(
      id: 'E',
      side: Side.enemigo,
      profile: lineProfile,
      soldiers: [
        Soldier(id: 'a', position: const Vec2(20, 5), wounds: 3),
        Soldier(id: 'b', position: const Vec2(20, 6.5), wounds: 1),
      ],
    );
    final resolver = CombatResolver(ScriptedDice([6, 6, 1]));
    resolver.resolve(AttackSpec(
      target: target,
      attackCount: 1,
      hitTarget: 4,
      strength: 3,
      ap: 0,
      damage: 1,
    ));
    expect(target.soldierById('b')!.alive, isFalse);
    expect(target.soldierById('a')!.wounds, 3);
  });

  test('sin salvación posible no se tira para salvar', () {
    final target = squad('E', Side.enemigo, column(20, 5, 2));
    final dice = ScriptedDice([6, 6]); // impacta, hiere; ninguna salvación
    final outcome = CombatResolver(dice).resolve(AttackSpec(
      target: target,
      attackCount: 1,
      hitTarget: 4,
      strength: 3,
      ap: 2, // SAL 5 + PA 2 = 7
      damage: 1,
    ));
    expect(outcome.unsaved, 1);
    expect(dice.remaining, 0);
  });
}
