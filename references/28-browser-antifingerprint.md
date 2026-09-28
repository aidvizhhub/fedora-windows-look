# 28 · Браузер: IP и анти-отпечаток (Mullvad Browser / Firefox / Tor)

<!-- meta
категория: E-сеть-удалённый-доступ
риск: L1 (префы `about:config`/`user.js` и настройки браузера; без sudo; обратимо)
preflight-гейт: установлен Firefox и/или Mullvad Browser; профили в `~/.mozilla/firefox/`; NETWORK_ONLINE=yes
откат: удалить блок из `user.js` профиля → полный рестарт браузера; в Mullvad Browser вернуть префы/настройки
-->

Это **справочник по браузерному слою**. Не дублирует соседей: WebRTC-утечка локального IP —
`25`, VPN/убийца-выключатель — `24`, общая карта утечек (DNS, IPv6, приложения) — `26`.
Здесь — всё, что видит **страница через JS**: отпечаток, DoH, IPv6, прокси и почему
«уникально закрутить» хуже, чем «быть как все».

> Разметка: **[факт]** — есть в источнике; **[вывод]** — сложено из фактов; **[гипотеза]** — не проверено живьём.

---

## Главное за 30 секунд

| Хочешь | Бери | Почему |
|---|---|---|
| Чтобы сайт **не знал IP** | **Tor Browser** | 3 реле: ни один узел не знает оба конца [факт] |
| Сильный анти-отпечаток + нормальная скорость | **Mullvad Browser + VPN** | тот же движок, что Tor, но IP прячет VPN [факт] |
| Убить наивный трекинг в обычном Firefox | **arkenfox/user.js + RFP** | «толпу» не создаёт, но naive-скрипты ломает [факт] |
| Просто «закрутить всё в ноль» | **не надо** | уникальный отпечаток = палево, хуже толпы [факт] |

Ключевая мысль: **VPN закрывает IP-слой. Браузерный отпечаток VPN не закрывает** —
это другой слой, и он живёт дольше, чем сессия тунеля. [факт ×2]

---

## 1. Mullvad Browser vs Firefox+user.js vs Tor Browser

### Что каждый даёт

| | Tor Browser | Mullvad Browser | Firefox + user.js (arkenfox) |
|---|---|---|---|
| Скрывает IP от сайта | Да, через 3 реле [факт] | **Нет сам по себе** — нужен VPN [факт] | Нет |
| Анти-отпечаток | Унификация + большая толпа [факт] | Та же унификация, тот же аудированный движок [факт] | RFP: ломает naive-скрипты, толпы нет [факт] |
| .onion | Да | **Нет** [факт] | Нет |
| WebRTC | Выключен | **Включён** (нужен для звонков) [факт] | Зависит от префов |
| Постоянное состояние | Нет (private) | Нет (private по умолчанию) [факт] | Есть (куки/логины) |
| Расширения | NoScript | uBlock Origin + NoScript + Mullvad ext [факт] | Что поставишь |
| Скорость | Медленно (3 хопа) [факт] | Нативная [факт] | Нативная |

**Mullvad Browser — это Tor Browser без сети Tor** (форк Tor Browser, а не «скин Firefox»). [факт]
Он не анонимизирует как Tor: загрузишь на голом канале — сайт видит твой реальный IP, как в Chrome. [факт]

### Когда что

- **IP в логах сервера = риск** (свисток, хостильная страна, цензура) → **Tor Browser**, без замен. [факт]
- **Реклама строит профиль, куки уже почистил** → **Mullvad Browser**. Canvas/audio/WebGL/шрифты куки-гигиеной не лечатся. [факт]
- **Дневной серфинг + надо остаться залогиненным** → Firefox + arkenfox (принимаешь, что ты уникален, но не для продвинутых скриптов). [факт]
- **Tor медленный, а IP всё равно прячешь VPN'ом** → Mullvad Browser + VPN. [факт]

### Версии/актуальность 2026

