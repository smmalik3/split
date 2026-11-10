#!/bin/bash
# Stop the Split server on port 8787.
PID=$(ss -ltnp 2>/dev/null | grep ':8787' | grep -oP 'pid=\K[0-9]+' | head -1)
if [ -z "$PID" ]; then
  echo "No Split server running on port 8787."
  exit 0
fi
kill "$PID"
echo "Stopped Split server (pid $PID)."
