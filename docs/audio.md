# Audio de Bastión

Los efectos actuales (`app/assets/audio/*.wav`) están sintetizados con código y son **provisionales**. Este documento es la especificación para sustituirlos por sonido definitivo sin tocar el código: basta con reemplazar cada archivo manteniendo su nombre.

## Dirección

Sonido de mesa de guerra de principios del siglo XX: madera, latón y pólvora. Nada épico ni orquestal; seco, cercano y legible en el altavoz de un móvil. Un efecto nunca debe tapar al siguiente: duraciones cortas y colas que se apagan rápido.

## Lista de efectos

| Archivo | Cuándo suena | Duración | Referencia |
| --- | --- | --- | --- |
| `click.wav` | Botones principales | < 60 ms | Tic de madera seca |
| `dice.wav` | Cada ataque con dados | 300–500 ms | Puñado de dados de hueso sobre tapete |
| `shot.wav` | Ataque automático (lanzallamas) | 200–400 ms | Disparo de fusil antiguo, apagado |
| `cannon.wav` | Disparo de dispersión | 0,8–1,2 s | Cañón de campaña lejano, grave |
| `charge.wav` | Carga | 0,6–0,9 s | Corneta, 3–4 notas ascendentes |
| `order.wav` | Jugar una orden | 300–500 ms | Redoble corto de tambor |
| `objective.wav` | Puntúas un objetivo | 0,6–1 s | Campana pequeña |
| `morale.wav` | Una escuadra queda Desmoralizada | 0,6–0,9 s | Cuerno grave que cae |
| `victory.wav` | Fin de batalla, victoria | 1–1,5 s | Fanfarria breve de latón |
| `defeat.wav` | Fin de batalla, derrota | 1–1,5 s | Mismo motivo, descendente |

## Especificación técnica

- **Formato:** WAV PCM 16 bits, 44,1 kHz, mono (o OGG Vorbis si se cambia la extensión en `Sfx` de `lib/settings/sounds.dart`).
- **Volumen:** picos a −1 dBFS como máximo; sonoridad parecida entre efectos (en torno a −16 LUFS integrados) para que el control de volumen sea uniforme.
- **Inicio:** sin silencio al principio (el efecto se sincroniza con las animaciones).
- **Licencia:** solo material propio, encargado o con licencia que permita uso comercial sin atribución obligatoria en pantalla (por ejemplo, CC0). Guarda la licencia de cada archivo en `docs/audio-licencias.md`.

## Música (pendiente)

No hay música todavía. Propuesta: dos bucles de 60–90 s (mapa de campaña y batalla), percusión y metales sobrios, sin melodía protagonista, para no cansar en sesiones largas. Necesitaría un ajuste de volumen de música separado del de efectos.
