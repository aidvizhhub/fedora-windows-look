# 24 · Mullvad VPN: харденинг (kill switch, DAITA, DNS-фильтр, multi-hop)

<!-- meta
категория: E-сеть-удалённый-доступ
риск: L2 (настройки VPN-клиента; обратимо, правки через `mullvad` GUI/CLI, систему не трогаем)
preflight-гейт: NETWORK_ONLINE=yes + установлен пакет `mullvad-vpn` (rpm) и демон `mullvad-daemon` active
откат: в файле: `mullvad lockdown-mode set off` / `auto-connect set off` / `tunnel set daita off` / `relay set multihop off` / `dns set default`
-->

Verified live: Fedora 44, GNOME 50, Wayland; `mullvad-vpn` **2026.5** (rpm), демон
`mullvad-daemon` **enabled**, GUI-ярлык `mullvad-vpn.desktop`. Клиент был **подключён**,
но с «дырявыми» дефолтами — закрыто. Без реальных IP, номеров аккаунтов и имён реле
(ниже — только плейсхолдеры и общие факты).

## Почему это нужно

Дефолтный Mullvad **подключён, но не защищает при сбое**:

- **Нет kill switch** → при падении туннеля трафик уходит **в открытую** (утечка).
- **Нет авто-старта** → после ребута система короткое время (или долго) живёт **мимо VPN**.
- **DAITA выключен** → нет защиты от анализа трафика.
- **DNS-фильтр выключен** → реклама/трекеры/малварь не режутся.

«Подключён = безопасно» — неверно. Безопасность даёт **набор настроек**, а не факт
соединения.

## Диагностика (read-only)

```bash
mullvad version
mullvad status -v
mullvad lockdown-mode get
mullvad auto-connect get
mullvad tunnel get
mullvad dns get
mullvad relay get
```

Признаки «дырявого» профиля: `Block traffic when the VPN is disconnected: off`,
`Autoconnect: off`, `DAITA: false`, блокировки `false`.

## Что применить

```bash
mullvad lockdown-mode set on      # kill switch: без VPN трафика нет вообще
mullvad auto-connect set on       # поднимать VPN при старте системы
mullvad tunnel set daita on       # DAITA — защита от анализа трафика
mullvad dns set default --block-ads --block-trackers --block-malware
mullvad relay set multihop on     # лишний хоп (вход → выход), опционально
mullvad tunnel set rotation-interval 24   # смена WireGuard-ключа каждые 24 ч (дефолт 720 ч / 30 дней)
```

**Грабля (проверено):** у `mullvad dns set default` флаги задаются **без значения** —
`--block-ads`, а НЕ `--block-ads on`. Со значением CLI падает:
`error: unexpected argument 'on' found`.

## Verify (только факты, не «должно работать»)

```bash
mullvad status -v
# ожидаем в Features: DAITA, Dns Content Blocker, Lockdown Mode, Multihop, Quantum Resistance

curl -s https://am.i.mullvad.net/json
# mullvad_exit_ip: true, country = страна выхода (утечки нет)

ip route get <ПУБЛИЧНЫЙ_IP>
# маршрут должен идти через wg0-mullvad, а не через физический интерфейс
```

- `mullvad relay get` → `Multihop state: enabled`.
- Локальные настройки: `lockdown-mode get` → `on`, `auto-connect get` → `on`,
  `tunnel get` → `DAITA: true`, `Rotation interval: 24 hours`,
  `dns get` → Block ads/trackers/malware `true`.

## Скорость: DAITA против multi-hop (живые замеры)

Метод, которому можно верить: `curl` на `speed.cloudflare.com/__down` (одиночный
поток 50 МБ) **плюс контроль реального потока по счётчикам интерфейса**
(`/sys/class/net/<wg-iface>/statistics/rx_bytes` до/после) — вывод curl умеет
показывать нереальные цифры, счётчик ядра не врёт. Настройки гоняются
`mullvad tunnel set daita` / `mullvad relay set multihop` и возвращаются на место.

| Сценарий | Одиночный поток |
|---|---|
| DAITA **on** + multi-hop on | ~36 Мбит/с |
| DAITA **off**, multi-hop on | ~72 Мбит/с |
| DAITA **off** + multi-hop off | ~78 Мбит/с |

