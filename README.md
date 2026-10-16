# Bastión

Wargame táctico de escaramuzas para móvil, con campaña roguelike. Flutter + Flame, con un motor de reglas en Dart puro.

## Estructura

```
bastion/
├── data/                    Datos canónicos: perfiles, órdenes, mapas, encuentros
├── packages/
│   └── rules_engine/        Motor de reglas: Dart puro, determinista, sin Flutter
│       ├── lib/src/
│       │   ├── dice.dart          d6 con semilla (xorshift32) y dados guionizados
│       │   ├── geometry.dart      Vec2, peanas, polígonos, distancias
│       │   ├── profiles.dart      Perfiles, armas y catálogo desde JSON
│       │   ├── battle_state.dart  Estado de la batalla (solo lo modifica el motor)
│       │   ├── battlefield.dart   Visión, cobertura, control de objetivos
│       │   ├── rules.dart         Tablas puras: herir, salvar, modificadores
│       │   ├── combat.dart        Impactar → herir → salvar → daño
│       │   ├── commands.dart      Intenciones del jugador o de la IA
│       │   ├── events.dart        Lo que ocurrió, para animar en la UI
│       │   ├── engine.dart        Flujo de ronda, activaciones, moral, órdenes
│       │   ├── orders.dart        Las 8 órdenes y a quién afectan
│       │   ├── missions.dart      Dominio, Defensa del vado, Reconocimiento
│       │   ├── planner.dart       Cálculo de cargas y desplazamientos
│       │   ├── ai.dart            IA del MVP (también sirve en servidor)
│       │   ├── deployment.dart    Formaciones y despliegue por zonas
│       │   ├── setup.dart         Mapas, configuración y sesión guardable
│       │   ├── campaign.dart      Veteranía, rangos y mejoras por rango
│       │   ├── campaign_run.dart  Mapa de campaña, compañía, botín, encuentros
│       │   └── simulation.dart    Simulaciones en lote para balance
│       └── bin/simulate.dart      CLI del simulador
│       └── test/                  Casos del reglamento
├── packages/server/         Servidor (shelf): multijugador, telemetría, configuración remota y panel
├── env/                     Entornos de compilación de la app (dev, qa, prod)
├── deploy/                  docker compose y configuración remota para el servidor
├── docs/                    Observabilidad, CI/CD y audio
├── art/                     Arte fuente, especificación (spec.json) y su flujo
├── app/                     App Flutter + Flame
│   └── lib/
│       ├── app/             Navegación del bucle y guardado
│       ├── data/            Carga de datos y repositorio (shared_preferences)
│       ├── theme/           Tokens del design system
│       ├── game/            Controladores de tablero y componentes Flame
│       ├── widgets/         Botones, paneles y barra superior
│       ├── art/             Carga de atlas y renderizadores (vectorial e ilustrado)
│       ├── core/            Entorno y utilidades
│       ├── telemetry/       Logs, errores y analítica (con consentimiento)
│       ├── remote_config/   Configuración remota
│       ├── settings/        Ajustes y sonido
│       ├── online/          Cliente y sesión multijugador
│       ├── copy.dart        Textos de interfaz (guía de copy)
│       └── screens/         Menú, campaña, compañía, despliegue, batalla…
└── tool/sync_data.sh        Copia data/ a app/assets/data/
```

## Principios

- **Las reglas no dependen de la UI.** `rules_engine` no importa Flutter. La app envía comandos y lee eventos.
- **Determinista.** La misma semilla y la misma lista de comandos reproducen la batalla en móvil, web o servidor. Esto habilita repeticiones, deshacer y multijugador con servidor autoritativo.
- **Validar antes de mutar.** Si un comando es inválido, el motor lanza `RuleViolation` y el estado no cambia.
- **Datos, no código.** Los perfiles se balancean editando `data/units.json`.
- **El motor no tiene textos de interfaz.** Devuelve códigos (`ViolationCode`) y eventos; la UI los traduce con la guía de copy.

## Puesta en marcha

