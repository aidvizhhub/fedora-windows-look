# 23 · GTK/WebKit-окна лагают на NVIDIA+Wayland (GPU выключен) + залипший процесс после обновления

<!-- meta
категория: B-производительность
риск: L1 (процессный env-переменный флаг; систему и драйвер не трогаем, обратимо)
preflight-гейт: GPU_VENDOR=nvidia + SESSION_TYPE=wayland (только эта связка болеет; AMD/Intel/nouveau — не трогать)
откат: убрать переменную из лаунчера/.desktop/скрипта запуска и полностью перезапустить приложение (не только окно)
-->

Verified live: Fedora 44, GNOME (Wayland), **GTX 1660 SUPER**, NVIDIA **615.71.09**.
Симптом и фикс воспроизведены и сняты на живом приложении (окно VOICEog на
`wry`/`tao`, движок WebKitGTK).

## Симптом

Нативное десктоп-окно (GTK-приложение, движок **WebKitGTK**, в т.ч. окна на
`wry`/`tao`/Electron-подобной обвязке) **лагает**: тугой скролл, рывковая
перерисовка, «стеклянность» интерфейса. При этом **та же самая страница в
обычном браузере** (Chromium/Firefox) — **плавная**.

Ключ к разгадке — **это не код приложения и не сайт**: рендерят-то разные
движки с разным доступом к GPU. Браузер взял GPU, окно приложения — нет.

## Почему

### Причина №1 — рендер через CPU (битая связка GTK/egl-wayland на NVIDIA)

На **NVIDIA-proprietary + Wayland** связка GTK + `egl-wayland` разваливается на
**explicit sync**. Окно падает с:

```
Gdk-Message: Error 71 (Protocol error) dispatching to Wayland display
```

Чтобы окно вообще не падало, обёртки/приложения лечат это **выключением
GPU-ускорения** — например `WEBKIT_DISABLE_DMABUF_RENDERER=1`. Тогда всё
рисуется на CPU → те самые лаги. Компромисс «чтобы не крашилось — рисуем
процессором».

Апстрим не чинён: основной баг **280210** (тот самый `Error 71` на NVIDIA+Wayland)
— **открыт (NEW)**; а отдельный баг **262607** (авто-отключение DMABuf-ускорения
именно для NVIDIA) закрыт **WONTFIX**. То есть «само не починится».

### Причина №2 — залипший процесс после обновления (вторая, отдельная грабля)

Если приложение **обновили** (rpm/deb/AppImage), уже **запущенный** процесс
продолжает крутить **старый код**: на Linux замена файла на диске **не**
перезапускает процесс — он держит открытый inode старой версии. У такого
процесса:

```bash
readlink /proc/PID/exe     # → путь с пометкой "(deleted)"
```

И он остаётся в старом (CPU) режиме, хотя на диске уже новый бинарь. Отсюда
классика: **«я обновил — а оно всё равно лагает»**. Лечение — **полностью
закрыть и запустить заново**, а не просто «перечитать страницу».

## Диагностика (read-only)

```bash
# 1. Держит ли окно GPU? Виден ли WebKit-процесс у NVIDIA?
nvidia-smi | grep -i webkit          # пусто → рендер на CPU

# 2. Не крутится ли старый код после обновления?
pid=$(pgrep -f -i voiceog | head -1) # свой процесс по имени
readlink /proc/$pid/exe              # путь с "(deleted)" → процесс старый, нужен перезапуск

# 3. Открыт ли рендер-узел GPU у процесса?
ls -l /proc/$pid/fd | grep -i dri    # ждём .../dri/renderD128
```

Проверить, не выставлены ли «лечебные» флаги отключения GPU у веб-процесса:

```bash
tr '\0' '\n' < /proc/$pid/environ | grep -Ei 'WEBKIT|GDK|__NV|DISABLE'
# WEBKIT_DISABLE_DMABUF_RENDERER=1 → GPU выключен, отсюда лаг
```

Быстрый диагноз: `nvidia-smi | grep -i webkit` **пусто** + в env стоит
`WEBKIT_DISABLE_DMABUF_RENDERER=1` → это ровно наш случай.

## Фикс

Цель — **сохранить GPU** и погасить только поломку explicit sync:

```bash
# Правильно: гасим ТОЛЬКО explicit sync — DMABUF/GPU продолжают работать
__NV_DISABLE_EXPLICIT_SYNC=1 ./voiceog
```

