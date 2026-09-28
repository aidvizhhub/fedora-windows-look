# 29 · Утечка IP вне браузера: приложения и P2P

<!-- meta
категория: E-сеть-удалённый-доступ
риск: L1–L3 (настройки приложений → сетевые правила); обратимо
preflight-гейт: NETWORK_ONLINE=yes
откат: в файле у каждого блока — что вернуть
-->

Референс собран research-агентом 2026-09-28. Браузер (WebRTC) — соседний
`25-webrtc-ip-leak-firefox.md`; общая карта утечек — `26-ip-leak-map.md`.
VPN-слой — `24-mullvad-vpn-hardening.md`.
Торренты+свой WireGuard — `09-vpn-torrents.md`. RustDesk для игр — `07-rustdesk-games.md`.

Пометки: **[факт]** — подтверждено источником; **[вывод]** — следствие из фактов;
**[гипотеза]** — не проверено лично. Ссылки — `[S1]`… в конце.

Коротко: IP течёт не там, где «звонок/игра», а **где есть прямой канал
хост↔хост**. Где между тобой и собеседником стоит сервер (Discord, веб-Gmail) —
там IP уходит только сервису, не человеку. Где канал прямой (звонки Telegram/Signal,
торренты, P2P-игры, RustDesk direct) — собеседник видит твой реальный адрес.

---

## 0. Ментальная модель: direct vs relayed

| Канал | Кто видит твой IP |
|---|---|
| **Relayed** (через сервер сервиса) | сам сервис (+ ISP по факту подключения). Собеседник — нет. |
| **Direct / P2P** (ICE/STUN/hole punching) | собеседник напрямую. |
| **DHT/PEX/tracker (торренты)** | другие пиры и трекер. |
| **Bind по интерфейсу** | приложение не выйдет мимо VPN-адаптера, пока адаптер живой. |

**[факт]** В WebRTC/ICE: сначала пробуются host-, затем srflx- (STUN → твой публичный
адрес) и только в последний resort relay- (TURN) кандидаты. Именно srflx несёт твой
реальный внешний IP собеседнику, если он победил [S1][S2].

---

## 1. Telegram

### Как течёт
- **[факт]** Звонки (голос/видео) по умолчанию идут **peer-to-peer** («для качества и
  меньшей задержки»). Прямое соединение → обе стороны знают реальные IP друг друга.
  Официальный ответ Telegram: «the downside ... necessitates that both sides know the
  IP address of the other» [S3].
- **[факт]** Настройка: `Settings → Privacy and Security → Calls → Peer-to-Peer` →
  `Never` (в других версиях `Nobody`) / `Always` / `My contacts`. `Never` = все звонки
  через серверы Telegram [S3][S4]. Это официальная формулировка перевода Telegram:
  «Disabling peer-to-peer will relay all calls through Telegram servers to avoid
  revealing your IP address, but may decrease audio and video quality» [S4].
- **[факт]** Звонки от тех, кого нет в контактах, Telegram **и так** релеит через свои
  серверы, чтобы не палить IP [S3].
- **[факт]** В протоколе звонка прямо сказано: стороны узнают «the IP addresses of each
  other or of the Telegram relay servers to be used (so-called reflectors)» [S5].
- **[факт]** 2018, CVE-2018-17780: десктоп-клиенты (Windows/Mac/Linux) **всегда** шли
  P2P и не имели опции «nobody» → текли публичный **и приватный** IP (даже входящий
  звонок писал IP звонящего в лог). Пофикшено в tdesktop 1.3.17 beta / 1.4.0 [S6][S7][S8].
- **[факт]** 2023: всё ещё течёт, если человек у тебя в контактах и ты принял звонок.
  TechCrunch подтвердил на живом тесте (исследователь n0a) [S3].
- **[факт]** «Секретные чаты» (Secret Chats) — **E2E, но НЕ P2P**: шифртекст
  отправляется через сервер методом `messages.sendEncrypted` и уже сервер доставляет
  второй стороне [S9]. Значит секретный чат **не отдаёт твой IP собеседнику** —
  в отличие от звонка. E2E ≠ прямой канал.
- **[факт, 2026]** Дыра «в один клик»: ссылка вида `tg://proxy`, замаскированная под
  упоминание `@username`. При клике клиент **тестирует прокси до применения твоих
  настроек прокси/VPN** — соединение уходит с реального интерфейса и палит реальный
  IP владельцу сервера. Android/iOS; PoC публичный. Telegram добавил предупреждение,
  но назвал «не уязвимостью» [S10][S11].
- **[факт]** Для сетевого наблюдателя/ISP: MTProto-транспорт отдаёт `auth_key_id` в
  открытом виде по незашифрованному TCP; это **постоянный идентификатор устройства**,
  который не меняется при смене IP и убивает анонимность даже при PFS и Secret Chats.
  Это не про собеседника, а про того, кто сидит на линии [S12].
- **[вывод]** User-боты на Telethon/Pyrogram: это обычные клиенты, ходят на дата-центры
  Telegram; в **обычной переписке** другие юзеры твоего IP не видят. **[гипотеза]**
  Если гонять через такую библиотеку звонки (pytgcalls/TgCalls) в P2P-режиме — утечёт
  так же, как в родном клиенте. Bot API: пользовательские IP ты получить не можешь;
  webhook-URL отдаёт IP **твоего** сервера только Telegram'у [вывод].

