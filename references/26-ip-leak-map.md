# 26 · Не спалить свой IP: карта утечек и как заткнуть (Fedora/GNOME, Linux)

<!-- meta
категория: E-сеть-удалённый-доступ
риск: L1→L2 (правки клиентов/браузера/сервисов; VPN/firewalld — L2; серверные схемы — L3, считать отдельно)
preflight-гейт: NETWORK_ONLINE=yes; установлен Mullvad (`references/24`); Firefox-профили есть (`references/25`)
откат: у каждого блока — своя команда отката; системное не трогаем без согласия
-->

Это **карта**: одним взглядом — где именно течёт реальный IP и чем это закрыть. Не
дублирует соседей, а связывает их: VPN — `24`, WebRTC — `25`, торренты/свой VPS — `09`.
Правило то же: сначала preflight, потом действия; verify фактами, не глазами.

## Главное за 30 секунд

IP течёт **не одним способом, а пятью слоями**. Закрыл один — светит другой:

| Слой | Что течёт | Чем течёт | Затычка | Где |
|---|---|---|---|---|
| Сеть | DNS мимо туннеля | systemd-resolved / NetworkManager / DoH | DNS от Mullvad + проверка `resolvectl` | `24`, `30` |
| Сеть | IPv6 мимо VPN | dual-stack | `mullvad ipv6 set off` + блок в nft | `30` |
| Сеть | обрыв VPN → открытый трафик | упал туннель | lockdown mode (kill switch) | `24`, `30` |
| Локально | mDNS/анонсы, открытые порты | avahi, firewalld, docker | закрыть сервисы и порты | `30` |
| Приложения | Telegram/Discord/торрент/игра | P2P-соединения | bind на VPN, релей, «Never» | `29` |
| Браузер | WebRTC, IPv6, DoH, отпечаток | JS страницы | `user.js` / Mullvad Browser | `25`, `28` |
| Наружу сервис | домашний IP виден клиентам | проброс портов из дома | только через VPS/туннель | `27` |
| Поведение | IP по крошкам (почта, git, ник) | ты сам | гигиена | `27` |

**Мысль:** VPN закрывает слой «пакеты». Всё, что выше, VPN **не** закрывает.

---

## 1. Сетевой слой: DNS, IPv6, kill switch

> Полный разбор с **живыми дампами** nft/resolvectl/ss (Fedora 44) — в
> `references/30-network-dns-ipv6.md`. Здесь — карта.

### DNS: уходит ли запрос мимо туннеля

VPN шифрует трафик, но DNS может резолвиться **локальным/провайдерским** резолвером
мимо туннеля — тогда видно, **какие** сайты ты открываешь. (Живой факт: на Linux с
приложением Mullvad весь `:53` кроме туннельного режется, так что маршрутом DNS не
утечёт — враг в основном **DoH в браузере**, см. `28`.)

Диагностика (read-only):

```bash
resolvectl status                 # какие DNS на каждом link'е
resolvectl query example.com      # куда реально ушёл запрос
cat /etc/resolv.conf              # что видит «классика»
mullvad dns get                   # что настроил Mullvad
```

Мullvad ставит свой DNS (в туннеле, `100.64.0.7`) и умеет блокировать внешний DNS.
Проверка утечки: `https://dnsleaktest.com` (расширенный тест — должен показать
**только** страну/провайдера VPN-выхода).

Грабля (проверено): флаги CLI — **без значения** (`mullvad dns set default --block-ads`,
а не `--block-ads on`). См. `references/24`.

### IPv6: тихий обход IPv4-туннеля

Dual-stack: IPv4 ушёл в VPN, а IPv6-маршрут — родной, мимо. Mullvad по умолчанию
IPv6 в туннель **не** пускает, но проверить надо.

```bash
ip -6 route show default                 # есть ли родной IPv6-дефолт
curl -6 -s --max-time 5 https://ifconfig.co ; echo   # реально ли отвечает по IPv6
mullvad ipv6 get
```

