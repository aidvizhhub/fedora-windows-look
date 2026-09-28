# 30 · Сетевой слой: DNS, IPv6, kill switch, порты, split-tunnel (Linux)

<!-- meta
категория: E-сеть-удалённый-доступ
риск: L1→L3 (диагностика read-only; сужение firewalld — L2; sysctl/правила — L3 с подтверждением)
preflight-гейт: NETWORK_ONLINE=yes; установлен Mullvad (`mullvad-vpn`), `nftables`; см. `24`
откат: настройки Mullvad — `mullvad dns/ipv6/lan ... set`; firewalld — вернуть прежнюю зону; sysctl — убрать файл
-->

Глубокий разбор **сетевого** слоя «не спалить IP» с **живыми дампами** (Fedora 44,
kernel 7.x, `nftables` 1.1.6, `mullvad-cli` 2026.5). Карта целиком — `26-ip-leak-map.md`;
VPN-настройка — `24-mullvad-vpn-hardening.md`. Конкретные адреса/хост владельца не
приводятся — только механизмы и команды.

## 0. Как Mullvad устроен на Linux (база)

- Демон строит собственную таблицу **`inet mullvad`** в nftables. Цепочки
  `output`/`input`/`forward` имеют **`policy drop`**; в `output` висит:
  ```
  oif "wg0-mullvad" udp dport 53 ip daddr <DNS-туннеля> accept
  oif "wg0-mullvad" tcp dport 53 ip daddr <DNS-туннеля> accept
  udp dport 53 reject
  tcp dport 53 reject with tcp reset
  oif "wg0-mullvad" accept
  reject
  ```
- Метки: `meta mark 0x6d6f6c65` (fwmark «в туннель») и `ct mark 0x00000f41` (skip-tunnel).
  Policy-роутинг (`ip rule`) заворачивает всё, кроме помеченного, в таблицу с
  `default dev wg0-mullvad`.
- На старте до демона ставится блокирующая политика отдельным юнитом (early-boot firewall).

Смотреть живьём (read-only):

```bash
mullvad status -v
sudo nft list table inet mullvad
ip rule ; ip route show table all | grep -i wg
```

---

## 1. DNS: на Linux под Mullvad утечь не может

**Механизм.** `systemd-resolved` слушает stub `127.0.0.53`; `/etc/resolv.conf` — симлинк.
Mullvad отдаёт DNS через туннель (`100.64.0.7`). Но проверять надо, потому что утечка
идёт **не через маршрутизацию, а через браузер** (DoH).

Проверка (живая, read-only):

```bash
resolvectl status              # Link wg0-mullvad: DNS Servers, Default Route: yes
resolvectl query example.com   # в конце "-- link: wg0-mullvad" = ушло в туннель
resolvectl dns                 # per-link DNS
cat /etc/resolv.conf ; ls -l /etc/resolv.conf
```

**Факт (живой ruleset):** в `output`/`forward` Mullvad **весь** `:53` уходит в `reject`,
кроме запросов через туннель к своему DNS. Значит на Linux с приложением обычный DNS
утечь не может — он либо в туннель, либо отклонён.

Враг — **DoH/DoT в браузере**: он идёт по 443 и обходит эти правила. Поэтому:

- Firefox: `Settings → Privacy & Security → Enable secure DNS → Off` (Firefox сам включает
  DoH через Cloudflare в части стран, включая РФ → запросы уходят мимо туннеля).
- Chromium-браузеры: выключить «Secure DNS / Use secure DNS».
- Свои DNS не задавать: `mullvad dns set default`.

Грабли:

- `mullvad dns set default` — **флаги без значения**: `... --block-ads --block-trackers
  --block-malware`; снять всё — просто `mullvad dns set default`.
- `/etc/resolv.conf` руками править бесполезно — симлинк, `resolved` перезапишет.
- При ручном WireGuard: `resolvectl dns <iface> <DNS-туннеля>`, непубличные резолверы.

---

## 2. IPv6: тихий обход IPv4-туннеля

**Механизм.** Если туннель несёт только IPv4, а на физлинке есть глобальный IPv6, ОС
предпочитает v6 → данные уходят мимо. Проверка (живая):