- **DAITA режет одиночный поток примерно ×2.** Это её цена, а не баг: она добивает
  соединение пакетами-пустышками, чтобы по форме/таймингу трафика нельзя было понять,
  что ты делаешь. Для браузера, SSH, игр — чувствуется; для многопоточной закачки
  почти нет (туда упирается не VPN, а канал).
- **Multi-hop по скорости почти бесплатен** (~5 %), но добавляет второй хоп и
  латентность — насколько, зависит от того, куда ведёт вход (см. нюанс ниже).
- Фактический потолок задаёт **физический интерфейс**, а не VPN: проверяй
  `cat /sys/class/net/<iface>/speed` (гигабитный чип, договорившийся на 100 Мбит,
  режет всё до 100 — чаще всего кабель/порт роутера).

**Развилка — решает владелец, обе стороны честные:**

```bash
mullvad tunnel set daita off   # скорость важнее (принять потерю защиты от анализа трафика)
mullvad tunnel set daita on    # защита от анализа важнее (принять ×2 по скорости)
```

## Ротация ключа (зачем)

- **Ключ = отпечаток.** Mullvad выводит выходной IP **детерминированно из
  WireGuard-ключа** → смена стран/серверов **не рвёт связку**, пока ключ один
  (независимое исследование tmctmt, 2026: 3650 ключей → лишь **284 уникальных
  IP-набора**). Поэтому ключ **ротируют**.
- **Дефолт 30 дней (720 ч)** → ставим **24 ч**:
  `mullvad tunnel set rotation-interval 24`.
- Проверка: `mullvad tunnel get` → `Rotation interval: 24 hours`.
- Мгновенно сменить ключ: `mullvad tunnel set rotate-key` (заработает до ~2 мин).
- Откат к дефолту: `mullvad tunnel set rotation-interval 720`.

## Нюансы (проверено)

- **Multi-hop + DAITA:** DAITA может **переопределить** заданный вход —
  в статусе будет `(multihop entry overriden by DAITA)`. Это норма, не ошибка.
  **При выключенной DAITA это переопределение пропадает** → заработает твой
  `Multihop entry`, и если он далеко, латентность вырастет. Проверь
  `mullvad relay get` → `Multihop entry: country ??`; лечится сменой входа на
  соседнюю страну или `mullvad relay set multihop off`. Латентность живьём:
  `ping -c 4 <gateway-туннеля>` (шлюз виден в `ip route`).
- **Lockdown on = без VPN интернета нет вообще.** Это смысл kill switch, а не поломка.
  «Пропал интернет» → сначала `mullvad status`, потом чинить.
- **DAITA просаживает скорость ~×2** (одиночный поток) — см. раздел «Скорость».
  Это осознанный размен, не поломка; включение/выключение — решение владельца.
- **DNS-блокировки** иногда ломают отдельные сайты → снять:
  `mullvad dns set default` (без флагов).
- **IPv6 в туннеле** по умолчанию off — это анти-утечка; включать только осознанно
  (`mullvad tunnel set ipv6 on`).
- Срок/аккаунт — `mullvad account get` (в репозиторий **не тащить**: номер аккаунта
  и срок — приватные).
- Конфиг не правим руками — только через CLI/GUI; ключи не трогаем.

## Откат

```bash
mullvad lockdown-mode set off
mullvad auto-connect set off
mullvad tunnel set daita off
mullvad relay set multihop off
mullvad dns set default
mullvad tunnel set rotation-interval 720   # вернуть дефолт 30 дней
```

Каждая команда обратима и не требует sudo (демон работает под своим пользователем).

## References

- CLI-протокол: `mullvad help`, `mullvad tunnel set --help`, `mullvad dns set default --help`
- Ротация ключа (офиц.): https://mullvad.net/en/help/cli-command-wg — «default is 720 hours (30 days)»
- Зачем ротация: https://tmctmt.com/posts/mullvad-exit-ips-as-a-fingerprinting-vector/ (ключ = отпечаток; 3650 ключей → 284 IP-набора)
- Mullvad (офиц.): DAITA, lockdown mode, multi-hop, DNS content blocking
- Соседний референс: `09-vpn-torrents.md` (свой WireGuard-сервер с нуля)
