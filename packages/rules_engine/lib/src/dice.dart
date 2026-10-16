/// Fuente de tiradas de d6. El motor nunca usa `dart:math.Random`
/// directamente: así las tiradas son reproducibles y se pueden guionizar en
/// los tests.
abstract interface class Dice {
  /// Devuelve un entero entre 1 y 6.
  int d6();
}

/// Generador xorshift32 con semilla. Solo usa desplazamientos, XOR y máscaras
/// de 32 bits, así que da la misma secuencia en la VM, en web y en el servidor.
final class SeededDice implements Dice {
  SeededDice(int seed) : _state = (seed & _mask) == 0 ? 0x9E3779B9 : seed & _mask;

  static const int _mask = 0xFFFFFFFF;

  /// Mayor múltiplo de 6 por debajo de 2^32. Los valores por encima se
  /// descartan para que el d6 no tenga sesgo.
  static const int _limit = 4294967292;

  int _state;

  int _next() {
    var x = _state;
    x ^= (x << 13) & _mask;
    x ^= x >>> 17;
    x ^= (x << 5) & _mask;
    _state = x & _mask;
    return _state;
  }

  @override
  int d6() {
    while (true) {
      final value = _next();
      if (value < _limit) return value % 6 + 1;
    }
  }
}

/// Dados con resultados fijados de antemano, para tests.
final class ScriptedDice implements Dice {
  ScriptedDice(Iterable<int> values) : _values = List.of(values);

  final List<int> _values;
  int _index = 0;

  /// Tiradas que aún no se han consumido.
  int get remaining => _values.length - _index;

  @override
  int d6() {
    if (_index >= _values.length) {
      throw StateError(
          'ScriptedDice sin valores: se pidieron más tiradas de las previstas.');
    }
    final value = _values[_index++];
    if (value < 1 || value > 6) {
      throw ArgumentError.value(value, 'value', 'Debe estar entre 1 y 6.');
    }
    return value;
  }
}

/// Índice uniforme en [0, n) usando dos d6 (n entre 1 y 36).
int rollIndex(Dice dice, int n) {
  if (n < 1 || n > 36) throw ArgumentError.value(n, 'n', 'Debe estar entre 1 y 36');
  while (true) {
    final value = (dice.d6() - 1) * 6 + (dice.d6() - 1);
    if (value < 36 - 36 % n) return value % n;
  }
}
