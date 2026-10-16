# Imagen del servidor de Bastión. Construir desde la raíz del repositorio:
#   docker build -f packages/server/Dockerfile -t bastion-server .
FROM dart:stable AS build
WORKDIR /src

# Solo los paquetes Dart puros: la app Flutter no hace falta para el servidor.
COPY packages/rules_engine packages/rules_engine
COPY packages/server packages/server
COPY data data
RUN printf 'name: bastion_workspace\npublish_to: none\nenvironment:\n  sdk: ^3.6.0\nworkspace:\n  - packages/rules_engine\n  - packages/server\n' > pubspec.yaml

WORKDIR /src/packages/server
RUN mkdir -p /out && dart pub get && dart compile exe bin/server.dart -o /out/server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /out/server /app/server
COPY --from=build /src/data /app/data
COPY --from=build /src/packages/server/config /app/config
EXPOSE 8080
VOLUME ["/var/bastion"]
ENTRYPOINT ["/app/server", "--data", "/app/data", "--config", "/app/config", \
  "--store", "/var/bastion/partidas", "--telemetry", "/var/bastion/telemetria"]
