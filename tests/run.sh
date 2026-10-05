#!/bin/bash
# Runs tests/popup.test.html in headless Chrome and prints the result.
# Needs python3 and Google Chrome. Set CHROME to use another Chromium binary.
set -u
cd "$(dirname "$0")/.."

PORT="${PORT:-8123}"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"

python3 -m http.server "$PORT" >/dev/null 2>&1 &
SERVER=$!
trap 'kill "$SERVER" 2>/dev/null' EXIT

# Wait for the server to accept connections.
for _ in $(seq 1 100); do
  curl -s -o /dev/null "http://localhost:$PORT/" && break
  sleep 0.1
done

DOM=$("$CHROME" --headless=new --disable-gpu --virtual-time-budget=20000 \
  --dump-dom "http://localhost:$PORT/tests/popup.test.html" 2>/dev/null)

# Match the failed log items only, not the same text in the test page's own script.
echo "$DOM" | grep -o '<li class="fail">[^<]*' | sed 's/<[^>]*>//'
RESULT=$(echo "$DOM" | grep -o 'RESULT: [A-Z]* [0-9]*/[0-9]*')
echo "${RESULT:-RESULT: FAIL (the test page did not finish)}"
[[ "$RESULT" == RESULT:\ PASS* ]]
