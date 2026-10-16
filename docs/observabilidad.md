# Observabilidad: logs, errores, analítica y configuración remota

Todo pasa por el servidor de Bastión, sin servicios de terceros. La app usa interfaces (`TelemetrySink`, `RemoteConfig`), así que añadir Firebase u otro proveedor es escribir un adaptador más, no cambiar el juego.

## Cómo ver los logs

| Dónde | Qué ves | Cómo |
| --- | --- | --- |
| En el móvil | Últimos 500 registros del dispositivo (siempre, aunque no haya consentimiento) | Ajustes → Diagnóstico → Registro de la app. Se puede filtrar y copiar. |
| Consola de desarrollo | Todo, en tiempo real | `flutter run` imprime cada registro con el prefijo `[bastion]` en modo debug |
| Panel web | Registros de todas las instalaciones que dieron consentimiento | `https://<servidor>/admin` con `BASTION_ADMIN_TOKEN`: resumen de 24 h, errores frecuentes, eventos, versiones, victorias por perfil y tabla filtrable de registros |
| Línea de comandos | Lo mismo que el panel, en JSON | `curl -H "Authorization: Bearer $TOKEN" "https://<servidor>/admin/logs?kind=error&hours=24"` |
| Disco del servidor | Histórico completo | `telemetria/telemetria-AAAA-MM-DD.jsonl`, una línea JSON por registro |

Filtros de `/admin/logs`: `kind` (log, error, event), `level`, `env`, `q` (texto), `install`, `hours`, `limit` (hasta 1000).

## Privacidad

- En el primer arranque se pide consentimiento con las dos opciones **desactivadas**: informes de errores y estadísticas de uso. Se puede cambiar en Ajustes → Privacidad.
- Sin consentimiento no sale nada del dispositivo. Al retirarlo se descarta lo que quedaba en cola.
- Se envía un identificador aleatorio de instalación, nunca datos personales. Los textos de error se recortan.
- Antes de publicar, añade esto a la política de privacidad y revisa los requisitos de tu país (en la UE, RGPD).

## Niveles de log

`debug` (solo desarrollo), `info`, `warning` y `error`. En prod el nivel mínimo lo marca la configuración remota (`log_level`); en dev y qa se registra todo.

Los errores no controlados se capturan con `FlutterError.onError` y `PlatformDispatcher.instance.onError`, con las 15 primeras líneas de la pila.

## Catálogo de eventos

| Evento | Parámetros | Para qué |
| --- | --- | --- |
| `app_open` | env, version | Instalaciones activas y adopción de versiones |
| `screen_view` | screen | Embudo de navegación |
| `campaign_start` | requisas | Campañas empezadas |
| `node_travel` | kind, depth, day | Rutas elegidas en el mapa |
| `encounter_choice` | encounter, option | Equilibrio de los Encuentros |
| `recruit` | profile, requisas | Perfiles preferidos |
| `battle_start` | mode, mission, map, squads | Uso de modos y misiones |
| `battle_end` | mode, result, rounds, mission, profiles, survival | **Balance real** por perfil (el panel calcula el % de victorias) |
| `order_played` | order | Uso de cada orden |
| `campaign_end` | result, day, squads | Dificultad de la campaña |
| `online_connect` | side | Uso del multijugador |
| `tutorial_skip` | — | Tutorial demasiado largo o innecesario |

Convención: nombres en `snake_case`, parámetros simples (texto, número, booleano o listas de texto), nunca datos personales.

## Configuración remota

El servidor sirve `config/<entorno>.json` en `GET /config/<entorno>` con ETag. La app trae los valores por defecto en `app/assets/config/defaults.json`, guarda los últimos recibidos y los refresca al arrancar y al volver a primer plano. Los cambios en el archivo del servidor se aplican sin reiniciarlo.

| Clave | Tipo | Efecto |
| --- | --- | --- |
| `multiplayer_enabled` | bool | Muestra u oculta el multijugador |
| `quick_battle_enabled` | bool | Muestra u oculta la batalla rápida |
| `poll_seconds` | int | Frecuencia de sondeo online (1–60) |
| `telemetry_flush_seconds` | int | Cada cuánto se envía la telemetría (5–3600) |
| `log_level` | texto | Nivel mínimo de log en prod |
| `min_app_version` | texto | Por debajo, la app pide actualizar |
| `maintenance_message` | texto | Aviso en el menú (vacío = sin aviso) |
| `ai_use_orders` | bool | La IA juega órdenes |
| `campaign_starting_requisas` | int | Requisas al empezar campaña |

Los datos de reglas (`units.json`) **no** se cambian por configuración remota a propósito: en multijugador, el servidor y los dos clientes tienen que usar exactamente las mismas reglas para que las partidas se reproduzcan igual. Los cambios de balance van en una versión nueva.

## Si más adelante usas Firebase

1. `flutterfire configure` para generar `firebase_options.dart`.
2. Un `FirebaseTelemetrySink implements TelemetrySink` que envíe `event` a Analytics y `error` a Crashlytics, y añádelo junto al `HttpTelemetrySink`.
3. Para Remote Config, un adaptador que rellene los mismos getters de `RemoteConfig`.

Nada más del juego cambia.