```bash
ip -6 route show default
ip -6 addr show scope global                 # есть ли глобальный v6
ip -6 route get 2606:4700:4700::1111         # "Network is unreachable" = v6 закрыт
curl -6 -s --max-time 5 https://ifconfig.co  # ответит = v6 ходит наружу
mullvad tunnel get                            # IPv6: off/on
```

Риск закрыт, когда `mullvad tunnel get` → **IPv6: off** (приложение не пропускает v6; в
nft `inet mullvad` v6 наружу не идёт). Затычка: `mullvad tunnel set ipv6 off`.

Грабли:

- **Классический разрыв:** включить in-tunnel IPv6, но физлинк тоже имеет глобальный v6 —
  нужен корректный маршрут/firewall, иначе возможная утечка.
- Системный `net.ipv6.conf.all.disable_ipv6=1` (L3) — грубо: ломает v6-сайты, влияет на
  Docker/`systemd-networkd`. Лучше держать off в Mullvad, а не резать стек глобально.
- Тесты: `test-ipv6.com`, `ipv6-test.com`.

---

## 3. Kill switch и lockdown: fail-closed, но зависит от правил

**Механизм.** Kill switch **всегда включён** — это не кнопка, а строгие nft-правила,
ставящиеся атомарно при выходе из `Disconnected`; в состояниях
`Connecting/Disconnecting/Error` он **fail-closed**. **Lockdown mode** добавляет блок и в
`Disconnected` (после явного Disconnect). Символ — замок «Blocking internet».

Проверка (живая):

```bash
mullvad status -v
mullvad lockdown-mode get
sudo nft list table inet mullvad          # policy drop?
mullvad disconnect
curl -s --max-time 5 https://am.i.mullvad.net/connected   # должен отказать/«Not using»
mullvad connect
```

**Где течёт:** если правила **не встали**, демон уходит в `Error` и сам пишет в лог
`FAILED TO BLOCK NETWORK CONNECTIONS ... Failed to set firewall policy`. Причины: старое
ядро / нет nftables / конфликт с другим firewall / reload nftables во время апгрейда.
Тогда блокировки нет — возможна утечка. Всегда сверяй `mullvad status -v` и лог:

```bash
journalctl -u mullvad-daemon -b | grep -iE 'firewall|block|error'
```

**Наша живая грабля (28.09):** при `LAN sharing = block` правила режут **`docker0`** —
хост↔контейнер и контейнер→наружу падают (RST за 0 мс), хотя внутри контейнера всё живо.
Фикс: контейнеры, нужные с хоста, — `network_mode: host` + бинд на `127.0.0.1`; для DNS
контейнеров известный обход — указать in-tunnel DNS `100.64.0.1` в `daemon.json`.

---

## 4. Имя хоста и сервисы в локалку (mDNS/SSDP/DHCP)

**Механизм.** `avahi-daemon` (mDNS, 5353/udp), `wsdd` (WS-Discovery, 3702/udp),
LLMNR (5355) и DHCP-Option-12 (hostname) **анонсируют имя и сервисы в локальный сегмент**
(не в интернет). При `LAN sharing = allow` мультикаст уходит в физическую сеть.

Проверка (живая; **важно:** для UDP — `-u`, а не `-d`):

```bash
sudo ss -lunp        # mDNS 5353, LLMNR 5355, wsdd 3702  (-d = DCCP, не то!)
sudo ss -ltnp        # TCP-листенеры
hostnamectl          # Static/Transient hostname
mullvad lan get      # allow/block
```

Затычка:

- Держать `mullvad lan set block` (по умолчанию у нас).
- Не нужен Avahi → `systemctl disable --now avahi-daemon`; не нужен `wsdd` → отключить.
- DHCP hostname: NetworkManager `ipv4.dhcp-send-hostname no` (или `send host-name = "";`).
- LLMNR: в `resolved.conf` `LLMNR=no`.

---

## 5. Порты наружу и Docker в обход firewalld

**Механизм (живая находка).** Зона `FedoraWorkstation` по умолчанию держит **открытыми
`1025-65535/tcp` и `1025-65535/udp`** — плюс `ssh`, `samba-client`. А Docker публикует
порты **в обход** firewalld через **DNAT** (`table ip nat chain PREROUTING`, priority
`dstnat`) — DNAT срабатывает раньше фильтра firewalld, поэтому закрытый в firewalld порт
всё равно отвечает.

