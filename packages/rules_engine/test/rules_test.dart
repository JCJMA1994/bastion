import 'package:rules_engine/rules_engine.dart';
import 'package:test/test.dart';

void main() {
  group('woundTarget', () {
    test('F igual a RES hiere con 4+', () => expect(woundTarget(3, 3), 4));
    test('F doble de RES hiere con 2+', () => expect(woundTarget(6, 3), 2));
    test('F mayor que RES hiere con 3+', () => expect(woundTarget(4, 3), 3));
    test('F menor que RES hiere con 5+', () => expect(woundTarget(3, 4), 5));
    test('F mitad de RES hiere con 6+', () => expect(woundTarget(3, 6), 6));
  });

  test('cobertura y Desmoralizado se limitan a -1 en total', () {
    expect(clampModifier(-1 + -1), -1);
    expect(clampModifier(1 + 1), 1);
  });

  group('tiradas naturales', () {
    test('un 1 falla aunque PUN 2+ con +1',
        () => expect(rollSucceeds(1, 2, modifier: 1), isFalse));
    test('un 6 impacta con -1',
        () => expect(rollSucceeds(6, 6, modifier: -1), isTrue));
  });

  group('saveTarget', () {
    test('SAL 3+ contra PA 2 salva con 5+', () => expect(saveTarget(3, 2), 5));
    test('SAL 5+ contra PA 2 no salva nunca',
        () => expect(saveTarget(5, 2), isNull));
    test('atrincherada mejora la salvación en 1',
        () => expect(saveTarget(5, 0, bonus: 1), 4));
  });

  group('rangos', () {
    test('umbrales de veteranía', () {
      expect(rankFor(1), Rank.recluta);
      expect(rankFor(2), Rank.regular);
      expect(rankFor(5), Rank.veterana);
      expect(rankFor(9), Rank.elite);
    });
  });
}
