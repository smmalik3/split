# Split — Flutter web + Node/Express + libSQL, one container.
# Build:  docker build -t split .        (or: Render deploys it from render.yaml)
# Run:    docker run -p 8080:8080 -e PORT=8080 split
# The server reads $PORT (Render injects it) and serves the Flutter web build
# plus the API. All persistent data lives in Turso (hosted libSQL); nothing
# on the container filesystem needs to survive a restart.

# ---- Stage 1: build the Flutter web app ----
FROM debian:bookworm-slim AS flutter-build

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl unzip xz-utils zip ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Pin the exact Flutter verified locally (3.47.9 / Dart 3.13.7). Floating
# `stable` broke the first Render build — the builder's fresh clone can
# roll forward to an untested Flutter/Dart at any time.
RUN git clone --depth 1 --branch 3.47.9 https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
ENV CI=true

WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
COPY analysis_options.yaml ./
COPY lib/ ./lib/
COPY web/ ./web/
RUN flutter --version \
    && flutter pub get \
    && flutter build web --release

# ---- Stage 2: slim Node 24 runtime ----
# express/multer/tesseract.js are pure JS and @libsql/client ships its native
# binding as an optional dependency, so npm ci needs no compiler here.
FROM node:24-slim AS runtime

WORKDIR /app

COPY server/package.json server/package-lock.json ./server/
RUN cd server && npm ci --omit=dev && npm cache clean --force

COPY server/server.js ./server/
COPY --from=flutter-build /src/build/web ./build/web
# OCR language data lives OUTSIDE the data dir: it is baked into the image at
# /app/tesseract-cache (see TESSERACT_CACHE below). It is NOT fetched at
# runtime — the tesseract.js CDN fetch hangs in some environments.
COPY data/tesseract-cache/ ./tesseract-cache/

ENV NODE_ENV=production
ENV TESSERACT_CACHE=/app/tesseract-cache
# Render injects $PORT at runtime; the server falls back to 8787 when $PORT
# is unset (e.g. local docker run).
EXPOSE 8080

CMD ["node", "server/server.js"]
