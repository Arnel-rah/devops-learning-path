# What happens when you type a URL?

Example: typing `https://github.com` in a browser.
All values below come from my own machine (Debian, Wi-Fi through an Android hotspot).

## 0. Before the network
The browser parses the URL: scheme `https` (port 443 by default), host
`github.com`, path `/`. It checks its caches, and for HTTPS it may already
know the site only supports HTTPS (HSTS), so it skips the `http://` step.

## 1. DNS: name -> IP
The browser needs an IP. It checks its own cache, then `/etc/hosts`, then
asks the resolver from `/etc/resolv.conf`.

```
nameserver 192.168.43.1        # my gateway is also my resolver
```

The resolver answers from its cache or asks other DNS servers (recursion):

```
github.com.   35   IN   A   140.82.121.4     # TTL 35 s, answered in 8 ms
```

- The TTL is the remaining time the answer can stay in cache.
- Another resolver gave another answer (`@1.1.1.1` -> `20.87.245.0`, 95 ms):
  each resolver has its own cache, and GitHub can reply differently.
- If DNS is down, IPs still work but names fail.

## 2. Routing: how packets leave my machine
My IP is `192.168.43.115/24`. The destination `140.82.121.4` is not in my
local network, so the kernel uses the default route:

```
default via 192.168.43.1 dev wlp2s0
```

The packet goes to the gateway, which does NAT (private IP -> public IP) and
forwards it. `traceroute` showed the path: hotspot -> carrier network ->
Orange Madagascar -> Paris -> Frankfurt -> GitHub (~400 ms round trip).

## 3. TCP: open a connection
To reach `140.82.121.4:443`, the client and the server do a three-way handshake:

1. Client -> server: `SYN` ("I want to talk")
2. Server -> client: `SYN-ACK` ("OK, I am ready")
3. Client -> server: `ACK` ("Connected")

This costs one round trip. With ~400 ms of latency, that is already ~0.4 s
before any data is sent. In `curl -v`: `Trying 140.82.121.4:443...` then
`Connected to github.com`.

## 4. TLS: secure the connection
Right after TCP, the TLS 1.3 handshake runs (visible in `curl -v`):

1. `Client hello`: supported ciphers, key share (x25519), ALPN (`h2, http/1.1`)
2. `Server hello`: chosen cipher and key share
3. `Encrypted Extensions`, `Certificate`, `CERT verify`, `Finished`:
   the server proves who it is
4. Client `Finished`: both sides now share encryption keys

What I observed:

```
SSL connection using TLSv1.3 / TLS_AES_128_GCM_SHA256 / x25519
ALPN: server accepted h2
subject: CN=github.com
issuer: Sectigo Public Server Authentication CA DV E36
valid: Sep 1 2026 -> Nov 29 2026
SSL certificate verify ok.
```

The certificate proves that the server owns `github.com`: it is signed by a
CA that my system trusts (`/etc/ssl/certs`). The client checks the name, the
dates and the signature chain. After that, all traffic is encrypted, so
nobody on the path (hotspot, carrier) can read or modify it.

## 5. HTTP: ask for the page
Over the encrypted channel, the browser sends the request (HTTP/2, negotiated
by ALPN):

```
GET / HTTP/2
Host: github.com
```

The server replies with a status code, headers and a body:

```
HTTP/2 200
content-type: text/html; charset=utf-8
```

Status codes to know: `200` OK, `301/302` redirect, `404` not found,
`500` server error.

If I type `http://github.com` instead, port 80 only redirects:

```
HTTP/1.1 301 Moved Permanently
Location: https://github.com/
```

The browser then repeats steps 1 to 5 on port 443.

## 6. Rendering
The browser parses the HTML and discovers more resources (CSS, JavaScript,
images, fonts). It requests each one (often on the same HTTP/2 connection or
on other domains, which means more DNS lookups), builds the page and
displays it.

## Summary

| Step | Protocol | What happens | My observation |
|---|---|---|---|
| 1 | DNS (UDP 53) | name -> IP | `140.82.121.4`, TTL 35 s |
| 2 | IP / routing | packet goes to the gateway | default via `192.168.43.1` |
| 3 | TCP | SYN, SYN-ACK, ACK | `Connected to github.com` |
| 4 | TLS 1.3 | certificate check, keys | Sectigo DV E36, verify ok |
| 5 | HTTP/2 | `GET /` -> `200` | `HTTP/2 200` |
| 6 | Browser | parse and load resources | more requests |

## Where it can break (debugging)

| Symptom | Likely layer | Command |
|---|---|---|
| `Could not resolve host` | DNS | `dig`, `cat /etc/resolv.conf` |
| Timeout, no connection | routing / firewall | `ip route`, `traceroute`, `nc -zv host 443` |
| `Connection refused` | nothing listens on that port | `ss -tlpn` on the server |
| Certificate error | TLS | `curl -v`, `openssl s_client` |
| `502` / `503` | application or load balancer | server logs |

## Why this matters for AWS
- DNS -> Route 53
- Routing and NAT -> VPC route tables, Internet Gateway, NAT Gateway
- Open ports -> Security Groups (and the app must listen on the right address)
- TLS certificates -> ACM / Let's Encrypt, load balancer or Caddy
- Debugging -> the same table above, layer by layer