Проверено живьём: после флага WebKit-процесс **держит `/dev/dri/renderD128`**
и **виден в `nvidia-smi`** — рендер снова на GPU, лаги уходят.

**Альтернатива** (если приложению мешает поздняя инициализация GL): `GDK_GL=always`
— заставляет GTK поднять GL-контекст на старте.

Как выставлять у себя:

```bash
# разово, из терминала
__NV_DISABLE_EXPLICIT_SYNC=1 /usr/bin/voiceog

# .desktop-лаунчер: подставить в Exec=
# Exec=env __NV_DISABLE_EXPLICIT_SYNC=1 /usr/bin/voiceog %U

# launcher-скрипт
export __NV_DISABLE_EXPLICIT_SYNC=1
```

**Флаг процессный, не системный.** Он влияет только на это приложение — игры и
систему не задевает (в отличие от прописывания в `/etc/environment`). Это важно:
начиная с драйвера **575.51.02 / 575.57.08** этой же переменной глушатся ещё
Vulkan/GLX-синк-пути (это прямо в changelog NVIDIA: переменную «extended… to also
apply to GLX and Vulkan applications»), поэтому держим её **только на процесс**,
а не на всю сессию.

### Лончеры не должны форсить DMABUF=1

Частая причина залипшего лага — лаунчер/обёртка из старой версии (или «чтоб не
крашилось») жёстко ставит `WEBKIT_DISABLE_DMABUF_RENDERER=1`. Тогда даже с
правильным флагом GPU не поднимется. Убери форс из `.desktop`/скрипта —
пусть GPU включается штатно.

## Проверка

```bash
# после запуска с __NV_DISABLE_EXPLICIT_SYNC=1
pid=$(pgrep -f -i voiceog | head -1)

nvidia-smi | grep -i webkit                 # ТЕПЕРЬ виден WebKit-процесс (GPU работает)
ls -l /proc/$pid/fd | grep -i dri            # держит /dev/dri/renderD128
readlink /proc/$pid/exe                      # без "(deleted)" → крутится актуальная версия (после перезапуска)
```

Живой критерий: скролл/перерисовка плавные, окно как браузер. Если `nvidia-smi`
по-прежнему пуст — вернись к шагу «лончеры не должны форсить DMABUF=1» и
убедись, что процесс **перезапущен** (см. грабли).

## Грабли

- **Залипший процесс после обновления.** Самая коварная: обновил пакет — а
  `readlink /proc/PID/exe` показывает `(deleted)`, и старый процесс продолжает
  тормозить в CPU-режиме. Полностью закрой и запусти заново; «перезагрузить
  страницу» не спасает.
- **Драйвер 575.57.08+:** `__NV_DISABLE_EXPLICIT_SYNC=1` гасит ещё и Vulkan/GLX
  (changelog NVIDIA) — поэтому **только на процесс**, не глобально в
  `/etc/environment`.
- **Не совмещать флаги.** Совмещать не нужно: `WEBKIT_DISABLE_DMABUF_RENDERER=1`
  сам выключает GPU, `__NV_*` в этом случае ни к чему (и по репортам такая пара
  конфликтует — без гарантий). Ставим **что-то одно**: либо `__NV_*` (GPU), либо
  `WEBKIT_*` (CPU), но не оба.
- **X11/XWayland + NVIDIA:** GPU там всё равно не заводится — сыплет
  `Failed to create GBM buffer`; **разумно оставить CPU**, но без краша.
  `Error 71` на X11 не бывает — он только Wayland-шный.
- **AMD / Intel / nouveau:** проблемы нет, ничего не трогать.

## Связанные

- Вид «как на винде» и общий лук системы: `references/03-windows-look.md`.
- Общий аудит «что жрёт систему / почему тормозит»: `references/01-speedup.md`,
  `references/21-background-services.md`.
- Первоисточники: WebKit bug 280210 (NEW) —
  `bugs.webkit.org/show_bug.cgi?id=280210`; WebKit bug 262607 (WONTFIX) —
  `bugs.webkit.org/show_bug.cgi?id=262607`;
  Linux-графика Tauri — `v2.tauri.app/develop/debug/linux-graphics/`;
  NVIDIA-квирк WebKitGTK — `docs.rs/webkit2gtk-nvidia-quirk`;
  NVIDIA 575 changelog (`__NV_DISABLE_EXPLICIT_SYNC` → GLX/Vulkan) —
  `forums.developer.nvidia.com/t/575-release-feedback-discussion/330513`.