- Stable-канал Mullvad Browser — на **Firefox ESR**; в GitHub-releases указано обновление до **Firefox 153.3.0esr** [факт]. Ранее 14.0 был на ESR 128 (релиз 19.11.2024) [факт].
- **Alpha 16.0a1** (26.03.2026) переехал на **Firefox Rapid Release**; апдейты каждые ~4 недели; добавлена поддержка **Linux ARM** (30.03.2026) [факт].
- Firefox ESR-ветки идут парами (140.x / 153.x) — stable Mullvad догоняет ESR, alpha — быстрый релиз. [факт/вывод]

---

## 2. DNS over HTTPS (DoH): чтобы DNS не утёк мимо VPN

### Что делает
DoH шлёт DNS-запросы по HTTPS к конкретному резолверу, минуя системный/провайдерский DNS. [факт]

### Префы Firefox (`about:config`)

`network.trr.mode` (TRR = Trusted Recursive Resolver) [факт, MozillaWiki 14.08.2026]:

| Значение | Смысл |
|---|---|
| `0` | Off (по умолчанию) — только системный DNS |
| `2` | First — TRR первым, при провале откат на системный |
| `3` | Only — только TRR, системный не используется |
| `5` | Off by choice — выключено осознанно и не перезапишется апдейтом |

`network.trr.uri` — URL DoH-сервера, например `https://dns.quad9.net/dns-query`. [факт]

В UI то же самое: **Settings → Privacy & Security → Enable secure DNS using → Max Protection** + провайдер. [факт]

### Грабли (важные)

- **Firefox по умолчанию включает DoH через Cloudflare** в US/Canada/Russia/Ukraine → DNS уходит **мимо VPN** на Cloudflare = утечка «какие сайты открываешь». [факт, Mullvad 24.06.2026]
- При подключённом **Mullvad VPN DoH надо ВЫКЛЮЧАТЬ** — DNS едет внутри туннеля, а публичный DoH только медленнее и светит запросы наружу. [факт ×2: Mullvad DoH-гайд, PrivacyGuides-форум]
- `network.trr.enable_when_vpn_detected` и `network.trr.enable_when_proxy_detected` (по умолчанию `false`): на **Windows** TRR сам выключается, если система видит VPN/системный прокси. [факт MozillaWiki]
- Даже в `mode=3` системный резолвер всё равно используется для **captive-portal detection** и телеметрии (`Bug 1593873`). [факт MozillaWiki]
- `network.trr.skip-AAAA-when-not-supported=true` — если IPv6-нет, AAAA не запрашиваются (частично защищает от IPv6-утечек DNS). [факт MozillaWiki]

### Mullvad Browser DoH

- Из коробки: **Mullvad DoH без fallback**; в настройках — **Max Protection** + `https://dns.mullvad.net/dns-query` (или adblock-вариант). [факт]
- **С 2 ноября 2026 публичный DoH/DoT Mullvad выключается**, поддержка — Quad9. Дефолтные настройки Mullvad Browser мигрируют на Quad9 автоматически; **свои кастомные URI надо менять руками**. [факт, 03.09.2026]

### SOCKS5 + DoH
Если включён Mullvad SOCKS5-прокси и **«Proxy DNS when using SOCKS v5»**, DNS идёт через прокси, а публичный DoH не используется (блокировщики в нём не работают). [факт Mullvad]

### Проверка
`https://mullvad.net/check` (бывший `my.mullvad.net/dnsleak` → редирект) — зелёный «No DNS leaks», сервер с `dns` в имени. [факт]. Плюс `dnsleaktest.com` (extended). [факт ref26]

**Правило:** под VPN — **DoH OFF**; без VPN — **DoH ON Max Protection** к доверенному резолверу. [вывод]

---

## 3. IPv6 в браузере: тихий обход IPv4-туннеля

### Что делает
Firefox **поддерживает IPv6 по умолчанию и предпочитает его IPv4**, а AAAA-записи запрашивает даже без IPv6-связности. Если VPN гонит только IPv4 — реальный IPv6 уходит мимо. [факт, hpc.mil]