Requiere Flutter 3.27 o superior (para los workspaces de pub).

```bash
flutter pub get                       # en la raíz: resuelve todo el workspace

# Motor de reglas
cd packages/rules_engine
dart analyze
dart test

# App: genera las carpetas de plataforma (no sobrescribe lib/ ni test/)
cd ../../app
flutter create . --platforms=android,ios --project-name bastion
flutter run
```

Tras editar `data/`, ejecuta `tool/sync_data.sh`.

## Logs, analítica y configuración remota

Ver [`docs/observabilidad.md`](docs/observabilidad.md): visor de registros en la app, panel web `/admin` del servidor, catálogo de eventos, privacidad y claves de configuración remota.

## CI/CD y entornos

Ver [`docs/cicd.md`](docs/cicd.md): entornos `env/*.json`, integración continua, publicación por etiqueta `v*`, firma, Google Play, imagen Docker y despliegue.

## Simulador de balance

Desde `packages/rules_engine` (no necesita Flutter ni emulador):

```bash
dart run bin/simulate.dart duelos --batallas 200    # matriz de victorias entre perfiles
dart run bin/simulate.dart campana --campanas 100   # % de campañas ganadas por la IA
dart run bin/simulate.dart ordenes --batallas 100   # efecto de las órdenes
```

Flujo de balance: cambia un número en `data/units.json`, vuelve a simular y compara.

Para una primera estimación sin Dart, `python3 tool/balance_model.py data/units.json` calcula el valor por coste de cada perfil (1,00 = equilibrado) con las mismas reglas de dados.

`tool/balance_report.sh` junta modelo, simulador y comprobación de rangos (`tool/check_balance.py`, 35–65% de victorias por perfil). La integración continua (`.github/workflows/ci.yml`) ejecuta los tests de los tres paquetes y el simulador en cada cambio, y publica el informe en el resumen del job.

Para contrastar con partidas reales: Ajustes → Tus partidas muestra victorias y supervivencia por perfil, y "Copiar datos" exporta el JSON.

## Multijugador

```bash
cd packages/server
dart test
dart run bin/server.dart --port 8080      # guarda las partidas en ./partidas
```

En la app: Ajustes → Servidor (por defecto `http://10.0.2.2:8080`, el equipo anfitrión visto desde el emulador de Android). Cada jugador elige su compañía (hasta 4 escuadras, 150 puntos, la Capitana gratis, hasta 3 órdenes). Uno crea la partida y comparte el código de 6 caracteres; el otro se une. Después, cada uno despliega sin ver al rival y confirma; la batalla empieza cuando confirman los dos. El servidor valida cada comando con el motor y controla de quién es el turno; los clientes rejuegan los mismos comandos con la misma semilla.

### Avisos de turno

- **En el móvil, sin cuentas de terceros:** una tarea periódica (`workmanager`) consulta la partida y muestra una notificación local (`flutter_local_notifications`) cuando te toca desplegar o jugar, o cuando termina. Android ejecuta estas tareas como mucho cada 15 minutos; con la app abierta, el sondeo es cada 2 segundos.
  - Android: `flutter_local_notifications` exige *core library desugaring* en `android/app/build.gradle` (ver su README) y el permiso `POST_NOTIFICATIONS` en Android 13+ (la app lo pide al arrancar).
  - iOS: añade el identificador `bastion.turnos` a `BGTaskSchedulerPermittedIdentifiers` en `Info.plist` y activa *Background fetch* (ver la guía de `workmanager`). iOS decide cuándo ejecutar la tarea.
- **Push real desde el servidor:** con `BASTION_WEBHOOK=https://…` el servidor envía un POST `{code, side, reason}` en cada cambio de turno. Conéctalo a una función que envíe el push (FCM/APNs); hace falta tu proyecto de Firebase o tu cuenta de Apple, por eso no viene configurado.

Para probar con HTTP sin cifrar en Android, añade `android:usesCleartextTraffic="true"` al `<application>` de `android/app/src/main/AndroidManifest.xml` (solo en desarrollo; en producción, HTTPS).