### Как проверить
```bash
# во время звонка: куда реально идут UDP-хендшейки
sudo ss -unap | grep -iE 'telegram|tdesktop'
# или Wireshark: фильтр stun / quic — ищем НЕ адреса дата-центров Telegram (149.154.x,/91.108.x)
```
Быстрый тест без софта: поставь P2P = `Never`, позвони с другого аккаунта и посмотри,
меняется ли адрес пира в логах (`~/.local/share/TelegramDesktop/log.txt`).

### Как заткнуть
1. `Settings → Privacy and Security → Calls → Peer-to-Peer = Never` (для чувствительных
   — глобально, не «My contacts»).
2. Либо **системный VPN с kill switch** — оба варианта вместе лучше: Never релеит
   звонки, VPN прячет адрес от самого Telegram/ISP.
3. Не кликать на «упоминания» в недоверенных чатах, если настроен только прокси без
   системного VPN (см. дыру `tg://proxy`) [S10].

### Грабли
- `Never` режет качество (лишний хоп через серверы Telegram) [S4].
- Старые tdesktop (<1.4.0) опции не имели — обновись [S6][S7].
- Проксировка внутри Telegram **не** спасает от `tg://proxy`: тест прокси идёт мимо
  твоего прокси. Спасает только системный (device-level) VPN [S10][S11].
- Секретный чат **не** защищает от сетевого деанона (`auth_key_id`) и не прячет факт
  «этот юзер в Telegram» от ISP [S12].

---

## 2. Discord

### Как течёт
- **[факт]** Discord использует **client-server (SFU/media relay)** для голоса и видео.
  Официальный блог: «Routing all your network traffic through Discord servers also
  ensures that your IP address is never leaked whether you use text, voice, or video —
  preventing anyone from finding out your IP address» [S13].
- **[факт]** В протоколе: клиент получает от голосового сервера его IP/порт и делает
  «IP Discovery» (узнаёт **свой** внешний UDP-адрес/порт) — обмена адресами между
  участниками нет. Браузерный клиент использует WebRTC, но всё равно против SFU
  Discord (SDP/ICE/DTLS/SRTP), а не против других юзеров [S14][S15].
- **[факт]** Утверждение «голосовые каналы Discord — P2P, любой в канале видит твой IP»
  — **миф**: сервер Discord релеит медиа; «IP grabber» работает только через внешние
  ссылки/социалку. Reddit r/discordapp, официальный блог, обзоры 2026 [S13][S16][S17].
- **[факт]** Реальный путь утечки в Discord — **клик по внешней ссылке**: превью
  картинок/ссылок проксируются Discord, но переход наружу отдаёт твой IP сайту [S13].
- **[гипотеза]** Сторонний репозиторий DcDNS утверждает про Electron/Chromium-наследие
  Discord: DNS мимо шифрования, WebRTC может отдать локальный/LAN IP, телеметрия,
  `X-Client-Data`. Это не подтверждено официально — проверить Wireshark'ом перед
  догмой [S18].

### Как проверить
```bash
# во время голоса: должны быть только адреса Discord (SFU), не IP других юзеров
sudo ss -unap | grep -i discord
```
Не верить «войс-IP-грабберам» за $30/мес — это скам-спекуляция [S19].

### Как заткнуть
1. Клиентских настроек «спрятать IP от собеседника» нет и не нужно — **архитектура уже
   релеит**. Если паришься — системный VPN.
2. Держать под VPN с kill switch, потому что **сам Discord и ISP** твой адрес видят.
3. Хостить Discord в браузере под анти-WebRTC настройками из `25-...` — если браузер
   вообще используется для других WebRTC-ресурсов [вывод].

### Грабли
- **Discord-голос ≠ WebRTC-утечка**: медиа-движок нативный, ICE как в вебе не гоняется;
  не путать с браузерной WebRTC-дырой [S13][S14].
- Discord **не даёт** per-app bind к интерфейсу → без kill switch падение VPN = уход
  трафика в физический интерфейс [вывод].
- Стрим/шаринг экрана в Discord идёт через серверы Discord — IP не течёт, но см. §8
  (визуальная утечка) [S13].

---

## 3. Торренты

### Как течёт
- **[факт]** Четыре механизма узнавания пиров: **tracker, DHT, PEX, LSD**. Каждый
  раздаёт твой `IP:port` другим [S20]. DHT хранит пиров по infohash и «relies on the
  publicly visible IP address of each node to remain constant» [S21]. PEX/NAT-PMP/UPnP
  добавляют свою долю.
- **[факт]** Свой IP видят: трекер (announce), DHT-ноды, и каждый пир, с которым ты
  установил соединение. Отключение DHT/PEX/LSD **не прячет** тебя от пиров/трекера —
  оно только уменьшает способы найти тебя [вывод из S20][S22].
- **[факт]** Даже при закрытом интерфейсе-биндинге трекер может получить реальный IP:
  qBittorrent issue #17449 — «peers see the VPN but tracker gets my public IP», причина —
  libtorrent < 2.0.7, починено в 2.0.7.0 [S23].

