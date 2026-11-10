# Split — Node/Express + prebuilt Flutter web, one container.
# The Flutter web app is built locally (flutter build web --release) and
# committed under build/web. Render's builder failed twice installing the
# Flutter toolchain in-Docker (git clone + 227MB Dart SDK download), so
# the Docker build no longer needs Flutter at all — it just serves the
# prebuilt output. Rebuild + commit build/web whenever the frontend changes.
# Build:  docker build -t split .        (or: Render deploys it from render.yaml)
# Run:    docker run -p 8080:8080 -e PORT=8080 split
# The server reads $PORT (Render injects it) and serves the Flutter web build
# plus the API. All persistent data lives in Turso (hosted libSQL); nothing
# on the container filesystem needs to survive a restart.

FROM node:24-slim

WORKDIR /app

COPY server/package.json server/package-lock.json ./server/
RUN cd server && npm ci --omit=dev && npm cache clean --force

COPY server/server.js ./server/
COPY build/web ./build/web
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
