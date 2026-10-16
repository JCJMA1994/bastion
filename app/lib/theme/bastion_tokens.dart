import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tokens del design system Bastión (tema "Noche de campaña").
abstract final class BastionColors {
  static const mesa900 = Color(0xFF101316);
  static const mesa800 = Color(0xFF171B20);
  static const mesa700 = Color(0xFF1F242B);
  static const mesa600 = Color(0xFF2C333C);
  static const mesa500 = Color(0xFF3D4652);
  static const tinta = Color(0xFFEEEAE2);
  static const tintaSuave = Color(0xFFA9B0B8);
  static const laton = Color(0xFFE3A33B);
  static const latonTinta = Color(0xFF1A1206);
  static const latonClaro = Color(0xFFFFD9A0);
  static const latonVelo = Color(0xFF2B2216);
  static const cobalto = Color(0xFF6AA6F8);
  static const campo = Color(0xFF2A3027);
  static const terrenoRuina = Color(0xFF7A6C5A);
  static const terrenoBosque = Color(0xFF4B6847);
  static const exito = Color(0xFF6CC08A);
  static const peligro = Color(0xFFEF7766);
}

abstract final class BastionSpace {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s6 = 24.0;
  static const toqueMin = 44.0;
}

abstract final class BastionRadius {
  static const s = 4.0;
  static const m = 8.0;
  static const l = 12.0;
}

/// Estilos de texto del design system.
abstract final class BastionText {
  static TextStyle seccion() => GoogleFonts.getFont('Big Shoulders Display',
      fontSize: 24, height: 28 / 24, fontWeight: FontWeight.w700,
      letterSpacing: 0.72, color: BastionColors.tinta);

  static TextStyle boton() => GoogleFonts.getFont('Big Shoulders Display',
      fontSize: 17, height: 20 / 17, fontWeight: FontWeight.w700,
      letterSpacing: 1.02, color: BastionColors.latonTinta);

  static TextStyle titulo() => GoogleFonts.getFont('IBM Plex Sans',
      fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w600,
      color: BastionColors.tinta);

  static TextStyle cuerpo() => GoogleFonts.getFont('IBM Plex Sans',
      fontSize: 14, height: 20 / 14, color: BastionColors.tinta);

  static TextStyle detalle() => GoogleFonts.getFont('IBM Plex Sans',
      fontSize: 12, height: 16 / 12, color: BastionColors.tintaSuave);

  static TextStyle etiqueta() => GoogleFonts.getFont('IBM Plex Sans',
      fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w600,
      letterSpacing: 0.88, color: BastionColors.tintaSuave);

  static TextStyle cifra() => GoogleFonts.getFont('IBM Plex Mono',
      fontSize: 16, height: 20 / 16, fontWeight: FontWeight.w600,
      color: BastionColors.tinta);
}