### Как проверить (реально)
1. `https://ipleak.net` → блок **Torrent Address detection** (даёт тестовый торрент).
   Запустил сид — если показан реальный IP, а не VPN — утечка [S24].
2. `sudo tcpdump -ni <физический_интерфейс> port <torrent-port>` при активной закачке —
   если пакеты есть, клиент ушёл мимо туннеля [вывод].
3. `ss -uap | grep -iE 'qbittorrent|transmission'` — смотреть локальный адрес сокета.

### Как заткнуть (конкретно)
**qBittorrent:**
```
Tools → Options → Advanced → Network Interface = <VPN-адаптер, напр. wg0 / ProtonVPN / NordLynx>
→ Apply → перезапустить qBittorrent
```
Официальная вика именно это и описывает: «bind ... ensures data can be transferred if
and only if your VPN is currently active» [S25]. ProtonVPN рекомендует то же самое
(Nord/Proton: `ProtonVPN TUN` для OpenVPN, `ProtonVPN` для WireGuard/Stealth; при смене
протокола интерфейс переименовывается — перебиндить) [S26].

**Transmission:**
`~/.config/transmission-daemon/settings.json`:
```json
"bind-address-ipv4": "<локальный IP VPN-интерфейса>",
"bind-address-ipv6": "<IPv6 VPN-адрес или отключить>"
```
Ман: `--bind-address-ipv4` / `-i` — «Listen for IPv4 BitTorrent connections on a
specific address. Only one IPv4 listening address is allowed. Default: 0.0.0.0» [S27].
Грабля: адрес динамический, при реконнекте меняется → нужен скрипт/рестарт, иначе
клиент слушает несуществующий адрес.

**Самый жёсткий путь — контейнер с VPN:**
Gluetun (WireGuard) + торрент-контейнер `network_mode: service:gluetun`. Если VPN
падает — контейнер теряет сеть вообще, никакой трафик не уйдёт [S28].

**Дополнительно:** включить **Anonymous Mode** в qBittorrent (скрывает клиент/пира от
трекера), отключить DHT/PEX/LSD, сменить listen-порт, `upnp=false` [S25][S29][вывод].

### Грабли (все — из живых issue, не теория)
- **#15551 (2021):** смена **любой** настройки при выключенном VPN молча сбрасывает
  `Optional IP address to bind to` в `All addresses` → человек течёт и после поднятия
  VPN. Милстоун 4.4.3 [S30].
- **#22996 (open, 2025):** qBittorrent 5.1.0 + NordVPN: Network Interface = NordLynx,
  Optional IP = адрес туннеля, а ipleak-торрент всё равно показывает реальный IP.
  Лечится контейнером Gluetun [S28].
- **#22834 (open, 2025):** split-tunnel (VPN-интерфейс с большей метрикой) → часть
  announce'ов всё равно уходит в физический Ethernet, даже с биндингом [S31].
- **#13661 (2020):** после апдейта клиент ходил мимо VPN при `Any interface` [S32].
- **[вывод]** Биндинг интерфейса — **необходим, но недостаточен**. Нужен ещё
  системный kill switch + firewall, а лучше — контейнер с VPN.
- VPN+торрент **без** биндинга = паливо, даже с kill switch: kill-switch'и текут при
  ребуте и в момент, когда туннель ещё не поднялся [S33][S34].

---

## 4. Игры, лаунчеры, in-game голос

### Как течёт
- **[факт]** P2P-игра: твой публичный IP виден всем участникам пакетным снифером
  (Wireshark/NetLimiter). Session-Sniffer прямо перечисляет «fully P2P» и
  «host-only P2P» тайтлы (Monster Hunter: World — fully P2P; Borderlands — только хост
  через P2P; и т.п.) [S35].
- **[факт]** В **host-only** P2P прямую связь имеет только хост → его IP видят все,
  остальных может прикрывать хост. В **full P2P** видят все всех [S35][вывод].
- **[факт]** Dedicated-server игры (Valorant, CS2, Apex) — сервер-посредник, игроки не
  видят друг друга [S36].
- **[факт]** Rainbow Six Siege (2016): матчи на дедиках, но **голосовой чат был P2P** →
  IP тиммейтов текли, ловились NetLimiter'ом; Ubisoft применил «IP protection» [S37].
- **[факт]** VRChat использует Steam Networking / Steam Voice, а это **P2P**: сам
  VRChat пишет «IPs are not expected to be private information ... we encourage the use
  of a VPN» [S38].
- **[факт]** Epic Online Services: режим `Force Relays` «hides your players' IP
  Addresses from each other», `Allow Relays` сначала пробует прямой P2P [S39].
- **[факт]** Кастомный игровой сервер из дома + проброс порта (Minecraft Java 25565 и
  т.п.) → **адрес сервера = твой домашний IP**, его видят все игроки по определению;
  риск DDoS/сканеров [S40][S41].
- **[факт]** Steam Remote Play Together: настройка `Allow Direct Connection (IP
  Sharing)` — если включена и сработала, гость подключается напрямую к хосту (узнаёт
  его IP); если отключена — через Steam Datagram Relays [S42][S43].
- **[вывод]** In-game VoIP часто и есть скрытый P2P-канал, даже если вся игра на
  дедиках (см. R6S).

