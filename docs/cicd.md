# CI/CD

## Integración continua (`.github/workflows/ci.yml`)

En cada push y pull request:

1. **Tests:** analiza y prueba el motor, el servidor y la app.
2. **Imagen del servidor:** comprueba que el Dockerfile compila.
3. **Balance:** modelo analítico, simulador de duelos, campañas y órdenes; el informe sale en el resumen del job y como artefacto. Avisa si algún perfil se sale del 35–65% de victorias.

## Entornos

`env/dev.json`, `env/qa.json` y `env/prod.json` definen `ENV`, `SERVER_URL` y `TELEMETRY`. Se pasan al compilar:

```bash
cd app
flutter run --dart-define-from-file=../env/dev.json
flutter build appbundle --release --dart-define-from-file=../env/prod.json --dart-define=APP_VERSION=1.2.0
```

Cambia las URL de qa y prod por las de tus servidores. Cada entorno del servidor tiene su configuración remota en `packages/server/config/`.

## Publicación (`.github/workflows/release.yml`)

- **Etiqueta `v1.2.3`:** compila qa y prod, publica la imagen del servidor en GitHub Container Registry, despliega (si está configurado), sube prod a la pista interna de Google Play (si está configurado) y crea la Release con los APK y AAB.
- **Manual (Run workflow):** elige el entorno y hace lo mismo para ese entorno.

### Secretos y variables

| Nombre | Tipo | Para qué |
| --- | --- | --- |
| `ANDROID_KEYSTORE_BASE64` | secreto | Keystore de firma en base64 (`base64 -w0 release.jks`) |
| `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | secretos | Datos de la keystore |
| `PLAY_SERVICE_ACCOUNT_JSON` | secreto | Cuenta de servicio de Google Play con permiso de publicación |
| `ANDROID_PACKAGE_NAME` | variable | Id de la app en Play (p. ej. `com.tuestudio.bastion`) |
| `DEPLOY_HOST`, `DEPLOY_USER`, `DEPLOY_PATH` | variables | Host del servidor; sin `DEPLOY_HOST` no se despliega |
| `DEPLOY_SSH_KEY` | secreto | Clave SSH para ese host |

Sin secretos de firma, el flujo compila igualmente (firmado con la clave de debug), útil para qa.

### Firma de Android

La primera vez, genera y versiona las carpetas de plataforma (`flutter create . --platforms=android,ios` en `app/`). Después, en `app/android/app/build.gradle(.kts)`, lee `key.properties` y úsalo en `signingConfigs.release` (ver la guía oficial "Build and release an Android app" de Flutter). El flujo escribe `key.properties` y la keystore desde los secretos.

## Servidor

```bash
docker build -f packages/server/Dockerfile -t bastion-server .
cd deploy && cp .env.example .env   # rellena BASTION_ADMIN_TOKEN
docker compose up -d
curl http://localhost:8080/health
```

Los datos (partidas y telemetría) viven en el volumen `bastion-data`. `deploy/config/` se monta como configuración remota editable. Pon el servidor detrás de HTTPS (por ejemplo, Caddy o un balanceador) antes de abrirlo a internet.
