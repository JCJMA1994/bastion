import 'package:flutter/material.dart';

import '../theme/bastion_tokens.dart';
import 'bastion_icons.dart';

/// Barra superior de las pantallas.
class BastionTopBar extends StatelessWidget {
  const BastionTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: BastionSpace.s2),
      decoration: const BoxDecoration(
        color: BastionColors.mesa800,
        border: Border(bottom: BorderSide(color: BastionColors.mesa600)),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              onPressed: onBack,
              tooltip: 'Volver',
              icon: const BastionIcon(BastionIcons.volver,
                  color: BastionColors.tinta),
            )
          else
            const SizedBox(width: BastionSpace.s2),
          Text(title, style: BastionText.seccion()),
          if (subtitle != null) ...[
            const SizedBox(width: BastionSpace.s3),
            Flexible(
              child: Text(subtitle!,
                  style: BastionText.detalle(), overflow: TextOverflow.ellipsis),
            ),
          ],
          const Spacer(),
          if (trailing != null) trailing!,
          const SizedBox(width: BastionSpace.s2),
        ],
      ),
    );
  }
}

class BastionPanel extends StatelessWidget {
  const BastionPanel({super.key, required this.child, this.highlighted = false});

  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(BastionSpace.s3),
      decoration: BoxDecoration(
        color: highlighted ? BastionColors.latonVelo : BastionColors.mesa700,
        border: Border.all(
            color: highlighted ? BastionColors.laton : BastionColors.mesa600),
        borderRadius: BorderRadius.circular(BastionRadius.m),
      ),
      child: child,
    );
  }
}

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        backgroundColor: BastionColors.laton,
        foregroundColor: BastionColors.latonTinta,
        disabledBackgroundColor: BastionColors.mesa800,
        disabledForegroundColor: BastionColors.tintaSuave,
        textStyle: BastionText.boton(),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BastionRadius.m)),
      ),
      child: Text(label),
    );
  }
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton(
      {super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final BastionIcons? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final child = icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              BastionIcon(icon!,
                  size: 18,
                  color: enabled ? BastionColors.tinta : BastionColors.tintaSuave),
              const SizedBox(width: BastionSpace.s2),
              Text(label),
            ],
          );
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, BastionSpace.toqueMin),
        foregroundColor: BastionColors.tinta,
        disabledForegroundColor: BastionColors.tintaSuave,
        backgroundColor: BastionColors.mesa700,
        side: const BorderSide(color: BastionColors.mesa500),
        textStyle: BastionText.cuerpo().copyWith(fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BastionRadius.m)),
      ),
      child: child,
    );
  }
}

/// Pastilla de rango o estado.
class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: strong ? BastionColors.latonVelo : BastionColors.mesa800,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text.toUpperCase(),
          style: BastionText.etiqueta().copyWith(
              color: strong ? BastionColors.latonClaro : BastionColors.tintaSuave)),
    );
  }
}
