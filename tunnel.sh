#!/bin/bash
# Expose the local Split server publicly via a Cloudflare quick tunnel.
# Prints the public https://....trycloudflare.com URL. The URL is ephemeral:
# it changes on every restart, so share the fresh link with the group.
# Logs: data/cloudflared.log
set -e
cd "$(dirname "$0")"
if ! curl -s -m 3 http://localhost:8787/api/health >/dev/null 2>&1; then
  echo "Split server is not running — starting it first..."
  ./start.sh
fi
pkill -f 'cloudflared tunnel' 2>/dev/null || true
sleep 1
setsid nohup ~/bin/cloudflared tunnel --url http://localhost:8787 > data/cloudflared.log 2>&1 < /dev/null &
echo "Tunnel starting..."
for i in $(seq 1 30); do
  URL=$(grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" data/cloudflared.log 2>/dev/null | grep -v "api.trycloudflare.com" | head -1)
  if [ -n "$URL" ]; then echo "Public URL: $URL"; exit 0; fi
  sleep 1
done
echo "Tunnel did not come up in 30s — check data/cloudflared.log"
tail -5 data/cloudflared.log
