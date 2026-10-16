import 'dart:math' as math;

/// Punto o vector en pulgadas sobre el tablero.
final class Vec2 {
  const Vec2(this.x, this.y);

  final double x;
  final double y;

  Vec2 operator +(Vec2 other) => Vec2(x + other.x, y + other.y);
  Vec2 operator -(Vec2 other) => Vec2(x - other.x, y - other.y);
  Vec2 operator *(double k) => Vec2(x * k, y * k);

  double get length => math.sqrt(x * x + y * y);
  double distanceTo(Vec2 other) => (this - other).length;

  Map<String, Object?> toJson() => {'x': x, 'y': y};

  factory Vec2.fromJson(Map<String, Object?> json) =>
      Vec2((json['x']! as num).toDouble(), (json['y']! as num).toDouble());

  @override
  bool operator ==(Object other) =>
      other is Vec2 && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Vec2($x, $y)';
}

/// Una peana: centro y radio, en pulgadas.
typedef Disc = ({Vec2 center, double radius});

/// Distancia entre los bordes de dos peanas (0 si se tocan o solapan).
double edgeDistance(Disc a, Disc b) {
  final d = a.center.distanceTo(b.center) - a.radius - b.radius;
  return d < 0 ? 0 : d;
}

/// Menor distancia de borde a borde entre dos grupos de peanas.
double minEdgeDistance(Iterable<Disc> a, Iterable<Disc> b) {
  var best = double.infinity;
  for (final da in a) {
    for (final db in b) {
      final d = edgeDistance(da, db);
      if (d < best) best = d;
    }
  }
  return best;
}

/// Polígono simple (sin autointersecciones) en pulgadas.
final class Polygon {
  Polygon(List<Vec2> points) : points = List.unmodifiable(points) {
    if (points.length < 3) {
      throw ArgumentError.value(
          points.length, 'points', 'Un polígono necesita al menos 3 vértices.');
    }
  }

  /// Rectángulo alineado con los ejes.
  factory Polygon.rect(double x, double y, double width, double height) =>
      Polygon([
        Vec2(x, y),
        Vec2(x + width, y),
        Vec2(x + width, y + height),
        Vec2(x, y + height),
      ]);

  final List<Vec2> points;

  /// Prueba de punto en polígono por cruce de rayos.
  bool contains(Vec2 p) {
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final a = points[i];
      final b = points[j];
      if ((a.y > p.y) != (b.y > p.y) &&
          p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Longitud del segmento [a]-[b] que queda dentro del polígono.
  double lengthInside(Vec2 a, Vec2 b) {
    final ts = <double>[0, 1];
    for (var i = 0; i < points.length; i++) {
      final t = _segmentIntersectionT(
          a, b, points[i], points[(i + 1) % points.length]);
      if (t != null) ts.add(t);
    }
    ts.sort();
    final d = b - a;
    final total = d.length;
    var inside = 0.0;
    for (var i = 0; i < ts.length - 1; i++) {
      final t0 = ts[i];
      final t1 = ts[i + 1];
      if (t1 - t0 < 1e-9) continue;
      if (contains(a + d * ((t0 + t1) / 2))) inside += (t1 - t0) * total;
    }
    return inside;
  }

  Map<String, Object?> toJson() =>
      {'points': [for (final p in points) p.toJson()]};
}

double? _segmentIntersectionT(Vec2 p, Vec2 p2, Vec2 q, Vec2 q2) {
  final r = p2 - p;
  final s = q2 - q;
  final denom = _cross(r, s);
  if (denom.abs() < 1e-12) return null;
  final qp = q - p;
  final t = _cross(qp, s) / denom;
  final u = _cross(qp, r) / denom;
  if (t < 0 || t > 1 || u < 0 || u > 1) return null;
  return t;
}

double _cross(Vec2 a, Vec2 b) => a.x * b.y - a.y * b.x;
