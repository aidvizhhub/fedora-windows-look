# 25 · WebRTC: утечка локального IP в браузере (Firefox, `user.js`)

<!-- meta
категория: E-сеть-удалённый-доступ
риск: L1 (правка `user.js` профиля браузера; без sudo; обратимо удалением блока)
preflight-гейт: установлен Firefox; профили есть в `~/.mozilla/firefox/<profile>/`
откат: удалить блок «Анти-утечка WebRTC» из `user.js` профиля → перезапустить браузер
-->

Verified live: Fedora 44, GNOME 50, Wayland; настройки добавлены в `user.js` каждого
профиля Firefox (применяются при старте, не сбрасываются при обновлении). Реальные
IP и идентификаторы ниже не приводятся.

## Почему это нужно

**WebRTC** — технология браузера для звонков и прямой (peer-to-peer) передачи данных.
Чтобы два браузера нашли друг друга, каждый собирает список **ICE-кандидатов** —
адресов, по которым до него можно достучаться. Браузер сам кладёт туда:

- **host-кандидаты** — локальные адреса (`192.168.x.x`, `10.x`, `fe80::`);
- **srflx-кандидаты** — публичный адрес, как его видит STUN-сервер.

Любой сайт может запросить этот список через JS и прочитать твою **локальную сеть**.
Под VPN публичный адрес прикрыт туннелем, а **локальный — нет**: это утечка и лишний
отпечаток (диапазон `192.168.0.0/24` и т.п. сужает круг). Ситуация усугубляется, если
браузер настроен на **прокси** — тогда srflx-кандидат может унести реальный внешний IP.

Выключать WebRTC «в ноль» тоже не всегда хорошо: сам факт выключенного WebRTC —
такой же отпечаток, как и утечка (ты выделяешься из толпы). Поэтому базовый уровень —
**убрать утечку, оставить звонки живыми**.

## Диагностика (read-only)

```bash
ls -1 ~/.mozilla/firefox/*/user.js            # в каких профилях уже есть user.js
grep -R 'media.peerconnection' ~/.mozilla/firefox/*/user.js   # что уже выставлено
pgrep -a firefox                              # браузер запущен? (тогда правки — только в user.js)
```

Профили перечислены в `~/.mozilla/firefox/profiles.ini` (реальные — те, что там есть;
прочие папки трогать не нужно).

## Что применить

Дописать в `user.js` каждого профиля (`~/.mozilla/firefox/<profile>/user.js`):

```js
// === Анти-утечка WebRTC ===
user_pref("media.peerconnection.ice.no_host", true);                 // не выпускать локальные адреса
user_pref("media.peerconnection.ice.default_address_only", true);     // только интерфейс дефолтного маршрута
user_pref("media.peerconnection.ice.proxy_only_if_behind_proxy", true); // при прокси — ICE только через него
// Жёстко вырубить WebRTC целиком (ломает браузерные звонки/веб-мессенджеры) — раскомментировать:
// user_pref("media.peerconnection.enabled", false);
```

Пакетно (идемпотентно, по всем профилям):

```bash
BLOCK='user_pref("media.peerconnection.ice.no_host", true);
user_pref("media.peerconnection.ice.default_address_only", true);
user_pref("media.peerconnection.ice.proxy_only_if_behind_proxy", true);'
for f in ~/.mozilla/firefox/*/user.js; do
  grep -q 'peerconnection.ice.no_host' "$f" || printf '%s\n' "$BLOCK" >> "$f"
done
```

**Грабли (проверено):**

- Правка **только через `user.js`**. Редактировать `prefs.js` при запущенном Firefox
  бессмысленно — браузер перезапишет файл при закрытии.
- `user.js` **подхватывается при старте** → нужен полный перезапуск Firefox, не просто
  новая вкладка.
