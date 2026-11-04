# Lectern: the Flutter web app and the Dart server in one image.
#
#   docker build -t lectern .
#   docker run -p 8091:8091 -v lectern-data:/data \
#     -e PUBLIC_BASE_URL=http://localhost:8091 lectern
#
# Configuration is environment variables only. SQLite lives in /data.

FROM debian:bookworm-slim AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git unzip xz-utils zip \
 && rm -rf /var/lib/apt/lists/*
ARG FLUTTER_VERSION=3.44.2
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
      https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}
RUN flutter config --no-analytics --no-cli-animations \
 && flutter precache --web

# Shared packages at the same relative paths as in the repository.
COPY packages/sui_auth/ /src/packages/sui_auth/
COPY packages/sui_wallet_web/ /src/packages/sui_wallet_web/
COPY packages/upload_recovery/ /src/packages/upload_recovery/
COPY packages/walrus_blob_check/ /src/packages/walrus_blob_check/

WORKDIR /src/app
COPY app/pubspec.yaml app/pubspec.lock ./
RUN flutter pub get
COPY app/ ./
RUN flutter build web --release --no-web-resources-cdn --no-wasm-dry-run \
 && rm -f build/web/canvaskit/*.symbols build/web/canvaskit/*/*.symbols

WORKDIR /src/server
COPY server/pubspec.yaml server/pubspec.lock ./
RUN dart pub get
COPY server/ ./
RUN dart build cli -t bin/server.dart -o /out

FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home-dir /app lectern \
 && mkdir -p /data && chown lectern /data
WORKDIR /app
COPY --from=build /out/bundle/ /app/server/
COPY --from=build /src/app/build/web/ /app/web/
ENV PORT=8091 \
    WEB_DIR=/app/web \
    DATA_DIR=/data
USER lectern
VOLUME ["/data"]
EXPOSE 8091
CMD ["/app/server/bin/server"]
