#!/bin/bash
# Start the Split server (port 8787) if it isn't already running.
# Logs: ~/workspace/splitwise-app/data/server.log
# Stop with: ./stop.sh
set -e
cd "$(dirname "$0")"
if curl -s -m 3 http://localhost:8787/api/health >/dev/null 2>&1; then
  echo "Split server is already running on http://localhost:8787"
  exit 0
fi
setsid nohup node server/server.js > data/server.log 2>&1 < /dev/null &
echo "Split server started (pid $!) on http://localhost:8787"
sleep 2
curl -s http://localhost:8787/api/health && echo
