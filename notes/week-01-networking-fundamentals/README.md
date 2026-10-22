# Week 01: Networking Fundamentals

## Goals

- Understand what happens between typing a URL and seeing a page.
- Use `ip`, `dig`, `ping`, `traceroute`, `curl`, `ss`, `nc` to inspect and debug a network.
- Understand why listen addresses and ports matter for AWS Security Groups.

## 1. Local network

Commands: `ip addr`, `ip route`

- Active interface: `wlp2s0` (Wi-Fi). `enp3s0` (Ethernet) is down (`NO-CARRIER`, no cable).
- My local IP: `192.168.43.115/24` (private, assigned by DHCP, lease ~56 min).
- My gateway: `192.168.43.1` (default route, also my DNS resolver).
- A `/24` gives 254 usable hosts (`192.168.43.1` - `192.168.43.254`).
- Routing: traffic for `192.168.43.0/24` goes directly over the Wi-Fi;
  everything else (Internet) goes through the default route via `192.168.43.1`.
- Probably an Android hotspot (`192.168.43.0/24` is its default range).
- No global IPv6: only link-local `fe80::/64`.
- Private ranges (RFC 1918): `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`.
  They are not routable on the Internet; the router translates them to a
  public IP with NAT.
- Public IP: unique and routable on the Internet. Private IP: only valid
  inside a local network or VPC.
- My public IP: `<redacted>` (different from my private IP, so my traffic is
  NAT-translated; the `10.x` hops in the traceroute suggest carrier-grade NAT as well).

## 2. DNS

Commands: `dig github.com`, `dig +short`, `dig MX gmail.com`, `dig @1.1.1.1`

- DNS translates a name into an IP address.
- **TTL**: how many seconds a resolver may cache the answer before asking again.
  Low TTL = changes spread fast; high TTL = fewer queries.
- If DNS goes down: IPs still work, but names fail. Most services appear
  "down" even though the servers are fine.

| Type  | Role                      |
| ----- | ------------------------- |
| A     | name -> IPv4 address      |
| AAAA  | name -> IPv6 address      |
| CNAME | alias -> another name     |
| MX    | mail servers for a domain |

My results:

| Resolver                 | github.com     | TTL  | Query time |
| ------------------------ | -------------- | ---- | ---------- |
| `192.168.43.1` (hotspot) | `140.82.121.4` | 35 s | 8 ms       |
| `1.1.1.1`                | `20.87.245.0`  | 45 s | 95 ms      |

- `/etc/resolv.conf`: `nameserver 192.168.43.1` (set by NetworkManager via DHCP).
  My gateway is also my DNS resolver.
- `dig github.com` flags: `qr rd ra ad` (response, recursion desired/available,
  DNSSEC-validated), status `NOERROR`.
- Two resolvers gave two different IPs and TTLs: each has its own cache, and
  GitHub can answer differently (load balancing, geography). The TTL is the
  remaining cache time, so it decreases between two queries.
- 8 ms vs 95 ms: a nearby cache vs a trip across the Internet.

## 3. Path of packets

Commands: `ping -c 4 8.8.8.8`, `ping -c 4 google.com`, `traceroute github.com`

- `ping 192.168.43.1`: 100% loss, yet traceroute hop 1 answers in ~4 ms.
  The hotspot drops ICMP echo requests but still forwards traffic. A failed
  ping does not prove a host is down (AWS Security Groups also block ICMP by default).
- `ping 8.8.8.8`: 0% loss, min/avg/max = 241/326/467 ms, mdev 85 ms.
  High latency and jitter, typical of a mobile link to a distant server.
- `traceroute github.com`: 15 hops answered, destination never "seen"
  (hops 16-30 are `* * *`, GitHub filters ICMP; curl still works).
- Path: gateway (4 ms) -> carrier private network (`10.x`) -> Orange Madagascar
  -> Paris -> Frankfurt (`twelve99.net`, Telia) -> GitHub interconnect (~407 ms).
- Per-hop latency is not cumulative (272 ms at hop 3, 29 ms at hop 7): routers
  answer ICMP at low priority and the mobile link varies. Use traceroute for
  the path, not for precise timing.
- Diagnosis: if `ping 8.8.8.8` works but `ping google.com` fails,
  **connectivity is fine and the problem is DNS** (resolver unreachable
  or misconfigured).

## 4. HTTP and TLS