Затычка: держать `mullvad ipv6 set off`; если IPv6 нужен — только через
туннель/блок в nft. Тест: `https://test-ipv6.com`.

### Kill switch: обрыв не должен сливать трафик

Классика палева — VPN мигнул, приложение рвануло напрямую. Лечится **lockdown mode**
(`references/24`). Живая верифа: отключить VPN и убедиться, что `curl` **падает**:

```bash
mullvad disconnect
curl -s --max-time 5 https://am.i.mullvad.net/json ; echo "rc=$?"   # ждём НЕ 200
```

Грабля (проверено 28.09): **lockdown режет и контейнеры** — nft-таблица `inet mullvad`
пропускает только `oif wg0-mullvad` и `lo`, поэтому `docker0`-бридж недоступен с хоста
(RST за 0 мс). Контейнеры, к которым нужен доступ с хоста, — на `network_mode: host` +
биндинг на `127.0.0.1`. Смотреть: `sudo nft list ruleset | sed -n '/table inet mullvad/,/^}/p'`.

### Split tunneling: «это приложение — мимо VPN»

`mullvad-exclude <команда>` гонит процесс **вне** туннеля (реальный IP!). Это удобно
для игр, но именно так и палятся: запустил в исключении «на минутку» — отдал домашний
адрес. Правило: исключения — осознанно и по списку, а не «чтобы скорость была».

---

## 2. Локальный слой: сервисы, порты, анонсы

Светит не только внешний трафик — **сам хост** анонсирует себя в локалку и наружу.

```bash
ss -lntup                         # что вообще слушает
systemctl is-active avahi-daemon  # mDNS-анонсы (.local), соседи видят тебя
resolvectl status | grep -i mdns
firewall-cmd --list-all           # зона FedoraWorkstation держит 1025-65535 tcp/udp!
sudo nft list ruleset | grep -i dnat   # docker пробрасывает порты в обход firewalld
```

Что делать (по согласию, L2):

- Сузить зону firewalld: закрыть 1025-65535, оставить только нужное (ssh и пр.).
- Не держать `avahi-daemon`/Samba/`rygel` (UPnP/SSDP), если не нужны — они анонсируют
  имя хоста и услуги.
- Помнить: **docker публикует порты DNAT-ом мимо firewalld** — `-p 0.0.0.0:8080` торчит
  наружу даже при «закрытом» firewall. Публиковать на `127.0.0.1:` когда наружу не надо.

Проверка снаружи (со стороны): `nmap` по своему внешнему IP — но только по своему и
осознанно; проще смотреть локально, что слушает.

---

## 3. Приложения и P2P: тут VPN не спасает

Самый частый слив — не браузер, а **приложение, которое соединяется напрямую**.
Полный разбор по каждому приложению (71 источник, команды проверки, грабли) —
`references/29-app-p2p-ip-leaks.md`. Здесь — карта, чтобы знать, где копать.