## Estado

Sprint 1:
- Secuencia de ronda (Mando, Activaciones alternas, Puntuación) y fin por rondas o eliminación.
- Movimiento con coherencia, solapamiento, límites, cambio de piso y penalización de bosque.
- Disparo, carga, cuerpo a cuerpo, asegurar, atrincherar, correr y retirada.
- Combate con modificadores limitados a ±1, naturales y daño sin desbordamiento.
- Cobertura, visión, elevación, control de objetivos, moral, aura de la Capitana y PM.

Sprint 2:
- Las 8 órdenes. Todas se juegan en una activación propia: las reactivas (Cuerpo a tierra, Contraataque) se preparan en una escuadra y se consumen al usarse.
- Misiones: Dominio, Defensa del vado y Reconocimiento (objetivos ocultos que se revelan al contacto).
- Fortificar (parapeto de 3" × 1") y despliegue con Infiltración (`Battlefield.invalidDeployments`).
- `Planner` para cargas y desplazamientos, e IA en el motor: carga con asalto y caballería, avanza hacia objetivos, dispara y asegura.
- App: arrastrar para mover con círculo de alcance y formación fantasma, línea de tiro con distancia y cobertura, botones de cargar, combatir, asegurar, atrincherar y fortificar, y barra de órdenes.

Sprint 3:
- Bucle completo: menú → mapa de campaña → compañía → despliegue → batalla → resultado.
- Campaña de 7 nodos generada por semilla: batallas, Suministros, Encuentros y Fortín final.
- Compañía persistente: veteranía con mejoras reales por rango, bajas, caídas, descanso, reclutamiento y órdenes que se gastan.
- Encuentros definidos en `data/encounters.json` (efectos: requisas, orden, curar, experiencia, bajas, azar).
- Tres mapas en `data/maps.json`, uno por misión.
- Despliegue interactivo (tocar para colocar) y automático.
- Guardado: la campaña en JSON y la batalla como configuración + comandos, que se rejuegan al abrir la app.
- Resumen animado de tiradas en la batalla.
- Batalla rápida fuera de campaña.

Sprint 4:
- Simulador de balance: duelos todos contra todos, campañas en lote y efecto de las órdenes.
- IA que juega órdenes: Arenga, Contraataque ante amenazas cuerpo a cuerpo, Cuerpo a tierra bajo fuego, Avance forzado hacia objetivos lejanos y órdenes de disparo cuando compensan.
- Iconos del design system en toda la app (`flutter_svg`), sin iconos Material.
- Animaciones en el tablero: movimiento suave, bajas que se desvanecen, trazas de disparo escalonadas y onda del cañón.
- Tutorial guiado de 5 pasos en la primera batalla, con opción de saltarlo.

Sprint 5:
- Balance: modelo analítico (`tool/balance_model.py`) y costes y perfiles ajustados; todos entre 0,93 y 1,13 de valor por coste. El reglamento está actualizado.
- Sonido: efectos sintetizados provisionales (clic, dados, disparo, cañón, victoria, derrota) sincronizados con las animaciones.
- Ajustes: sonido y volumen, velocidad de animación (normal, rápida, sin animación), texto grande, tablero en texto y servidor.
- Accesibilidad: respeta "reducir movimiento" y el tamaño de texto del sistema (con tope), etiquetas semánticas, y "tablero en texto" que se activa con el lector de pantalla: lista de escuadras con posición, distancia y cobertura, y movimiento hacia objetivos sin arrastrar.
- Multijugador asíncrono: servidor autoritativo con persistencia en disco, control de turno y de versión, y cliente con sondeo y resincronización automática.

Sprint 6:
- Multijugador con compañía a elegir (presupuesto validado en el servidor) y despliegue manual con el rival oculto.
- Avisos de turno: notificaciones locales en segundo plano y webhook en el servidor para push real.
- Sonido: carga, orden, objetivo y moral rota; especificación del audio definitivo en `docs/audio.md`.
- Balance: CI con tests, simulador y comprobación de rangos; estadísticas de partidas reales en la app.