Commands: `curl -v https://github.com`, `curl -I`, `curl -v http://...`

What to spot in the output:

1. DNS resolution (`Host github.com:443 was resolved`)
2. TCP connection (`Trying 140.82.121.4:443`)
3. TLS handshake (Client hello, Server hello, Certificate, Finished)
4. HTTP request (`GET / HTTP/2`)
5. Response and status code (`200` OK, `301/302` redirect, `404`, `500`)

My results:

- Resolved to `140.82.121.4`, no IPv6, ALPN `h2` accepted.
- TLS version: TLSv1.3, `TLS_AES_128_GCM_SHA256`, key exchange `x25519`.
- Certificate: `CN=github.com`, valid Sep 1 - Nov 29 2026 (short-lived),
  issuer Sectigo Public Server Authentication CA DV E36, verification OK.
- The handshake took several seconds: with ~400 ms of latency, each round
  trip (TCP, then TLS) is expensive.
- Status code: `curl -sI https://github.com` returns `HTTP/2 200`
  (`content-type: text/html; charset=utf-8`). HTTP/2 was negotiated via ALPN.
- Redirect: `curl -sI http://github.com` returns `HTTP/1.1 301 Moved Permanently`
  with `Location: https://github.com/`. Port 80 only redirects; the browser
  then repeats the full DNS, TCP, TLS, HTTP sequence on port 443.
- `curl -I` sends a `HEAD` request (headers only, no body), useful for
  healthchecks and redirect tests.
- Why HTTPS needs a certificate: it proves the server is really the owner
  of the domain (signed by a trusted CA) and lets the client and server set
  up encryption, so nobody in the middle can read or modify the traffic.

## 5. Ports and connections

Commands: `ss -tulpn`, `ss -tn`, `nc -zv github.com 443`

- A port identifies a service on a machine (80 HTTP, 443 HTTPS, 22 SSH).
  IP = the building, port = the door.
- `0.0.0.0:PORT`: listens on **all** interfaces (reachable from the network).
- `127.0.0.1:PORT`: listens on the loopback only (reachable from the machine itself).

Services listening on my machine:

- Loopback only: PostgreSQL `5432`, CUPS `631`, VS Code, JetBrains Toolbox, a Java process.
- All interfaces: KDE Connect `1716` (TCP/UDP), Firefox (UDP), mDNS `5353`.
  Reachable from the hotspot network, a larger exposure on public Wi-Fi.
- `sudo ss -tulpn` shows the owner of processes run by other users.

### Mini server experiment

```bash
python3 -m http.server 8080                    # shows 0.0.0.0:8080 in ss
python3 -m http.server 8080 --bind 127.0.0.1   # shows 127.0.0.1:8080 in ss
```

Why it matters for AWS: a Security Group controls who can reach a port, but
the app must also listen on the right address. An app bound to `127.0.0.1`
is unreachable from outside even if the Security Group is open (like my
PostgreSQL on `127.0.0.1:5432`). And an app bound to `0.0.0.0` with an open
Security Group is exposed to the world.

## 6. Deliverable

See [what-happens-when-you-type-a-url.md](what-happens-when-you-type-a-url.md).

Summary of the flow:

1. **DNS**: the browser asks a resolver for the IP of the domain (after
   checking its caches and `/etc/hosts`).
2. **TCP**: three-way handshake (SYN, SYN-ACK, ACK) to open a connection
   to the IP on port 443.
3. **TLS**: the server sends its certificate, the client verifies it, both
   agree on keys (TLS 1.3).
4. **HTTP**: the browser sends `GET /`, the server returns a status code,
   headers and the HTML.
5. **Rendering**: the browser parses the HTML, fetches CSS/JS/images
   (more requests), then displays the page.

## What I learned / what broke

- My gateway and my DNS resolver are the same machine (`192.168.43.1`).
- The kernel picks a route by matching the destination against the routing
  table: local `/24` first, otherwise the default route. A VPC route table
  works the same way.
- A DNS TTL is a countdown in the resolver's cache, not a fixed value.
- `ping` to my gateway failed while traceroute reached it: ICMP can be
  filtered, so use `nc -zv` or `curl` to test a service.
- Traceroute `* * *` does not mean the path is broken.
- My connection goes through carrier NAT, Orange Madagascar, then Paris and
  Frankfurt; latency to GitHub is ~400 ms.
- `301` means "moved permanently": `Location` tells the client where to go next.