Проверка:

```bash
firewall-cmd --list-all
firewall-cmd --list-ports --zone=FedoraWorkstation
sudo ss -ltnp
sudo nft list ruleset | grep -nE 'DOCKER|dnat|policy drop'
```

Затычка:

- Сузить зону:
  `sudo firewall-cmd --permanent --zone=FedoraWorkstation \
   --remove-port=1025-65535/tcp --remove-port=1025-65535/udp && sudo firewall-cmd --reload`.
- Docker не публиковать на `0.0.0.0` — биндить `127.0.0.1:8080:80`; правило в
  `DOCKER-USER`/раньше `dstnat` для остального.
- Kill switch Mullvad (priority filter 0) идёт раньше firewalld (filter+10) и режет
  входящее с WAN — держать включённым.

**Правило:** «порт закрыт в `firewall-cmd`» ≠ «порт закрыт», если рядом Docker.

---

## 6. Split tunneling: «это приложение — мимо VPN»

**Механизм.** Linux-реализация — через **cgroup**: исключённый процесс попадает в cgroup,
nft-правило `mangle` матчит `meta cgroup <inode>` и ставит метки, выводящие его наружу
(`ct mark 0x00000f41` + `meta mark 0x6d6f6c65`).

```bash
mullvad-exclude curl https://am.i.mullvad.net/connected   # "Not using Mullvad" = мимо
mullvad split-tunnel list
```

**Риск:** исключённый процесс ходит с **реальным IP** — это и есть деанон; Mullvad прямо
предупреждает про корреляцию «два IP одновременно». Грабли: DNS исключённого приложения
**всё равно** идёт в туннель (исключение неполное); соединения рвутся при смене сервера;
на Linux нет path-based — браузеры/дочерние процессы наследуют исключение непредсказуемо.

**Правило:** не исключать ничего, кроме реально нужного; «на минутку для скорости» — так
и палятся.

---

## 7. Чем проверять себя (что смотреть)

| Сервис | Что проверяет | Что должно быть |
|---|---|---|
| `mullvad.net/en/check` | IP, DNS, WebRTC | «Using Mullvad VPN» + No DNS leaks |
| `ipleak.net` | IP, WebRTC(STUN), DNS, torrent-детект | нет ISP-IP/ISP-DNS |
| `browserleaks.com/webrtc` \| `/dns` | локальный IP, резолверы | только выход Mullvad |
| `dnsleaktest.com` (Extended) | 36 запросов | все резолверы — Mullvad |
| `test-ipv6.com` | IPv6-утечка | v6 недоступен или тоже за VPN |
| `am.i.mullvad.net/connected` | принадлежит ли IP Mullvad | Connected |

## Verify (живьём)

```bash
mullvad status -v
mullvad tunnel get ; mullvad lan get ; mullvad lockdown-mode get
sudo nft list table inet mullvad | head
resolvectl query example.com
sudo ss -lunp | grep -E '5353|1900|3702|5355'
```

## Откат

Настройки Mullvad — `mullvad dns/ipv6/lan ... set <default>` (см. `24`). firewalld —
вернуть прежнюю зону (снимок `firewall-cmd --list-all` до правки). sysctl — удалить
`/etc/sysctl.d/*.conf` и `sysctl --system`. Системное — только с согласия владельца.

## References

- Mullvad: security.md (kill switch/lockdown), known-issues, split-tunneling, «How to
  prevent DNS leaks» (2026-06-24), «CLI» (2026-01-20), IPv6 support
- Mullvad issue #9647 (Docker DNS под VPN, 2026-01), #8620 (старое ядро/nft)
- Fedora Magazine/Discussion — зона `FedoraWorkstation` и её открытые порты; firewalld
  discussion #1125 и ServerFault — Docker DNAT в обход firewalld
- systemd-resolved: `resolvectl`, `resolved.conf`
- BrowserLeaks / ipleak / dnsleaktest / test-ipv6 / am.i.mullvad.net
- Соседние референсы: `24-mullvad-vpn-hardening.md`, `26-ip-leak-map.md`,
  `29-app-p2p-ip-leaks.md`, `28-browser-antifingerprint.md`, `09-vpn-torrents.md`
