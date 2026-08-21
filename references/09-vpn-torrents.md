# 09 · Self-hosted WireGuard VPN + fast torrents (client + seedbox)

Verified live: Fedora 44 (client, NetworkManager + wg-quick) and a small VPS
server (Ubuntu, 1 vCPU / 2G RAM / 80G disk / ~600 Mbps link). Result: full-tunnel
VPN with 0% interface errors, torrent port reachable from outside, and an
optional server-side seedbox (qBittorrent-nox + WebUI reachable only from the
VPN). No secrets, no real IPs — everything below uses placeholders.

## Why it matters

- A self-hosted WireGuard VPS removes the middleman: no logs, no shared exit
  IPs, no subscription — just your server and your keys.
- Torrents need **incoming connections**; without port forwarding peers can
  only connect to you one-way, which alone can cost 5–10x download speed.
- The #1 silent killer of speed is the **MTU black hole**: default WireGuard
  MTU 1420 assumes a clean path; if your route fragments at a smaller size,
  TCP thinks the network is congested and throttles itself to a crawl.
- The "pro" way to torrent: run the client **on the server** (seedbox). The
  server sits close to peers with a fat uplink; you just fetch finished files
  over SFTP.

## The setup (what was applied)

### 1. Server: WireGuard from scratch

```bash
apt update && apt install -y wireguard wireguard-tools
umask 077
SERVER_PRIV=$(wg genkey); SERVER_PUB=$(echo "$SERVER_PRIV" | wg pubkey)
CLIENT_PRIV=$(wg genkey); CLIENT_PUB=$(echo "$CLIENT_PRIV" | wg pubkey)
```

`/etc/wireguard/wg0.conf` — **MTU 1392 was the measured safe value** (1420
failed the ping test; see diagnostics). Every iptables rule in `PostUp`/
`PostDown` MUST be separated by `; ` — a single missing semicolon kills the
tunnel with `Bad argument`.

```ini
[Interface]
MTU = 1392
Address = <SERVER_WG_IP>/24
ListenPort = 51820
PrivateKey = <SERVER_PRIV>
PostUp = iptables -t nat -A POSTROUTING -s <WG_SUBNET> -o eth0 -j MASQUERADE; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -A INPUT -p udp --dport 51820 -j ACCEPT; iptables -t nat -A PREROUTING -p tcp --dport <TORRENT_PORT> -j DNAT --to-destination <CLIENT_WG_IP>:<TORRENT_PORT>; iptables -t nat -A PREROUTING -p udp --dport <TORRENT_PORT> -j DNAT --to-destination <CLIENT_WG_IP>:<TORRENT_PORT>; iptables -A FORWARD -p tcp -d <CLIENT_WG_IP> --dport <TORRENT_PORT> -j ACCEPT; iptables -A FORWARD -p udp -d <CLIENT_WG_IP> --dport <TORRENT_PORT> -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -s <WG_SUBNET> -o eth0 -j MASQUERADE; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -D INPUT -p udp --dport 51820 -j ACCEPT; iptables -t nat -D PREROUTING -p tcp --dport <TORRENT_PORT> -j DNAT --to-destination <CLIENT_WG_IP>:<TORRENT_PORT>; iptables -t nat -D PREROUTING -p udp --dport <TORRENT_PORT> -j DNAT --to-destination <CLIENT_WG_IP>:<TORRENT_PORT>; iptables -D FORWARD -p tcp -d <CLIENT_WG_IP> --dport <TORRENT_PORT> -j ACCEPT; iptables -D FORWARD -p udp -d <CLIENT_WG_IP> --dport <TORRENT_PORT> -j ACCEPT

[Peer]
PublicKey = <CLIENT_PUB>
AllowedIPs = <CLIENT_WG_IP>/32
```

Stability tuning (both ends — server here, client in section 2):

```bash
echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-wireguard.conf
echo 'net.ipv4.tcp_congestion_control=bbr' > /etc/sysctl.d/99-bbr.conf
cat > /etc/sysctl.d/99-wg-tune.conf <<'EOF'
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.ipv4.udp_mem=65536 131072 262144
net.core.default_qdisc=fq
EOF
sysctl --system
systemctl enable wg-quick@wg0 && systemctl start wg-quick@wg0
```

### 2. Client: Fedora 44

- **IPv6 must be enabled.** A `99-no-ipv6.conf` with `disable_ipv6=1` breaks
  `wg-quick` ("IPv6 is disabled on nexthop device") and AmneziaVPN entirely.
  Remove it and `sysctl -w net.ipv6.conf.all.disable_ipv6=0
  net.ipv6.conf.default.disable_ipv6=0`.
- Client `/etc/wireguard/wg0.conf`: same keys as section 1, `MTU = 1392`,
  `AllowedIPs = 0.0.0.0/0` (drop `::/0` when IPv6 is off), `DNS = 1.1.1.1`,
  `PersistentKeepalive = 25`.

```bash
sudo dnf install -y wireguard-tools
sudo wg-quick up wg0      # 1-click connect
curl -s https://api.ipify.org   # must show the server IP
```

GUI toggle (preferred): import into NetworkManager and control from
GNOME → Settings → Network → VPN.

```bash
nmcli connection import type wireguard file /etc/wireguard/wg0.conf
nmcli connection modify wg0 wireguard.mtu 1392 connection.autoconnect no
nmcli connection up wg0
```

### 3. Diagnostics (order matters)

- **MTU test** — find the largest packet that passes, then set MTU with margin:

```bash
for s in 1280 1364 1392 1400 1420; do
  ping -M do -s $s -c 2 -W 2 <SERVER_IP> >/dev/null 2>&1 && echo "MTU $s OK" || echo "MTU $s FAIL"
done
```

- **Loss/jitter**: `ping -c 60 -i 0.5 <SERVER_IP>` (1–3% loss on the route is
  enough to make torrents "drop and stall" — TCP retransmits; buffers + BBR
  smooth it, only a better route removes it).
- **Interface errors**: `ip -s link show wg0` → errors/dropped must be 0.
- **Port checks from the client lie (hairpin)** — verify with an external
  checker (e.g. yougetsignal.com/tools/open-ports).

### 4. Torrents on the client

- Bind the client to the WG interface (qBittorrent: Options → Connection →
  Network interface = `wg0`/`pc`) — no leaks.
- Torrent port in the client MUST equal the DNAT-forwarded port on the server.
- Sane limits: ~500 global / ~250 per torrent; uTP on; DHT/PEX/LSD on;
  upload cap ≥ 100 KiB/s (peers throttle you back if you starve them).
- Firewall: `firewall-cmd --permanent --add-port=<PORT>/tcp --add-port=<PORT>/udp`.
- qBittorrent 5.x rewrites its config and may pick a random port on its own —
  set the port in the GUI, not by hand-editing the conf.

### 5. Seedbox on the server (the pro move)

```bash
apt install -y qbittorrent-nox
```

`/etc/systemd/system/qbittorrent-nox.service` — **Type=simple** (the daemon
does not fork; `Type=forking` times out):

```ini
[Unit]
Description=qBittorrent-nox seedbox
After=network.target
[Service]
Type=simple
ExecStart=/usr/bin/qbittorrent-nox --confirm-legal-notice
Restart=on-failure
[Install]
WantedBy=multi-user.target
```

Configure via the WebUI API (v5 splits settings across `qBittorrent.conf` +
`qBittorrent-data.conf`; hand-written keys get ignored):

```bash
# temp password is printed to the journal on first run:
journalctl -u qbittorrent-nox -n 30 --no-pager | grep -oE "temporary password is provided for this session: \S+"
# login, then setPreferences (web_ui_address = server WG IP → VPN-only UI):
curl -s -c /tmp/qb.cookies -H "Referer: http://127.0.0.1:8080" \
  -d "username=admin&password=<TEMP>" "http://127.0.0.1:8080/api/v2/auth/login"
curl -s -b /tmp/qb.cookies -H "Referer: http://127.0.0.1:8080" \
  --data-urlencode 'json={"web_ui_address":"<SERVER_WG_IP>","web_ui_port":8080,"web_ui_username":"admin","web_ui_password":"<NEW>","web_ui_local_host_auth":false,"web_ui_csrf_protection":true,"web_ui_host_header_validation":true,"listen_port":<SEEDBOX_PORT>,"upnp":false,"dht":true,"pex":true,"lsd":true,"max_conns":500,"max_conns_per_torrent":250,"save_path":"/srv/torrents","temp_path":"/srv/torrents/tmp","preallocate_all":true,"global_dl_limit":0,"global_up_limit":0}' \
  "http://127.0.0.1:8080/api/v2/app/setPreferences"
systemctl restart qbittorrent-nox
```

- WebUI reachable only inside the VPN (`http://<SERVER_WG_IP>:8080`) — from PC
  and phone alike; invisible from the public internet.
- The seedbox torrent port must differ from client ports, or the server's own
  DNAT rules will steal its incoming connections.
- Fetch finished files: `scp root@<SERVER_IP>:/srv/torrents/<file> ~/Загрузки/`
  or any SFTP client.

## Baseline (input data, measured)

Generic observations from a small budget VPS (1 vCPU / 2G RAM / ~80G virtual
disk) — no identifying specifics, just the numbers that matter for planning:

- **Link**: ~600 Mbps class — verified with a single-stream download at
  ~76 MB/s when the box was idle. The channel itself is real.
- **vCPU: 1 core — the actual bottleneck.** BitTorrent on a single core tops
  out around 180–230 Mbps (≈ 23–28 MB/s): thousands of peer connections,
  per-piece hashing and encryption eat the core whole (observed load > 2.5
  on 1 vCPU while downloading). The WebUI will show ~20-odd MB/s no matter
  how fat the link is.
- **Disk**: ~380 MB/s write — not a bottleneck at these speeds.
- **Takeaway**: on a 1-vCPU box expect the torrent client to cap at roughly a
  third of a 600 Mbps link. For full-link torrents plan 2–4 vCPU (usually a
  few dollars more per month). Single-stream HTTP (curl/CDN) still reaches
  the full link on one core — don't mistake that test for torrent capacity.

## Results

- Throughput via VPN ≈ 85–90% of the direct link (measured 5–8 MB/s vs
  9.5 MB/s direct on a ~76 Mbps line over an ~80 ms path).
- MTU fix alone removed the invisible fragmentation; 0% interface errors,
  0 drops on the tunnel.
- Torrent ports (client + seedbox) verified open from the public internet.
- Seedbox pulls at the server's full link speed (≈ 600 Mbps class), regardless
  of the home route quality.

## Notes / gotchas

- The route's 1–3% loss and latency live **between** ISP and server — tuning
  the tunnel cannot delete them; choose a server with good peering for the
  client's region.
- AmneziaVPN auto-enables obfuscation (Jc/Jmin/Jmax) when importing a plain
  WireGuard config — that breaks connectivity to a plain WG server; disable
  it or skip the app.
- Hairpin self-tests for forwarded ports report "closed" even when the port is
  open from the internet — always confirm with an external checker.