### Как проверить
```bash
# в сессии: искать connections НЕ к игровому серверу
sudo ss -unap | grep -i <game.exe>
# Windows: resmon → Network → процесс игры, либо netstat -n -o
```
Wireshark: смотришь remote-адреса; если видишь адреса других игроков (не диапазон
сервера) — P2P [S36].

### Как заткнуть
- Системный VPN/kill switch (единственное, что реально прячет IP от других игроков) [S38].
- Играть в игры с дедиками/Force Relays, где есть [S39].
- Не хостить сервер из дома: VPS + WireGuard-туннель до дома (снаружи виден IP VPS),
  либо платный игровой хостинг, либо mesh-VPN для друзей [S40][S41].
- Steam Remote Play: отключить `Allow Direct Connection (IP Sharing)` [S42].

### Грабли
- «Open NAT» без VPN = IP охотнее светится в P2P-лобби [S36].
- IP даёт только ISP + примерный город, не адрес/квартиру — паника не по делу [S36][S44].
- Смена VPN-выхода меняет IP, но NAT-type и латентность могут убить игру [вывод].

---

## 5. RustDesk

### Как течёт
- **[факт]** Архитектура: `hbbs` (rendezvous/ID) помогает найти друг друга, затем
  клиенты пробуют **UDP/TCP hole punching → прямое P2P**; если не вышло — fallback на
  `hbbr` (relay). В majority случаев hole punching успешен, relay не используется [S45].
- **[факт]** В **direct**-режиме стороны соединены напрямую → каждая сторона видит IP
  другой (контролируемый видит IP контролёра и наоборот). В **relay**-режиме прямой
  связи нет, но хост relay видит оба [S45][вывод].
- **[факт]** `Enable direct IP access` (подключение по сырому IP/хосту) по умолчанию
  ВЫКЛ и «connection is unencrypted» [S46].

### Как заткнуть (force relay)
- **[факт]** Клиент ≥ 1.2.0: добавить суффикс **`/r`** к удалённому ID — «force the
  connection to be sent over the relay server» [S47].
- **[факт]** Сервер: переменная **`ALWAYS_USE_RELAY=Y`** у `hbbs` — «Y forces every
  session through a relay (disables direct/hole-punched connections)»; в Pro — галка в
  веб-консоли [S48][S49].
- **[факт]** WebSocket-режим клиента (`allow-websocket=Y`) тоже умеет только relay
  (кроме direct-IP) [S50].

### Как проверить
В статусе сессии RustDesk виден тип соединения (Direct/Relay) и peer-адрес в логах
(`~/.local/share/logs/RustDesk/...`) [S46].

### Грабли
- **`ALWAYS_USE_RELAY=Y` работает не всегда:** есть отчёт, что даже с ним в одной
  подсети клиенты всё равно делают P2P; issue #677 — relay не задействован [S49][S51].
  Проверяй **каждую** сессию по логам, не верь переменной на слово.
- Direct быстрее (меньше латентности) — force relay бьёт по скорости и грузит твой
  сервер (30 k–3 M/s на 1080p) [S45].
- Self-host **не** отменяет P2P: свой `hbbs`/`hbbr` всё равно сначала пробует прямой
  канал. Прячешь IP только force relay [S45][S47].

---

## 6. VPN-контекст: что делают приложения, когда туннель упал

### Как течёт
- **[факт]** Приложение, стартующее **до** VPN, ходит через физический интерфейс. Дыра
  в момент загрузки ОС (VPN ещё не поднялся) — классика: Tunnelblick issue #428 [S33].
- **[факт]** Многие kill-switch'и текут **при ребуте**: сначала интернет есть, VPN ещё
  нет. McAfee прямо рекомендует тест «перезагрузился → сразу на leak-сайт» [S34].
- **[факт]** USENIX Security 2023 «Bypassing Tunnels»: VPN-клиенты добавляют
  routing-исключения (локалка, IP самого VPN-сервера). Злоумышленник (своя точка Wi-Fi
  или подмена DNS) эксплуатирует их и заставляет трафик уйти **вне** туннеля в открытом
  виде [S52].
- **[факт]** ProtonVPN Linux, advanced kill switch on + VPN on: `curl --interface wlan0
  https://ipinfo.io` всё равно отдаёт **реальный IP**. Т.е. сокет, явно привязанный к
  физическому интерфейсу, kill switch не блокирует [S53].
- **[факт]** Android: DNS-запросы текут даже при `Always-on VPN` + `Block connections
  without VPN` — при переключении сервера/реконнекте/краше VPN, и для приложений,
  зовущих `getaddrinfo` напрямую (Chrome) [S54].

### Как проверить
```bash
# 1) проверка «а есть ли вообще блокировка вне туннеля»
curl --interface <физический_интерфейс> https://am.i.mullvad.net/json
# должен УПАСТЬ/таймаутнуться; если вернул реальный IP — kill switch дырявый для bound-сокетов
# 2) ребут-тест: перезагрузился → сразу `curl ipinfo.io`, не поднимая VPN руками
# 3) тест смены сервера (Android): смотри DNS-утечки на dnsleaktest.com
```

### Как заткнуть
1. **Системный** kill switch (Mullvad `lockdown-mode on`; wg killswitch; nftables),
   не app-level [S34][S55]. Детали — `24-mullvad-vpn-hardening.md`.