- Глоб по `~/.mozilla/firefox/*/` цепляет **служебные папки** (`Crash Reports`,
  `Pending Pings`, `firefox-mpris`, `Profile Groups`) — туда `user.js` не нужен, лучше
  брать список профилей из `profiles.ini` или удалить лишнее.
- Имена префов — из MozillaWiki, не «на память»:
  `media.peerconnection.ice.no_host` (убрать host-кандидаты),
  `media.peerconnection.ice.default_address_only` (только дефолтный интерфейс),
  `media.peerconnection.ice.relay_only` (жёстче — только relay-кандидаты),
  `media.peerconnection.enabled` (полный выключатель).

## Verify (только факты)

1. Полностью закрыть и открыть Firefox.
2. Открыть тест утечки: `https://browserleaks.com/webrtc` (или `mullvad.net/en/check`).
3. Ожидаем: виден **только IP VPN-выхода**, ни одного `192.168.*` / `10.*` / `fe80::`.

Проверка, что преф применился (без глазами-по-настройкам):

```
about:config  →  поиск media.peerconnection  →  no_host = true
```

Осторожно с пробой на `about:blank`: там инъекции страниц не работают и картина
может врать — тестировать на реальном https-сайте.

## Уровни защиты (от мягкого к жёсткому)

1. **Базовый (этот референс):** `no_host` + `default_address_only` + `proxy_only_if_behind_proxy`
   — локальный IP не течёт, звонки работают.
2. **Жёсткий:** `media.peerconnection.enabled = false` — WebRTC нет вообще.
   Цена: не работают браузерные звонки, веб-мессенджеры, часть конструкторов; плюс
   сам факт «выключено» — отпечаток.
3. **По-взрослому:** **Mullvad Browser** (или Tor Browser) — там RFP (анти-отпечаток)
   и WebRTC настроены из коробки, и ты не отличаешься от остальных пользователей.
   Для всего чувствительного — только он.

**Chromium-браузеры (Chrome, Brave, Chromium):** отдельного флага в `about:` нет.
Управление — через политику (`/etc/opt/chrome/policies/managed/*.json`,
`/etc/opt/brave.com/policies/managed/*.json`):

```json
{ "WebRtcIPHandlingPolicy": "disable_non_proxied_udp" }
```

Значения: `default_public_interface_only` (не светить локальный IP),
`disable_non_proxied_udp` (жёстче — не пускать UDP мимо прокси/VPN). Ставить только
осознанно — жёсткое значение ломает часть WebRTC.

## Нюансы (проверено)

- Современный Firefox **уже** подменяет host-кандидаты на mDNS-имена (`*.local`), так
  что утечка локального IP частично закрыта из коробки. `no_host` — это ремень к
  подтяжкам; критично он важен, когда браузер ходит через прокси.
- VPN сам по себе **не закрывает WebRTC** — это разные слои: туннель прячет адрес
  пакетов, а ICЕ-кандидаты формирует браузер и отдаёт их странице.
- Настройка **не заменяет** анти-отпечаток: время, шрифты, canvas, WebGL и прочее
  остаются. Для анонимности смотри пункт 3 «по-взрослому».
- Правка per-profile: если браузер запускается с другим профилем, применить нужно и к нему.

## Откат

Удалить из `user.js` профиля блок `=== Анти-утечка WebRTC ===` (или строки
`media.peerconnection.ice.*`) и перезапустить Firefox. Без sudo, систему не задевает.

## References

- MozillaWiki, Media/WebRTC/Privacy (имена и смысл префов ICE):
  https://wiki.mozilla.org/Media/WebRTC/Privacy
- Mozilla Bug 1304600 (default_address_only vs no_host vs relay_only):
  https://bugzilla.mozilla.org/show_bug.cgi?id=1304600
- Тест утечки: https://browserleaks.com/webrtc · https://mullvad.net/en/check
- Соседние референсы: `24-mullvad-vpn-hardening.md` (VPN-слой), `21-background-services.md`
