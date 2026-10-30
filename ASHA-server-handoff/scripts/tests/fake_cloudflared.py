#!/usr/bin/env python3
"""Stand-in for `cloudflared tunnel --url http://127.0.0.1:PORT` used by test_tunnel_scripts.sh where the real Cloudflare edge is not
reachable. It prints the same log lines a quick tunnel prints (including the api.trycloudflare.com line the script must ignore) and then
serves HTTPS on 127.0.0.1:$FAKE_TLS_PORT with a self-signed certificate, piping bytes to the local server like the real tunnel does."""
import asyncio
import os
import ssl
import sys
import time

args = sys.argv[1:]
target = args[args.index("--url") + 1]
host, port = target.split("://", 1)[1].split(":")
tls_port = int(os.environ.get("FAKE_TLS_PORT", "8443"))
name = os.environ.get("FAKE_TUNNEL_HOST", "fake-quick-test.trycloudflare.com")
log = sys.stderr
log.write("2026-10-30T00:00:00Z INF Thank you for trying Cloudflare Tunnel.\n")
log.write("2026-10-30T00:00:00Z INF Requesting new quick Tunnel on trycloudflare.com...\n")
log.write('2026-10-30T00:00:00Z ERR error="Post https://api.trycloudflare.com/tunnel" (decoy line)\n')
log.flush()
time.sleep(1.5)
log.write("2026-10-30T00:00:01Z INF +--------------------------------------------------------------------------------------------+\n")
log.write("2026-10-30T00:00:01Z INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |\n")
log.write("2026-10-30T00:00:01Z INF |  https://%s                                                     |\n" % name)
log.flush()


async def pipe(r, w):
    try:
        while data := await r.read(65536):
            w.write(data)
            await w.drain()
    except Exception:
        pass
    finally:
        w.close()


async def handle(cr, cw):
    ur, uw = await asyncio.open_connection(host, int(port))
    await asyncio.gather(pipe(cr, uw), pipe(ur, cw))


async def main():
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(os.environ["FAKE_CERT"], os.environ["FAKE_KEY"])
    srv = await asyncio.start_server(handle, "127.0.0.1", tls_port, ssl=ctx)
    async with srv:
        await srv.serve_forever()

asyncio.run(main())
