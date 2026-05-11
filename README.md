# signotec-stpadserver-bridge

> Copyright © 2026 Florian Hesse — [comnic IT](https://comnic-it.de) · License: MIT (see [`LICENSE`](LICENSE))

Docker image that runs **signoPAD-API/Web 3.5.0 (Windows build) under Wine**
on a Linux host. Turns any Linux server into a central WSS endpoint for a
LAN-attached signotec pad (Sigma / Omega / Gamma / Delta / Alpha / Zeta).

Browser clients talk HTTPS/WSS to a TLS-terminating reverse proxy of your
choice (Apache, Nginx, Caddy, …), WS traffic gets proxied into the
container, and the container speaks TCP/IP to the pad on the LAN.

## Why not the official Linux build?

signotec does ship `signoPAD-API/Web` for Linux as well
(`signoPAD-API_Web_Linux_3.5.0.zip`), but that build only implements
**Default mode**. Default mode can capture a signature, but **cannot
display a PDF on the pad** — the recipient just sees a bare "please sign"
screen. That defeats the whole reason for buying a large Delta 10.1 in
the first place.

The **Windows build** of `signoPAD-API/Web` implements the full
**API mode**: load PDF onto the pad, scroll, sign directly on the
document. Exactly what most workflows actually need.

The fix: pack the Windows build into an Ubuntu + Wine container and run
it on the Linux server. In hands-on testing, every relevant command
goes through cleanly: `searchForPads(IP=...)`, `Device.open`, `Pdf.load`,
`Display.setPDF`, `Signature.confirm`, `Signature.saveAsStream`.

## Build & run

Only the host needs `docker` — the Dockerfile fetches and extracts the
signotec installer itself.

```bash
docker build -t signotec-stpadserver:wine .

# manual one-shot run (host network so the container can reach the pad LAN)
docker run --rm --network host signotec-stpadserver:wine 0.0.0.0 49494
```

Or in one go, including systemd + Apache reverse proxy:

```bash
sudo bash install.sh
```

## What happens during `docker build`

The Dockerfile is multi-stage:

* **Stage 1 (extract)** — downloads
  `signotec_signoPAD-API_Web_3.5.0.exe` from
  [downloads.signotec.com](https://downloads.signotec.com/signoPAD-API_Web/),
  briefly runs the InstallShield wrapper under Wine to obtain the inner
  MSI, then unpacks `MSI → Data1.cab → flat binary list`. **No** signotec
  binaries are committed to this repo — they're fetched directly from
  the vendor on every build.
* **Stage 2 (runtime)** — Ubuntu 22.04 Jammy + Wine 32/64 + the
  extracted binaries. `WINEDLLOVERRIDES` forces Wine to load the native
  MSVC runtime DLLs that ship with signotec (their Boost.Asio uses
  `?_Throw_Cpp_error@std`, which is missing from Wine's own `msvcp140`
  stub).

The container listens on `0.0.0.0:49494` by default and speaks **plain
WS** (no TLS — TLS termination is delegated to Apache/Nginx with your
existing certificate).

## TLS reverse proxy

Example snippet for an Apache 2 SSL vhost (see
[`apache/orbit-ssl-signotec.snippet`](apache/orbit-ssl-signotec.snippet)):

```apache
ProxyPass        /signotec-ws/ ws://127.0.0.1:49494/
ProxyPassReverse /signotec-ws/ ws://127.0.0.1:49494/
```

Browsers then connect to `wss://<host>/signotec-ws/` — your own TLS
certificate, your own origin. Works for multiple hostnames or IPs
without having to reconfigure the pad server.

## Client-side code

The browser loads signotec's official `STPadServerLib-3.5.0.js` and
connects through the TLS endpoint. From a JavaScript perspective the
result is identical to a station-PC setup with a USB-attached pad —
same API mode, same `Pdf.load` + `Display.setPDF` flow.

## Operations

```bash
docker ps --filter name=signotec-stpadserver
journalctl -u signotec-stpadserver -f
sudo systemctl restart signotec-stpadserver
```

## Files

| File                                          | Purpose                                          |
|-----------------------------------------------|--------------------------------------------------|
| `Dockerfile`                                  | Multi-stage build: extract installer + runtime   |
| `wine-entrypoint.sh`                          | Wine prefix init + server start                  |
| `systemd/signotec-stpadserver.service`        | systemd unit for auto-start                      |
| `apache/orbit-ssl-signotec.snippet`           | Example reverse-proxy snippet for Apache         |
| `install.sh`                                  | Full setup script (sudo)                         |

## License / contributors

Code in this repository: MIT, © 2026 Florian Hesse / comnic IT
(https://comnic-it.de).

The signotec binaries fetched at build time are property of
[signotec GmbH](https://www.signotec.com) and are subject to their own
license terms — they are not stored in this repo, but downloaded fresh
from the signotec download portal on every build.
