# Arte de Bastión

`art/source/` contiene el arte fuente con la convención de la especificación
(ver el documento "Plan de arte: de vectores a sprites"). Ahora mismo es
**arte provisional** generado con `tool/art/make_placeholder_art.py` para
probar la tubería; el arte definitivo lo sustituye archivo por archivo.

## Flujo para incorporar arte

1. Copia los PNG del artista en `art/source/` respetando nombres y carpetas:
   - `troops/<faccion>/<perfil>_<estado>.png` y `..._mask.png`
   - `terrain/<tipo>/<pieza>.png` (ruinas, bosque, crater, muro_bajo, parapeto, objetivo)
   - `effects/<efecto>_<NN>.png` (fogonazo, humo, impacto, explosion)
   - `ground/<tema>.png`
2. Valida y empaqueta:

   ```bash
   tool/pack_art.sh        # = check_art.py + pack_art.py
   ```

   `check_art.py` avisa de piezas que faltan, tamaños, máscaras y nombres.
   `pack_art.py` genera los atlas WebP y el manifiesto en `app/assets/art/`.
3. Prueba en el móvil con Ajustes → Estilo gráfico → Ilustrado.
4. Si el cambio es intencionado, actualiza las capturas de referencia:

   ```bash
   cd app && flutter test --tags golden --update-goldens
   ```

`art/spec.json` es la especificación en datos: facciones, perfiles, estados,
lienzos, escalas y tamaño máximo de página. Si cambia la especificación, se
cambia ahí y el validador y el empaquetador la siguen.

Requisito: Python 3 con Pillow (`pip install pillow`).

## Decoración de los mapas

Cada área de terreno se decora sola con piezas elegidas de forma determinista
(el mismo mapa se ve igual en todos los dispositivos). Para colocarlas a mano,
añade al área una lista `decoracion` en `data/maps.json`:

```json
{"id": "molino", "tipo": "ruinas", "rect": [16, 3, 8, 6], "piso": true,
 "decoracion": [
   {"pieza": "ruinas/piso_alto", "x": 20, "y": 6, "escala": 1.8},
   {"pieza": "ruinas/escombros_2", "x": 23, "y": 4, "rot": 30}
 ]}
```

`x` e `y` en pulgadas del tablero, `rot` en grados. Es solo visual: el motor
de reglas la ignora (hay un test que lo comprueba). Los ids de área con
decoración a mano deben ser únicos entre mapas.
