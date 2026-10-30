#!/usr/bin/env bash
# Tests start_public.sh / stop_public.sh end to end WITHOUT the internet: a fake cloudflared serves real HTTPS (self-signed) on
# 127.0.0.1 and curl is pointed at it with --connect-to. Proves: backend start, address parsing (ignores api.trycloudflare.com),
# /health through HTTPS, run/public_url.txt, sync through the "public" URL, the dashboard's Settings sees it, and a clean stop.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=fake-quick-test.trycloudflare.com" -keyout "$T/k.pem" -out "$T/c.pem" >/dev/null 2>&1
cat > "$T/cloudflared" <<STUB
#!/usr/bin/env bash
exec "$(command -v python3)" "$ROOT/scripts/tests/fake_cloudflared.py" "\$@"
STUB
chmod +x "$T/cloudflared"
export CLOUDFLARED="$T/cloudflared" FAKE_CERT="$T/c.pem" FAKE_KEY="$T/k.pem" FAKE_TLS_PORT=18443 PORT="${PORT:-8790}"
URL="https://fake-quick-test.trycloudflare.com"
export NO_PROXY="${NO_PROXY:-},fake-quick-test.trycloudflare.com" no_proxy="${no_proxy:-},fake-quick-test.trycloudflare.com"   # sandboxes with an HTTPS proxy
export TUNNEL_CURL_OPTS="--connect-to fake-quick-test.trycloudflare.com:443:127.0.0.1:18443 -k"
"$ROOT/scripts/start_public.sh"
test "$(cat "$ROOT/run/public_url.txt")" = "$URL"
echo "--- through the public URL:"
curl -fsS $TUNNEL_CURL_OPTS "$URL/health"; echo
ADMIN_PW="$(grep -Eo '^admin +[^ ]+' "$ROOT/run/demo_credentials.txt" | tail -1 | awk '{print $2}')"
TOK="$(curl -fsS $TUNNEL_CURL_OPTS -H 'content-type: application/json' -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PW\"}" "$URL/api/v1/auth/login" | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')"
KEY="$(curl -fsS $TUNNEL_CURL_OPTS -H "Authorization: Bearer $TOK" -H 'content-type: application/json' -d '{"worker_id":"WRK-SYN-001","label":"tunnel test"}' "$URL/api/v1/admin/phones" | python3 -c 'import sys,json; print(json.load(sys.stdin)["api_key"])')"
ID="HH-TUN-$RANDOM"
BODY="{\"installation_id\":\"install-tunnel-01\",\"operations\":[{\"op_id\":\"op-$ID\",\"entity_type\":\"household\",\"entity_id\":\"$ID\",\"op_type\":\"create\",\"payload\":{\"village_id\":\"VIL-SYN-01\",\"assigned_worker_id\":\"WRK-SYN-001\",\"household_member_count\":4}}]}"
echo "--- phone push (twice: the second is the offline-retry duplicate):"
curl -fsS $TUNNEL_CURL_OPTS -H "X-API-Key: $KEY" -H 'content-type: application/json' -d "$BODY" "$URL/api/v1/sync/push" | python3 -c 'import sys,json; r=json.load(sys.stdin)["results"][0]; print(r["status"], "acknowledged=%s duplicate=%s" % (r["acknowledged"], r["duplicate"]))'
curl -fsS $TUNNEL_CURL_OPTS -H "X-API-Key: $KEY" -H 'content-type: application/json' -d "$BODY" "$URL/api/v1/sync/push" | python3 -c 'import sys,json; r=json.load(sys.stdin)["results"][0]; print(r["status"], "acknowledged=%s duplicate=%s" % (r["acknowledged"], r["duplicate"]))'
echo "--- the dashboard sees the new family:"
curl -fsS $TUNNEL_CURL_OPTS -H "Authorization: Bearer $TOK" "$URL/api/v1/dashboard/households?q=$ID" | python3 -c 'import sys,json; j=json.load(sys.stdin); print("total", j["total"], j["items"][0]["household_id"], "from_phone=%s" % j["items"][0]["from_phone"])'
echo "--- Settings page source of the public address:"
curl -fsS $TUNNEL_CURL_OPTS -H "Authorization: Bearer $TOK" "$URL/api/v1/admin/server-info?check=false" | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j["public_url"], "|", j["source"], "| qr:", j["qr_svg"][:4])'
echo "--- secure cookie behind https (X-Forwarded-Proto set by the tunnel):"
curl -fsS -o /dev/null -D - -H "X-Forwarded-Proto: https" -H 'content-type: application/json' -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PW\"}" "http://127.0.0.1:$PORT/api/v1/auth/login" | grep -i '^set-cookie' | grep -io 'secure; *httponly\|httponly; *.*secure\|secure' | head -1
"$ROOT/scripts/stop_public.sh"
test ! -f "$ROOT/run/public_url.txt"
! curl -fsS --max-time 2 "http://127.0.0.1:$PORT/health" >/dev/null 2>&1
echo "TUNNEL SCRIPT TEST PASSED"