### Как чинить (Firefox)
- `network.dns.disableIPv6 = true` — перестать запрашивать AAAA (лечит DNS-часть, **не** отключает сам IPv6-стек). [факт, mozillazine]
- `network.trr.skip-AAAA-when-not-supported` (см. DoH) — при DoH. [факт]
- На **системном** слое у Mullvad: `mullvad ipv6 set off` (по умолчанию не пускает IPv6 в туннель) — см. `26`. [факт ref26]

### Грабли
- **FoxyProxy 8 игнорирует `network.dns.disableIPv6`** — браузер всё равно коннектится по IPv6 (issue #102). [факт]
- Правильный порядок: **сначала системный слой** (`26`: `ip -6 route`, `mullvad ipv6 get`), потом браузер. [факт ref26]

### Chromium
Отдельного `about:`-флага нет; IPv6 регулируется ОС, WebRTC — политикой (см. `25`). [вывод]

Тест: `https://test-ipv6.com`; ждём отсутствие родного IPv6. [факт ref26]

---

## 4. Прокси-утечки: SOCKS5 vs HTTP

### Что делает SOCKS5
SOCKS5 умеет передавать **доменное имя** (ATYP=3), тогда резолвит **прокси**, а не ты. Firefox включает это только явным префом. [факт]

### Как настроить
- `network.proxy.socks_remote_dns = true` (в UI: **Proxy DNS when using SOCKS v5**). [факт]
- В `curl`: `socks5://` — резолвит **ты**, `socks5h://` — резолвит **прокси** (`h` = hostname). [факт]
- При SOCKS5-прокси и включённом remote DNS — **WebRTC-кандидаты** могут унести реальный внешний IP; см. `media.peerconnection.ice.proxy_only_if_behind_proxy` в `25`. [факт ref25]

### Почему HTTP-прокси хуже
- HTTP-прокси работает только с HTTP/HTTPS (для HTTPS — `CONNECT` с хостом), другие протоколы мимо. [вывод]
- Может дописывать заголовки (`X-Forwarded-For`, `Via`), что само по себе — маркер. [факт, fingerprint.com]
- Не несёт UDP → часть трафика (WebRTC) уйдёт напрямую. [вывод]

### Грабли FoxyProxy (проверено сообществом)
- FoxyProxy 8.9 в **Firefox 130** давал **DNS-утечку** при включённом «Proxy DNS», хотя нативный SOCKS5 + remote DNS **не** тёк. [факт, issue #154, 22.09.2024]
- Whonix-форум: тот же симптом — DNS идёт мимо SOCKS5 через FoxyProxy. [факт]
- Вывод: для чувствительного — **нативные настройки Firefox** надёжнее расширения-менеджера. [вывод]

---

## 5. Отпечаток, который выдаёт тебя и коррелирует с IP

### Что реально палит «ты под VPN»

| Сигнал | Как течёт | Почему коррелирует с IP |
|---|---|---|
| **Timezone** | `Intl.DateTimeFormat`, `getTimezoneOffset` | система UTC+3, выход UTC+2 → **несовпадение** = топ-признак VPN [факт] |
| **Язык** | `Accept-Language`, `navigator.language` | «страна выхода РФ, язык ru» vs «выход Австрия» — несостыковка [факт EFF] |
| **WebRTC** | ICE-кандидаты | локальный/реальный IP; разобрано в `25` |
| **WebGL renderer** | `WEBGL_debug_renderer_info` | `ANGLE (NVIDIA, NVIDIA GeForce RTX 3060...)` — точная железка [факт] |
| **Canvas** | `toDataURL()` + MD5 | рендер зависит от GPU/ОС/шрифтов → хэш [факт] |
| **Шрифты** | перебор списка | набор шрифтов = ОС + локаль [факт] |
| **Разрешение/DPR** | `screen`, `devicePixelRatio` | окно/экран в уникальном размере выдаёт вне толпы [факт] |
| **navigator.platform / touch** | JS/HTTP | нестыковка UA и платформы — маркер [факт] |
| **CPU** | `hardwareConcurrency`, `deviceMemory` | ещё одна ось уникальности [факт EFF] |

EFF Cover Your Tracks логирует именно это: UA, Accept-headers, разрешение+глубина, timezone,
шрифты/плагины, canvas-хэш, WebGL-хэш, DNT, platform, язык, touch. [факт]

### Таймзона — отдельно
Для сайтов рассинхрон «браузер говорит UTC+X, IP говорит UTC+Y» — **прямой признак VPN/прокси**;
«исправляется» сменой системной таймзоны, но это не всегда удобно. [факт, fingerprint.com 03.07.2025; trustmyip]
В реальности под Mullvad Browser timezone = **UTC** (RFP), и это **нормально** — ты в толпе. [факт]

### Как проверить себя (инструменты)
- `browserleaks.com` — IP, JS, WebRTC, Canvas, **WebGL**, Fonts. [факт]
- `coveryourtracks.eff.org` — уникальность + защита от трекеров. [факт]
- `amiunique.org` — статистика уникальности среди пользователей. [факт]
- `abrahamjuliot.github.io/creepjs/` — **детектор лжи**: ловит анти-детект-расширения и подмены. [факт]

---

## 6. Приём «не выделяться»: RFP, letterboxing, и почему уникальность — зло

### Что делает RFP (`privacy.resistFingerprinting=true`) [факт, Mullvad «hard facts»]
- timezone → **UTC**;
- **letterboxing** — окно округляется до кратности **200×100 px**;
- UA/ОС подменяются на «универсальные» (Tor: Win→Win10, macOS→10.15, Android→10, прочее→«Linux X11»);
- шрифты ограничены фиксированным набором; `prefers-color-scheme` → **light**;
- canvas-извлечение рандомизируется (`randomDataOnCanvasExtract`);
- тайминги загрублены (`reduceTimerPrecision`, jitter);
- отключены WebSpeech, gamepad, sensors, performance API.

Префы Mullvad Browser (полный список) [факт, 13.01.2026]:
```
privacy.resistFingerprinting = true
privacy.resistFingerprinting.letterboxing = true
privacy.resistFingerprinting.randomDataOnCanvasExtract = true
privacy.resistFingerprinting.reduceTimerPrecision.jitter = true
privacy.resistFingerprinting.reduceTimerPrecision.microseconds = 1000
privacy.resistFingerprinting.target_video_res = 480
```

### Философия: толпа, а не «я невидим»
Задача не «сделать тебя нечитаемым», а «чтобы все выглядели одинаково». **Каждый твой тюнинг
выкидывает тебя из толпы**. [факт, Tor Project; Privacy Ranker]

### Как «быть как все» (Mullvad/Tor)
1. **Не менять размер окна** — не максимизировать, не тащить в случайный размер: letterboxing ломается, а размер — маркер. [факт]
2. **Не добавлять/не трогать расширения** — uBlock Origin/NoScript оставить как есть; снятие/перенастройка = уникальность. Mullvad ext можно удалить без вреда, но и оставить безопасно. [факт]
3. **Security level менять только с перезапуском** — иначе настройки не применяются полностью. [факт, Privacy Guides]
4. **Не переключать тему** — под RFP `prefers-color-scheme` = light; смена темы выделяет. [факт]
5. Для логов — отдельный браузер (Firefox+arkenfox), для чувствительного — Mullvad/Tor. [факт]

### Firefox+user.js (arkenfox) — честные границы
- RFP «не течёт» реальными значениями и ломает **naive**-скрипты; **advanced**-скрипты требуют толпы — этого arkenfox **не даёт**. [факт, arkenfox 04.08.2026]
- «Несколько префов» не делают тебя более уникальным — ты **уже уникален** без всего. [факт, arkenfox]
- FPP (`fingerprintingProtection`, Firefox 120+) — мягкая альтернатива: рандомизирует canvas на eTLD+1/сессию. [факт]
- Цена RFP: timezone UTC0, всегда светлая тема, ломаются отдельные сайты, refresh прибит к 60 Hz. [факт, archwiki]

---

## 7. Что НЕ решает браузер

- **Логины и куки.** Вход в личный аккаунт мгновенно пришивает к сессии твою личность — самый частый способ деанона Tor-юзеров, и это провал поведения, а не инструмента. [факт, Privacy Ranker]
- **Уже утёкший IP / связки аккаунтов.** Браузер не отменяет прошлое; email/ник/git-`user.email` — тоже «палево IP» руками. [факт/вывод, `26`/`27`]
- **Слой ОС.** DNS/IPv6/утечки приложений (Telegram/Discord/торрент) браузер не закрывает. [факт, `26`]
- **Persistent-состояние в обычных браузерах.** Куки/кэш/логины переживают смену IP и связывают сессии. [вывод]
- **Mullvad Browser сам по себе не прячет IP** — без VPN сайт видит реальный адрес. [факт]

«New Identity» в Mullvad Browser чистит куки/историю, но **не меняет IP** — надо вручную переключить
сервер VPN. [факт, Mullvad]

---

## Verify (только факты)

1. `https://mullvad.net/check` — IP = выход VPN; «No DNS leaks».
2. `https://browserleaks.com/ip` + `/webrtc` — только IP выхода, ни одного `192.168.*/10.*/fe80::` (`25`).
3. `https://test-ipv6.com` — нет родного IPv6.
4. `https://dnsleaktest.com` (extended) — DNS = страна VPN.
5. `https://coveryourtracks.eff.org` — в Mullvad Browser «fingerprint resembles many others».
6. `about:config` → `network.trr.mode` (0/5 под VPN) и `privacy.resistFingerprinting` (true у Mullvad).

---

## Слабые места / не проверено

- **[не проверено живьём]** Всё выше собрано из источников, не из наших прогонов на Fedora 44. Реальная верифа — за владельцем (пункт Verify).
- **[гипотеза]** Насколько web-сайты 2026 реально считают timezone-mismatch — зависит от анти-фрода; fingerprint.com описывает метод, но массовость неизвестна.
- **[не проверено]** Точная текущая версия stable Mullvad (это ESR-догон) — брал GitHub-releases; перед инструкцией сверить на месте.
- **[не проверено]** Конкретный DoH-резолвер после 02.11.2026 (Quad9) в нашей сети — пинги/anycast могут отличаться.
- **[гипотеза]** `network.dns.disableIPv6` — не панацея: лечит AAAA-запросы, но не отключает IPv6-стек; полный запрет — на системном слое (`26`).
- **[не проверено]** Поведение FoxyProxy актуальных версий (баг #154 от 2024) — мог быть починен; но принцип «нативный SOCKS5 надёжнее» остаётся [вывод].
- **[пробел]** Не разбирал fingerprinting через AudioContext, WebGPU, `navigator.connection` — следующий заход.
- **[пробел]** Ref 25 фокусируется на WebRTC/IP; здесь WebRTC затронут обзорно, глубина — там.

---

## References (с датами доступа)

**Первоисточники (проект/Mozilla/Tor):**
- Mullvad: «The Mullvad Browser hard facts» — обновлено **13.01.2026**: https://mullvad.net/en/browser/hard-facts
- Mullvad Help: «DNS over HTTPS and DNS over TLS» — **03.09.2026**: https://mullvad.net/en/help/dns-over-https-and-dns-over-tls
- Mullvad Help: «How to prevent DNS leaks» — **24.06.2026**: https://mullvad.net/en/help/dns-leaks
- Mullvad Blog: «Shutting down our public encrypted DNS servers…» — **03.09.2026**: https://mullvad.net/en/blog/shutting-down-our-public-encrypted-dns-servers-and-sponsoring-quad9-instead
- Mullvad Blog: «Mullvad Browser 14.0 released» (ESR 128) — **19.11.2024**: https://mullvad.net/en/blog/mullvad-browser-140-released
- Mullvad Browser releases (Firefox 153.3.0esr; alpha 16.0a1 → Rapid Release 26.03.2026): https://github.com/mullvad/mullvad-browser/releases · https://mullvad.net/en/blog/mullvad-browser-alpha-moves-to-firefox-rapid-release-and-adds-linux-arm-support
- Mullvad: «Tor without the Tor Network»: https://mullvad.net/en/browser/tor-without-tor
- MozillaWiki: «Trusted Recursive Resolver» (`network.trr.*`) — **14.08.2026**: https://wiki.mozilla.org/Trusted_Recursive_Resolver
- Mozilla Support: «DNS over HTTPS (DoH) FAQs» — **02.12.2024**: https://support.mozilla.org/en-US/kb/dns-over-https-doh-faqs
- Tor Project Support: «How Tor Browser protects you against browser fingerprinting»: https://support.torproject.org/tor-browser/features/fingerprinting-protections/
- MozillaWiki: «Network.dns.disableIPv6» / «Network.proxy.socks_remote_dns»: https://kb.mozillazine.org/Network.dns.disableIPv6 · https://kb.mozillazine.org/Network.proxy.socks_remote_dns

**Гайды/рейтинги:**
- Privacy Guides: «Desktop Browsers» — **24.05.2026**: https://www.privacyguides.org/en/desktop-browsers/
- Privacy Ranker: «Tor Browser vs Mullvad Browser» — **18.08.2026**: https://privacyranker.com/posts/tor-browser-vs-mullvad-browser/
- ArchWiki: «Firefox/Privacy» — **28.04.2026**: https://wiki.archlinux.org/title/Firefox/Privacy
- arkenfox wiki: «3.3 Overrides [To RFP or Not]» — **04.08.2026**: https://github.com/arkenfox/user.js/wiki/3.3-Overrides-%5BTo-RFP-or-Not%5D
- hpc.mil: «IPv6 and Mozilla Firefox»: https://www.hpc.mil/solution-areas/networking/ipv6-knowledge-base/ipv6-knowledge-base-applications/ipv6-and-mozilla-firefox

**Анти-фрод/отпечаток:**
- Fingerprint.com: «How to detect a VPN» — **03.07.2025**: https://fingerprint.com/blog/vpn-detection-how-it-works/
- EFF: «About Cover Your Tracks»: https://coveryourtracks.eff.org/about
- AmIUnique FAQ: https://amiunique.org/faq
- BrowserLeaks: Canvas / WebGL / WebRTC / Fonts: https://browserleaks.com/canvas · https://browserleaks.com/webgl · https://browserleaks.com/webrtc · https://browserleaks.com/fonts
- CreepJS (детектор лжи анти-детект-тулов): https://github.com/abrahamjuliot/creepjs
- donutbrowser: unmasked vendor/renderer (`ANGLE (NVIDIA …)`): https://donutbrowser.com/browser-fingerprinting/
- Chromium policy `WebRtcIPHandling` (`disable_non_proxied_udp`): https://chromeenterprise.google/policies/web-rtc-ip-handling/

**Грабли прокси:**
- FoxyProxy issue #154 «DNS leak in Firefox 130» — **22.09.2024**: https://github.com/foxyproxy/browser-extension/issues/154
- FoxyProxy issue #102 «ignores network.dns.disableIPv6»: https://github.com/foxyproxy/browser-extension/issues/102
- Whonix: «SOCKS5 DNS leak using FoxyProxy»: https://forums.whonix.org/t/socks5-dns-leak-using-foxyproxy-in-firefox-esr/17007
- SOCKS5H vs SOCKS5 (remote DNS): https://maskproxy.io/blog/socks5h-vs-socks5-proxy-dns-resolves/

**Соседние референсы:** `24-mullvad-vpn-hardening.md` (VPN), `25-webrtc-ip-leak-firefox.md` (WebRTC),
`26-ip-leak-map.md` (карта DNS/IPv6/приложений), `27-host-without-home-ip.md` (наружу без домашнего IP).