| Приложение | Как течёт IP | Как заткнуть |
|---|---|---|
| **Telegram-звонки** | P2P (по умолчанию): собеседник видит твой IP | Настройки → Приватность → Звонки → **Peer-to-peer: Никогда** (тогда через реле). Секретный чат — E2E, но **не** P2P (IP не течёт) |
| **Signal/WhatsApp-звонки** | P2P: IP идёт партнёру ещё до ответа | Signal: **Always Relay Calls**; WhatsApp — «Protect IP in calls» (проверить в версии) |
| **Discord** | голос/видео идут через **SFU (сервер)**, НЕ P2P — IP не течёт; реальный вектор — клик по внешней ссылке | держать под VPN (Discord/ISP видят адрес); не ходить по левым ссылкам |
| **Торренты** | DHT/PEX/трекер отдают IP пиров **и твой** | **bind на интерфейс VPN** (qBittorrent: Advanced → Network Interface; Transmission: `bind-address-ipv4`), + kill switch, идеально — контейнер Gluetun. Грабля: bind необходим, но недостаточен (issues #15551/#22996/#22834). Детали — `29`, `09` |
| **Игры/лаунчеры** | full-P2P — видят все; host-only — только хост; in-game VoIP часто P2P (R6S); Steam Remote Play «Allow Direct Connection» | играть через VPN; в EOS — `Force Relays`; свой сервер — не из дома (`27`) |
| **RustDesk** | direct (hole punching) отдаёт адрес партнёру, relay — нет | суффикс **`/r`** к ID или `ALWAYS_USE_RELAY=Y`; проверять тип сессии по логам. См. `07`, `29` |
| **Почта** | SMTP-клиент палит твой IP в `Received`; веб-Gmail — нет | отправлять из веб-интерфейса или через VPS-релей |
| **VPN упал** | приложения уходят мимо туннеля (старт до VPN, ребут) | lockdown + bind + порядок старта (VPN → потом P2P-софт) |

Для торрентов bind — критично: **без bind «VPN + торрент» = палево**, при обрыве клиент
отдаёт реальный адрес пирам. Это не про скорость, это про дыру.

---

## 4. Браузер: два соседа, тут только связка

- **IP-течь в браузере** — `references/25` (WebRTC: локальный IP, `ice.no_host`).
- **Отпечаток, DoH, IPv6 в браузере, прокси, RFP, Mullvad Browser/Tor** — целиком
  вынесено в `references/28-browser-antifingerprint.md`. Не размазываем: слой браузера
  живёт там.
- Короткая связка: сначала системный слой (здесь, п. 1), потом браузер (`28`). Главный
  маркер «ты под VPN» — **рассинхрон timezone** (система UTC+3, выход Вены UTC+2);
  в Mullvad Browser RFP приводит время к UTC, и это нормально (ты в толпе).

---

## 5. Наружу сервис — без домашнего IP

Отдельный референс: `27-host-without-home-ip.md` (VPS + WireGuard, Cloudflare Tunnel,
onion, грабля «VPS видит твой endpoint»). Коротко: **никогда не пробрасывай порт из
дома**; наружу торчит VPS, дом — за туннелем. Плюс гигиена: git-`user.email`, заголовки
почты, WHOIS, повтор ника — это тоже «палево IP», только руками.

---

## Verify — только факты

```bash
mullvad status -v
curl -s --max-time 8 https://am.i.mullvad.net/json | jq .   # mullvad_exit_ip, ip, country
```

- `https://ipleak.net` — IP, DNS, WebRTC разом.
- `https://browserleaks.com/webrtc` — локальный IP (сосед `25`).
- `https://dnsleaktest.com` — DNS мимо туннеля.
- `https://test-ipv6.com` — IPv6-утечка.
- `https://am.i.mullvad.net/check` — на самом ли деле через Mullvad.

Ожидаем: внешний адрес = **выход VPN**; ни одного `192.168.*`, `10.*`, `fe80::`; DNS —
страна VPN, не провайдер.

## Откат

Блоки правятся по одному и обратимы: настройки клиента — вернуть как было; `firewall-cmd`
— вернуть прежнюю зону/порты (снимок `firewall-cmd --list-all` до правки); VPN-настройки —
`references/24`. Системное — только с согласия владельца.

## References

- Mullvad: DNS / IPv6 / lockdown / split tunneling / port forwarding — `mullvad.net/en/help`
- Mozilla WebRTC privacy — `references/25` (имена префов ICE)
- Cloudflare Tunnel — `developers.cloudflare.com/cloudflare-one/connections/connect-networks/`
- Torrent bind на интерфейс — доки qBittorrent / Transmission; сосед `references/09`
- Telegram P2P-звонки — официальный FAQ (Peer-to-peer настройка)
- Соседние референсы: `24-mullvad-vpn-hardening.md`, `25-webrtc-ip-leak-firefox.md`,
  `28-browser-antifingerprint.md`, `29-app-p2p-ip-leaks.md`, `30-network-dns-ipv6.md`,
  `09-vpn-torrents.md`, `07-rustdesk-games.md`, `27-host-without-home-ip.md`