2. **auto-connect on boot** + kill switch вместе — иначе окно после ребута [S34].
3. P2P-приложения (торрент, RustDesk, игры) — **bind к интерфейсу** поверх kill switch
   [S25][S47].
4. Запускать чувствительные приложения **после** поднятия VPN; не держать их в
   автозапуске раньше VPN [вывод из S33].
5. Помнить: bind спасает только то приложение, которое его уважает; остальной софт всё
   равно может уйти мимо (см. #22834 про сплит-туннель) [S31][S53].

### Грабли
- «VPN подключён» ≠ «безопасно». Безопасность даёт набор: kill switch + автозапуск +
  bind + порядок старта [S34][S55].
- IPv6 отдельный канал утечки: если VPN только v4, а в системе включён v6 — трафик
  может уйти наружу. Mullvad по умолчанию держит v6 в туннеле off — это анти-утечка
  [S55].
- Split-tunnel ломает биндинг: часть пакетов уходит в физический интерфейс [S31].

---

## 7. Почта и заголовки писем

### Как течёт
- **[факт]** **Веб-Gmail** (mail.google.com): IP отправителя в `Received:` **не пишется**
  — только внутренние адреса Google (`10.x`). Провайдеры (Gmail/Outlook/Yahoo)
  вырезают оригинальный IP отправителя [S56][S57][S58].
- **[факт]** **SMTP-клиент** (Apple Mail, Thunderbird, Outlook) через
  `smtp.gmail.com`: Gmail добавляет `Received: from smtpclient.apple ([твой публичный
  IP]) by smtp.gmail.com` — получатель видит твой IP. Так делает сервер Gmail, потому
  что так требует стандарт почты, а не по злому умыслу [S56][S57].
- **[факт]** `X-Originating-IP` встречается в корпоративных/Google Workspace вариантах —
  ещё один носитель IP [S58].
- **[факт]** Свой почтовый сервер (в т.ч. домашний) светит **свой** IP в заголовках и
  через SPF; если сервер дома — это домашний IP [вывод из S56].
- **[факт]** Трекинг-пиксели/«прочитано» отдают IP **получателя** отправителю, не
  наоборот [S57].

### Как проверить
Gmail → ⋮ → «Show original» → смотреть `Received:`. Твой IP = строка с твоим
провайдером/городом, а не `10.x`/google.com [S56].

### Как заткнуть
- Отправлять из **веб-интерфейса**, а не из SMTP-клиента [S56].
- Если нужен клиент — гнать SMTP через VPS-релей, который перепишет `Received`; либо
  обычный VPN (IP всё равно в загаловке, но это IP VPN, не твой) [S56][вывод].
- Не путать: Google **всё равно** логирует IP подключения SMTP-клиента у себя, просто
  не пишет его в письмо [S56].

### Грабли
- «Gmail прячет IP» верно только для веба. С Thunderbird/Apple Mail — не прячет [S56].
- Само поле `Received` читается снизу вверх; верхнее — последний сервер, не отправитель
  [S57].

---

## 8. Скриншоты, метаданные, соцсети, стримы

### Как течёт
- **[факт]** EXIF с телефона содержит GPS, модель, дату-время. Соцсети (FB/IG/X/TikTok/
  Snapchat) при загрузке **вырезают** EXIF — но **прямая** отправка (мессенджер, почта,
  AirDrop, облако) обычно сохраняет его [S59][S60][S61].
- **[факт]** Скриншот GPS не несёт (новый файл), но содержит **модель устройства и
  время** создания [S60].
- **[факт]** Утечка на стороне сервиса: Gyazo (2026-09) — 23.62 млн записей и метаданные
  490 млн картинок; вместе с OCR-текстом и EXIF-GPS; «приватные» картинки защищал
  лишь 32-символьный ID [S62].
- **[факт]** P2P-стриминг (PeerTube/WebTorrent): твой IP уходит в трекер и другим
  зрителям; на PeerTube предупреждение «Watching this video may reveal your IP address
  to others», P2P включён по умолчанию (opt-out). WebTorrent подтверждает: виден
  «facing IP» [S63][S64][S65].
- **[факт]** Self-hosted стрим (Owncast/nginx-rtmp) дома: зрители подключаются к **IP
  твоего сервера** = домашний IP (RTMP ingest 1935, web 8080) [S66].
- **[факт]** Discord/Zoom/OBS-стримы идут через серверы → IP не течёт. **Но**
  визуальная утечка: если на шаримом экране видно твой публичный IP (браузер на
  ipleak, админка роутера, peer-list торрента, терминал с `curl ifconfig.me`) — зрители
  его увидят [вывод из S13][S60].

### Как проверить
```bash
exiftool photo.jpg | grep -iE 'gps|serial|make|model'   # что реально в файле
# или exif.regex.info / EXIF-вьюер — но только локально, не заливать файл
```

### Как заткнуть
- Отключить геотег в камере; перед шарингом чистить метаданные: `exiftool -all= file`,
  `mat2`, встроенные средства ОС (Win: Properties → Remove; macOS: Preview → GPS →
  Remove) [S60].
- PeerTube: выключить P2P в плеере; WebTorrent — не качать/не сидировать [S64][S65].
- Стрим — на VPS, не из дома; либо через сервис-посредник [S66].
- Шаринг экрана: убрать окна с IP-адресами; использовать режим «одно окно» [вывод].

### Грабли
- «Соцсеть вырезала EXIF» ≠ «файл чистый»: она могла сохранить копию/проиндексировать
  (кейс Gyazo) [S62].
- Опция «не участвовать» в PeerTube — opt-out, т.е. по умолчанию ты уже раздаёшь
  [S64].
- EXIF-вьюеры-онлайн сами получают твой файл и IP — чистить локально [вывод].

---

## Быстрый чек-лист «заткнуть всё»

1. Mullvad: `lockdown-mode on`, `auto-connect on` (`24-...`).
2. Telegram: `Calls → Peer-to-Peer = Never`; не кликать «упоминания» из чужих чатов.
3. Discord/прочее: не нужен bind, но держать под VPN; следить за внешними ссылками.
4. qBittorrent: `Network Interface = VPN-адаптер` + Anonymous Mode; идеально —
   Gluetun-контейнер. Проверять ipleak torrent-тестом после каждого апдейта.
5. Transmission: `bind-address-ipv4` = адрес туннеля (+ скрипт на смену IP).
6. Игры: VPN + дедик/Force Relays; сервер — на VPS, не дома.
7. RustDesk: суффикс `/r` или `ALWAYS_USE_RELAY=Y`, проверять тип сессии по логам.
8. Почта: только веб-интерфейс (или SMTP через VPS-релей).
9. Фото: геотег off + чистка EXIF; P2P-стриминг выключать.
10. После ребута — сразу leak-тест, до ручного поднятия VPN.

---

## Источники

Живой сбор 2026-09-28. `[факт]`-пункты прослеживаются к этим ссылкам. SearXNG в этот
прогон был недоступен (пустые ответы/`Server busy`) — использован websearch и прямое
чтение страниц.

**Telegram**
- [S3] TechCrunch, 2023-10-19 — «Telegram is still leaking user IP addresses to contacts»: https://techcrunch.com/2023/10/19/telegram-is-still-leaking-user-ip-addresses-to-contacts/
- [S4] Telegram Translations, «Disabling peer-to-peer will relay all calls…» (правка Mar 19, 2021): https://translations.telegram.org/en/tdesktop/settings/lng_settings_peer_to_peer_about
- [S5] Telegram API — End-to-End Encrypted Voice and Video Calls («learn the IP addresses of each other or … reflectors»): https://core.telegram.org/api/end-to-end/video-calls
- [S6] SecurityWeek, 2018-10-01 — CVE-2018-17780: https://www.securityweek.com/telegram-leaks-user-ip-addresses/
- [S7] The Hacker News, 2018-10-01: https://thehackernews.com/2018/09/hack-telegram-messenger.html
- [S8] ZDNet, 2018: https://www.zdnet.com/article/telegram-fixes-ip-address-leak-in-desktop-client/
- [S9] Telegram API — End-to-End Encryption, Secret Chats (`messages.sendEncrypted` → server): https://core.telegram.org/api/end-to-end
- [S10] Cybernews, 2026-01-12 — one-click `tg://proxy` real-IP leak: https://cybernews.com/security/telegram-one-click-vulnerability-leaks-ip-address
- [S11] PiunikaWeb, 2026-01-13 — Telegram responds: https://piunikaweb.com/2026/01/13/telegram-proxy-link-warning-ip-exposure
- [S12] iStories / Symbolic — «Telegram's MTProto: Assessing Deanonymization Potential» (auth_key_id, PFS/Secret Chats не спасают): https://symbolic.software/pdf/gnmx-01.pdf

**Discord**
- [S13] Discord Blog, 2023-08-24 — «How Discord Handles Two and a Half Million Concurrent Voice Users using WebRTC» (client-server, IP never leaked): https://discord.com/blog/how-discord-handles-two-and-a-half-million-concurrent-voice-users-using-webrtc
- [S14] Discord Docs — Voice Connections / IP Discovery / SFU: https://docs.discord.com/developers/topics/voice-connections
- [S15] Discord Blog — «Security, Discord, and You!» (client-server architecture): https://blog.discord.com/security-discord-and-you
- [S16] Reddit r/discordapp — «Can someone get my IP address just from being in a call»: https://www.reddit.com/r/discordapp/comments/ok5usi/
- [S17] TechYorker, 2026-04-29 — разбор мифа про IP в Discord: https://techyorker.com/can-someone-find-my-ip-address-through-discord-server
- [S18] GitHub larperru/DcDNS (третьестор. утверждения про Electron/Chromium): https://github.com/larperru/DcDNS
- [S19] YouTube «Investigating the Discord Exploit that Leaks Your IP!», 2024-02-26 (скам-спекуляция): https://www.youtube.com/watch?v=d0h4QPqAwss

**Торренты**
- [S20] BEP 27 (Private Torrents) — четыре механизма: tracker/DHT/PEX/LSD: https://bittorrent.org/beps/bep_0027.html
- [S21] BEP 32 (IPv6 DHT) — «DHT relies on the publicly visible IP address of each node»: https://bittorrent.org/beps/bep_0032.html
- [S22] Stack Overflow — DHT хранит peer IP по infohash: https://stackoverflow.com/questions/1332107/dht-in-torrents
- [S23] qBittorrent issue #17449 (2022) — tracker получает реальный IP: https://github.com/qbittorrent/qBittorrent/issues/17449
- [S24] TorGuard KB, upd. 2026-08-17 — bind = kill switch, тесты/проверка: https://torguard.net/support/articles/OS-and-Apps/qbittorrent-vpn-binding-windows.php
- [S25] qBittorrent Wiki, upd. 2026-09-03 — How to bind your VPN: https://github.com/qbittorrent/qBittorrent/wiki/How-to-bind-your-vpn-to-prevent-ip-leaks
- [S26] ProtonVPN — P2P servers / binding: https://protonvpn.com/support/bittorrent-vpn
- [S27] Transmission manpage — `--bind-address-ipv4` (default 0.0.0.0): https://manpages.ubuntu.com/manpages/trusty/man1/transmission-daemon.1.html
- [S28] qBittorrent issue #22996 (2025) — leak despite bind; совет Gluetun: https://github.com/qbittorrent/qBittorrent/issues/22996
- [S29] qBittorrent Wiki — How to Disable DHT, PeX, and LPD: https://github.com/qbittorrent/qBittorrent/wiki/How-to-Disable-DHT,-PeX,-and-LPD
- [S30] qBittorrent issue #15551 (2021) — rebind to All addresses: https://github.com/qbittorrent/qBittorrent/issues/15551
- [S31] qBittorrent issue #22834 (2025) — split tunnel leak: https://github.com/qbittorrent/qBittorrent/issues/22834
- [S32] qBittorrent issue #13661 (2020) — update bypassed VPN: https://github.com/qbittorrent/qBittorrent/issues/13661

**Игры / P2P-сервисы**
- [S33] Tunnelblick issue #428 — startup leak до VPN: https://github.com/Tunnelblick/Tunnelblick/issues/428
- [S34] McAfee — VPN Kill Switch (leaks during reboot; тест): https://www.mcafee.com/learn/vpn-kill-switch/
- [S35] BUZZARDGTA/Session-Sniffer — список P2P-игр (host-only vs full P2P): https://github.com/BUZZARDGTA/Session-Sniffer
- [S36] UrbanX — IP grabbers in P2P games (dedicated servers не светят; IP = ISP+city): https://urbanx.co.za/knowledge-hub/competitive-security-edge-config-continuity/ip-grabbers-p2p
- [S37] Ars Technica, 2016-04-28 — Rainbow Six Siege VoIP P2P: https://arstechnica.com/gaming/2016/04/rainbow-six-siege-reportedly-reveals-your-ip-address-to-potential-attackers
- [S38] VRChat Feedback — «IP exploit +» (Steam Networking P2P; «use a VPN»): https://feedback.vrchat.com/feature-requests/p/ip-exploit
- [S39] Epic Online Services — P2P Interface (`Force Relays` hides IPs; `Allow Relays`): https://dev.epicgames.com/docs/epic-online-services/multiplayer/nat-p2p-interface/p2p-reference
- [S40] Minecraft Hosting Pro — hosting from home exposes home IP: https://www.minecraft-hosting.pro/how-to-make-a-minecraft-server
- [S41] Self-host game server behind CGNAT (VPS+WireGuard edge), 2026-07-16: https://www.wu-ftpd.org/how-to-self-host-a-game-server-from-home-behind-cgnat
- [S42] Steam Community — «IP Sharing» / Allow Direct Connection: https://steamcommunity.com/groups/SteamClientBeta/discussions/3/2243301553223316744
- [S43] Steam Remote Play (Steamworks docs): https://partner.steamgames.com/doc/features/remoteplay
- [S44] GDevelop docs — P2P leaks client IPs: https://wiki.gdevelop.io/gdevelop5/all-features/p2p

**RustDesk**
- [S45] RustDesk Docs — Self-host (hole punching → direct, иначе relay): https://test.rustdesk.com/docs/en/self-host
- [S46] RustDesk Wiki — FAQ (direct IP access unencrypted; логи/access logs): https://github.com/rustdesk/rustdesk/wiki/FAQ
- [S47] RustDesk Wiki — Force relay (`/r` суффикс, ≥1.2.0): https://github.com/rustdesk/rustdesk/wiki/FAQ#force-relay
- [S48] rustdesk-server — environment variables (`ALWAYS_USE_RELAY`): https://github.com/rustdesk/rustdesk-server/blob/master/docs/environment-variables.md
- [S49] rustdesk-server issue #253 — ALWAYS_USE_RELAY (и грабля с LAN): https://github.com/rustdesk/rustdesk-server/issues/253
- [S50] RustDesk Docs — Advanced settings (websocket only relay): https://rustdesk.com/docs/en/self-host/client-configuration/advanced-settings/
- [S51] rustdesk-server issue #677 — relay not used despite ALWAYS_USE_RELAY=Y: https://github.com/rustdesk/rustdesk-server/issues/677

**VPN / kill switch**
- [S52] USENIX Security 2023 — «Bypassing Tunnels: Leaking VPN Client Traffic by Abusing Routing Tables»: https://www.usenix.org/conference/usenixsecurity23/presentation/xue
- [S53] ProtonVPN Linux GUI issue #130 — `curl --interface wlan0` bypasses kill switch: https://github.com/ProtonVPN/proton-vpn-gtk-app/issues/130
- [S54] BleepingComputer, 2024-05-03 — Android DNS leak даже с Always-on + Block: https://www.bleepingcomputer.com/news/security/android-bug-leaks-dns-queries-even-when-vpn-kill-switch-is-enabled
- [S55] Mullvad — CLI/lockdown/DAITA (соседний реф 24): https://mullvad.net/en/help/cli-command-wg

**Почта**
- [S56] Gmail Community thread, 2021-12 — SMTP client IP появляется в `Received`: https://support.google.com/mail/thread/138114117
- [S57] ServerFault, 2009 — веб-Gmail не показывает IP отправителя, SMTP-клиент показывает: https://serverfault.com/questions/31960/
- [S58] Security.SE, 2013 — `Received: by 10.x with HTTP` (внутренние IP Google), `X-Originating-IP`: https://security.stackexchange.com/questions/41828/
- [S59] EXIFData.org, 2025-12-15 — соцсети вырезают EXIF, прямые отправки нет: https://exifdata.org/blog/social-media-exif-privacy-tiktok-snapchat-twitter-test

**Метаданные / стримы**
- [S60] EXIFData.org — «EXIF Data Privacy» (соцсети чистят, скриншоты без GPS но с device/time): https://exifdata.org/blog/exif-data-privacy-the-ultimate-guide-to-protecting-your-image-metadata
- [S61] Christian Heilmann, 2014-10-21 — EXIF GPS реальными полями: https://christianheilmann.com/2014/10/21/removing-private-metadata-geolocation-time-date-from-photos-the-simple-way-removephotodata-com/
- [S62] The IT Nerd, 2026-09-18 — Gyazo breach (23.62M records, 490M images, EXIF GPS + OCR): https://itnerd.blog/2026/09/18/gyazo-breach-exposes-23-62m-user-records-and-metadata-for-490m-images/
- [S63] PeerTube Docs — Privacy guide (IP в трекере и у других пиров): https://docs.joinpeertube.org/admin/privacy-guide
- [S64] PeerTube issue #2934 (2020) — P2P opt-out, IP leaks by design; VPN снимает: https://github.com/Chocobozzz/PeerTube/issues/2934
- [S65] WebTorrent issue #1242 — exposes facing IP (VPN прикрывает): https://github.com/webtorrent/webtorrent/issues/1242
- [S66] Owncast Docs — Manual install/Server setup (RTMP 1935 + 8080 доступны снаружи): https://owncast.online/docs/getting-started/install/manual

**Прочее**
- [S67] How-VoIP-Calls-Can-Leak-Your-IP-Address (Wireshark/STUN PoC; WhatsApp/Telegram уязвимы, Discord — нет): https://github.com/Kulisekmatej/How-VoIP-Calls-Can-Leak-Your-IP-Address
- [S68] TechCrunch, 2023-11-03 — обзор звонков Signal/FaceTime/Messenger/Viber/Threema/Wire/WhatsApp: https://techcrunch.com/2023/11/03/psa-chat-call-apps-reveal-ip-address
- [S69] Signal Blog, 2017 — P2P только для инициатора/контактов, «Always Relay Calls»: https://signal.org/blog/signal-video-calls
- [S70] Signal-Desktop issue #6741 (2024) — IP течёт ещё до ответа; «Always Relay Calls»: https://github.com/signalapp/Signal-Desktop/issues/6741
- [S71] EFF SSD — How to: Use Signal (Always Relay Calls): https://ssd.eff.org/module/how-to-use-signal

## Слабые места / не проверено

- **SearXNG не отвечал** (пустые `results` / `Server busy`) — не удалось отработать
  полный 20-запросный свип через него; факты собраны websearch'ем и чтением страниц.
- **Live-проверок на этой машине не делалось** (Wireshark/tcpdump/ipleak) — это research,
  не верифа. «Как проверить» — команды, а не отчёт об исполнении.
- **Telegram userbot/Telethon**: поведение по IP — вывод из архитектуры (client-server),
  прямой источник не найден. Нужен живой тест звонка через pytgcalls + tcpdump.
- **DcDNS-утверждения про Discord/Electron** (DNS, WebRTC, телеметрия) — третьесторонний
  репозиторий, независимо не подтверждён.
- **WhatsApp «Protect IP address in calls»** — упоминается в GitHub-PoC, не из
  официального текста WhatsApp; проверить на актуальной версии.
- **Формулировки опций по версиям плавают** (Never/Nobody/My contacts; Discord
  server-wide voice activity) — сверять в текущем клиенте.
- **Браузерный Discord + WebRTC**: предполагается, что всё идёт на SFU Discord и прямого
  соединения между юзерами нет; лично не верифицировано пакетно.
- **P2P-мессенджеры кроме Telegram/Signal** (Session, Element/Matrix) — не разбирались
  детально: у Session P2P-звонки раскрывают IP партнёру и OPTF STUN/TURN-серверу
  [см. обсуждение privacyguides], Element/Matrix — по умолчанию релеит, но требует
  отдельной проверки.
- **IPv6-утечки приложений** (не браузера) не тестировались отдельно; известны для
  Android (см. [S54]).
