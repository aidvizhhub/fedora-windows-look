# 22 · RustDesk: "Wayland requires higher version of linux distro" (сам захват)

<!-- meta
категория: E-сеть-удалённый-доступ
риск: L1→L2 (перезапуск сессионных служб — без sudo; `sudo systemctl restart rustdesk` — L2, обратимо)
preflight-гейт: SESSION_TYPE=wayland (на X11 этой ошибки нет) + DE=GNOME (путь портала gnome)
откат: в файле: конфиг не меняем — только перезапуск служб; запасной путь — сессия «GNOME on Xorg»
-->

Verified live: Fedora 44, GNOME 50, Wayland, RustDesk **1.4.9**, PipeWire
**1.6.9**, xdg-desktop-portal-gnome **50.0** (ScreenCast v5). Error reproduced
and cleared by restarting the portal stack.

## Сообщение врёт

```
Для Wayland требуется более поздняя версия дистрибутива Linux.
Используйте рабочий стол X11 или смените ОС.
```

Это **общая заглушка RustDesk**, а НЕ проверка версии дистрибутива. Смотри
исходник `src/server/wayland.rs` → `map_err_scrap`: если захват по Wayland
падает и в тексте ошибки встречается `pipewire` (в старых сборках ещё
`org.freedesktop.portal` / `dbus`), RustDesk отдаёт ровно эту строку. Перевод:
**«мост PipeWire/xdg-desktop-portal не поднялся на этом подключении»**, а не
«твоя ОС устарела».

Проверь факты — система почти наверняка подходит с запасом:

```bash
pipewire --version                                   # Compiled/Linked с libpipewire X.Y
rpm -q xdg-desktop-portal-gnome pipewire
busctl --user get-property org.freedesktop.portal.Desktop \
  /org/freedesktop/portal/desktop org.freedesktop.portal.ScreenCast version   # ждём число (напр. 5)
```

Если `ScreenCast version` отвечает числом, а PipeWire свежий — «старая ОС» не
при чём, проблема в конкретной сессии захвата.

## Почему возникает

- **Гонка на загрузке (главная причина после обновления/ребута).**
  `rustdesk.service` — системная служба, стартует раньше пользовательской
  сессии. На этом хосте сервис поднялся в 14:54:08, а `pipewire` — 14:55:36,
  портал — 14:55:39 (на ~1.5 мин позже). Захват пытается инициализироваться,
  когда моста ещё нет → падение с этой ошибкой → висит до перезапуска.
- **Отклонён диалог GNOME «Поделиться экраном»** при подключении — портал не
  выдал поток, ошибка та же.
- **Портал упал/перезапускался** (обновление пакетов, краш) — старая сессия
  захвата повисает.
- **Удалёнка ДО логина** — экран входа по Wayland не отдаётся вообще, нужен X11
  (документированное ограничение RustDesk).

Это не регрессия «ядра» как таковая: свежий бут просто расставляет службы в
неверном порядке.

## Диагностика (read-only)

```bash
# кто когда стартовал — видно гонку service vs pipewire/portal
for u in pipewire wireplumber xdg-desktop-portal xdg-desktop-portal-gnome; do
  printf "%-28s " "$u"; systemctl --user show "$u" -p ActiveEnterTimestamp --value; done
systemctl show rustdesk -p ActiveEnterTimestamp --value

# портал жив и отдаёт ScreenCast?
busctl --user is-active org.freedesktop.portal.Desktop
busctl --user get-property org.freedesktop.portal.Desktop \
  /org/freedesktop/portal/desktop org.freedesktop.portal.ScreenCast version
```

Если портал `active` и версия отвечает — дело в залипшем состоянии сессии,
лечится перезапуском связки, а не переустановкой ОС.

## Фикс

```bash
# 1. Протолкнуть сессионное окружение в dbus/systemd (чтобы портал видел сессию)
dbus-update-activation-environment --systemd \
  WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP

# 2. Перезапустить портал и RustDesk-сервер
systemctl --user restart xdg-desktop-portal-gnome
systemctl --user restart xdg-desktop-portal
sudo systemctl restart rustdesk

# 3. Переподключиться и РАЗРЕШИТЬ диалог «Поделиться экраном» (первый раз спрашивает)
```

Порядок важен: сначала бэкенд `-gnome`, потом сам портал. Сервер RustDesk
после рестарта пересоздаёт `--server`/`--tray` и заново договаривается с
порталом.

**Запасной путь (если Wayland всё равно капризничает):** на экране входа
выбрать сессию **«GNOME on Xorg»** — там RustDesk работает по X11, портал не
нужен. Для удалённого доступа **до логина** X11 обязателен всегда.

## Verify

```bash
systemctl --user is-active xdg-desktop-portal xdg-desktop-portal-gnome pipewire   # все active
systemctl is-active rustdesk                                                       # active
busctl --user get-property org.freedesktop.portal.Desktop \
  /org/freedesktop/portal/desktop org.freedesktop.portal.ScreenCast version        # отвечает числом
```

Затем — живое подключение с клиента: экран должен отдаваться, без баннера про
«позднюю версию».

## Грабли

- **Кириллица в консоли не при чём**, но при рестарте `xdg-desktop-portal`
  команда в сессии может получить `Killed by SIGKILL` (transient-scope) — это
  не поломка: сессия (`gnome-shell`) не перезапускается, аптайм тот же, в
  логах oomd чисто. Проверь `systemctl show org.gnome.Shell@user.service -p
  ActiveEnterTimestamp`.
- **RustDesk Wayland — экспериментальная ветка** (с 1.2.0). Если нужен
  железобетонный удалённый доступ, X11-сессия надёжнее.
- **Не путать с «Failed to obtain screen capture. You may need to upgrade the
  PipeWire library»** — это отдельный код ошибки (PipeWire-стрим не отдал
  кадры), чаще лечится обновлением PipeWire; на Fedora 44 с PipeWire 1.6.9 не
  встречается.

## Связанные

- Чёрный экран у партнёра / FPS: `references/07-rustdesk-games.md`.
- Партнёр не слышит звук: `references/20-rustdesk-audio.md`.
- Общий аудит «тихих» служб (в т.ч. удалёнок): `references/21-background-services.md`.
