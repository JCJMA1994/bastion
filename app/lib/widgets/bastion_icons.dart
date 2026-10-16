import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Set de iconos del design system: trazo de 2px en rejilla de 24px,
/// extremos y uniones redondeados. Toman el color que se les pase.
enum BastionIcons {
  mover('<path d="M4 12h14M13 6l6 6-6 6"/>'),
  disparar('<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2"/>'
      '<path d="M12 2v3M12 19v3M2 12h3M19 12h3"/>'),
  cargar('<path d="M4 6l6 6-6 6M12 6l6 6-6 6"/>'),
  asegurar('<path d="M6 21V4h11l-2.5 4 2.5 4H6"/>'),
  atrincherar('<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6z"/>'),
  cobertura('<path d="M3 20V9h18v11M3 14.5h18M9 9v5.5M15 14.5V20"/>'),
  elevado('<path d="M12 16V4M7 9l5-5 5 5M4 20h16"/>'),
  moral('<path d="M6 21V3M6 4h12l-3 4 3 4H6"/><path d="M10 7v2"/>'),
  dados('<rect x="3.5" y="3.5" width="17" height="17" rx="3"/>'
      '<circle cx="8.5" cy="8.5" r="1.2" fill="currentColor"/>'
      '<circle cx="15.5" cy="15.5" r="1.2" fill="currentColor"/>'
      '<circle cx="12" cy="12" r="1.2" fill="currentColor"/>'),
  ordenes('<rect x="4" y="6" width="12" height="15" rx="2"/>'
      '<path d="M8 3h10a2 2 0 0 1 2 2v12"/>'),
  objetivo('<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4"/>'),
  bajas('<circle cx="12" cy="12" r="9"/><path d="M9 9l6 6M15 9l-6 6"/>'),
  suministros('<path d="M3 8l9-5 9 5v8l-9 5-9-5z"/><path d="M3 8l9 5 9-5M12 13v8"/>'),
  encuentro('<circle cx="12" cy="12" r="9"/>'
      '<path d="M9.5 9a2.5 2.5 0 0 1 5 0c0 1.5-2.5 2-2.5 3.5M12 16.5v.5"/>'),
  ascenso('<path d="M12 19V5M6 11l6-6 6 6"/>'),
  descanso('<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>'),
  hecho('<path d="M5 12l5 5L20 7"/>'),
  volver('<path d="M15 18l-6-6 6-6"/>'),
  menu('<path d="M4 6h16M4 12h16M4 18h16"/>'),
  acercar('<path d="M12 5v14M5 12h14"/>'),
  alejar('<path d="M5 12h14"/>'),
  ajustar('<path d="M4 9V4h5M20 9V4h-5M4 15v5h5M20 15v5h-5"/>'),
  deshacer('<path d="M9 14L4 9l5-5"/><path d="M4 9h11a5 5 0 0 1 0 10h-3"/>'),
  vigilar('<path d="M2 12s3.5-6 10-6 10 6 10 6-3.5 6-10 6S2 12 2 12z"/>'
      '<circle cx="12" cy="12" r="2.5"/>');

  const BastionIcons(this.paths);

  final String paths;

  String get svg =>
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
      'stroke="currentColor" stroke-width="2" stroke-linecap="round" '
      'stroke-linejoin="round">$paths</svg>';
}

class BastionIcon extends StatelessWidget {
  const BastionIcon(this.icon,
      {super.key, this.size = 20, required this.color, this.semanticLabel});

  final BastionIcons icon;
  final double size;
  final Color color;

  /// Nulo para iconos decorativos acompañados de texto.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      icon.svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      semanticsLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
  }
}