Sprint 7:
- Telemetría propia: logs, errores no controlados y eventos de analítica, con consentimiento, cola persistente y envío por lotes.
- Visor de registros en la app y panel web `/admin` en el servidor (resumen, errores frecuentes, victorias por perfil y búsqueda de registros).
- Configuración remota por entorno con ETag y caché: activar o desactivar modos, mantenimiento, versión mínima, sondeo, nivel de log, IA y requisas iniciales.
- Entornos dev, qa y prod; imagen Docker del servidor; `docker compose`; flujo de publicación con firma, Google Play, GitHub Releases y despliegue por SSH.

Sprint 8:
- Tablero con zoom: pellizco, arrastre sobre zonas vacías, rueda del ratón y botones accesibles.
- Miniaturas por rol vistas desde arriba (fusil, hacha, bandera, caballo, cañón) orientadas hacia el enemigo.
- Probabilidades antes de actuar: impacta, hiere y salva con sus modificadores, bajas esperadas, probabilidad de al menos una baja, de desmoralizar y de destruir (distribución exacta en `odds.dart`). Avisos de Contraataque y Vigilar del objetivo.
- Caras de los dados de cada ataque, por fases, con animación.
- Deshacer movimiento (comando del motor, válido también en multijugador).
- Acción Vigilar: disparo de reacción con −1, también antes de una carga; la IA la usa.

Sprint 9 (plan de arte, fases F0 y F1):
- Renderizadores intercambiables para tropas, terreno y efectos; el estilo vectorial es el código anterior, movido sin cambios.
- Estilo ilustrado con atlas WebP: una llamada `drawAtlas` por página, color de bando por máscara, figura de "caída" para las bajas, suelo en mosaico y vuelta automática a vectorial si falta una pieza.
- Elección de resolución (1x, 2x o 4x) según la pantalla; ajuste "Estilo gráfico" (Automático, Vectorial, Ilustrado) y clave remota `art_style` (sprites en dev y qa, vector en prod).
- Herramientas en Python: arte provisional, validador (`check_art.py`) y empaquetador (`pack_art.py`), probados en este entorno. La CI valida el arte.
- Pruebas: carga de todas las piezas, vuelta a vectorial, pintado real del sprite, elección de estilo y capturas de referencia etiquetadas `golden`.

Sprint 10 (plan de arte, parte de desarrollo de F3 a F5):
- Terreno ilustrado: decoración por área generada de forma determinista o fijada a mano (`decoracion` en `maps.json`), objetivos ilustrados con su anillo de puntuación, y capa estática del tablero pintada una vez y reutilizada.
- Efectos por fotogramas: fogonazo, humo e impacto en los disparos y explosión del cañón; vuelta a vectorial si faltan.
- Pose de disparo de las tropas al atacar.
- Especificación, generador provisional, validador y empaquetador para terreno y efectos; 372 recortes verificados contra sus originales.

Arte provisional mejorado:
- Motor de pintura (`tool/art/paint.py`): capas con relieve (luz arriba a la izquierda), contorno, textura y máscara de bando sombreada, sin que lo tapado se tiña.
- Tropas detalladas (mochila, casco o sombrero, brazos, armas, capa, caballo, cañón de bronce con servidores), terreno con ladrillos, tablones, copas de árbol y sacos terreros, suelo de tierra y hierba sin costuras, y efectos con degradados.
- Tropas sin pérdida y terreno y efectos con WebP de alta calidad: 2,2 MB de atlas en total.

Pendiente fuera del código:
- Arte definitivo según la especificación del plan de arte (fases F2 a F5).
- Sonido definitivo grabado o encargado según `docs/audio.md`.
- Proyecto de Firebase (o APNs) para conectar el webhook a push real.
- URL reales de qa y prod en `env/`, secretos de firma y despliegue en GitHub, y HTTPS delante del servidor.
- Política de privacidad que recoja la telemetría.
- Partidas de prueba con jugadores y ajuste de `data/units.json` con sus datos.
