# 11 · Rear line-out jack is dead while front works (Realtek HDA pin disabled)

<!-- meta
категория: C-железо-периферия
риск: L2 (hda-verb + systemd-юнит; обратимо)
preflight-гейт: AUDIO_CODEC=realtek (кодек/пин — ИЗ preflight, не из примера!)
откат: в файле: удалить systemd-юнит / пин в 0x00
-->

Verified live: Fedora (GNOME, PipeWire + WirePlumber), Realtek HDA codec
(HDA Intel PCH). Symptom: headphones in the **rear green jack** are silent,
front panel jack works fine; the system "does not see" the rear output. Root
cause: the rear line-out **pin is disabled in the codec** (`Pin-ctls: 0x00`),
while the front pin is active (`Pin-ctls: 0xc0`). Fix: enable the pin with one
`hda-verb` command + a systemd unit so it survives reboots. No personal data
below — only generic paths and placeholders.

## Why it matters

- On Realtek HDA chips (ALC887/897/1220 class) a **dead rear green jack with a
  working front jack is usually NOT hardware failure** — it is a codec pin
  left disabled (known widespread issue, see References). The same chip
  plays fine on Windows because the vendor driver enables the pin.
- The front panel jack and the rear green jack are **two different pins of the
  same sound chip**. PipeWire/WirePlumber names them by function:
  - rear green = **"Line Out"** (`analog-output-lineout`)
  - front panel = **"Headphones"** (`analog-output-headphones`)
  This naming is confusing: plug your headphones into the front jack and the
  UI says "Headphones"; plug them into the rear green and the UI says
  "Line Out". Sound follows the **selected port**, not the physical plug.
- If the pin is disabled, selecting the right port does nothing — the channel
  is unmuted, the sink is RUNNING, but the pin simply does not output.

## Diagnosis (read-only, no fixes yet)

### 1. Which card, which codec

```bash
aplay -l                    # find your analog card (e.g. card 0: HDA Intel PCH)
ls /dev/snd/hwC*D0          # codec devices: hwC0D0, hwC1D0, ...
cat /proc/asound/card0/codec#0 | head -2   # Codec: Realtek HDA (модель в preflight AUDIO_CODEC)
```

### 2. Find the rear line-out pin in the codec dump

```bash
cat /proc/asound/card0/codec#0 | grep -B2 -A8 "Line Out at Ext Rear"
```

Look at the pin block: `Pin Default 0x01014010: [Jack] Line Out at Ext Rear`,
`Conn = 1/8, Color = Green`. Note its **Node** (usually `0x14`). Now read the
pin state:

```bash
cat /proc/asound/card0/codec#0 | grep -A8 "Node 0x14"
```

| State | Meaning |
|---|---|
| `Pin-ctls: 0x40: OUT` | ✅ pin enabled, sound can flow |
| `Pin-ctls: 0x00:` | 🔴 pin disabled — **this is the bug** |
| `EAPD 0x2: EAPD` | amplifier powered (if `0x0`/missing — also a problem) |

Compare with the front pin (`HP Out at Ext Front`, usually `0x1b`): a working
front jack will show `Pin-ctls: 0xc0: OUT HP`.

## The fix (what was applied)

### 1. Enable the pin (immediate test)

```bash
sudo hda-verb /dev/snd/{CARD_DEV} {REAR_LINEOUT_NID} SET_PIN_WIDGET_CONTROL 0x40
# example: sudo hda-verb /dev/snd/hwC0D0 0x14 SET_PIN_WIDGET_CONTROL 0x40
```

- `{CARD_DEV}` — from `ls /dev/snd/hwC*D0` (card 0 → `hwC0D0`).
- `{REAR_LINEOUT_NID}` — the Node found above (typically `0x14`).
- `0x40` = `OUT` — pin direction to playback.
- Needs `alsa-tools` installed (`hda-verb`); if missing:
  `sudo dnf install alsa-tools` (Fedora).

Verify:

```bash
cat /proc/asound/card0/codec#0 | grep -A8 "Node 0x14" | grep Pin-ctls
# expect: Pin-ctls: 0x40: OUT
```

### 2. Select the right port (Line Out = rear green)

```bash
pactl set-sink-port {SINK} analog-output-lineout
# {SINK} from: pactl list sinks short | grep analog-stereo
```

### 3. Make it permanent — systemd unit at boot

```bash
sudo tee /etc/systemd/system/rear-lineout-fix.service > /dev/null <<EOF
[Unit]
Description=Enable rear line-out pin on HDA codec (Pin-ctls OUT) - auto card lookup
After=sound.target

[Service]
Type=oneshot
# $$ = экранирование systemd (переменная для шелла, НЕ для systemd!)
# карту ищем по ИМЕНИ (PCH), чтобы пережить смену порядка карт (USB-устройства)
ExecStart=/bin/sh -c 'CARD=$$(basename "$$(readlink -f /proc/asound/PCH)"); CARD=$${CARD#card}; exec /usr/bin/hda-verb /dev/snd/hwC$${CARD}D0 0x14 SET_PIN_WIDGET_CONTROL 0x40'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now rear-lineout-fix.service
systemctl is-active rear-lineout-fix.service   # → active
```

ВАЖНО (проверено 23 авг 2026 — беда ВОЗВРАЩАЛАСЬ!):
- **Юнит с ЖЁСТКИМ номером карты (`hwC0D0`) ЛОМАЕТСЯ**, когда порядок
  карт меняется (подключили USB-микрофон → он стал card0, PCI-звук → card1).
  Симптом: юнит падает `hda-verb open: No such file or directory`,
  пин заднего разъёма снова `Pin-ctls: 0x00` — «беда вернулась».
  Проверка: `systemctl is-active rear-lineout-fix.service` → failed.
- **ЛЕЧЕНИЕ:** юнит ищет карту по ИМЕНИ из `/proc/asound/PCH`, а не по
  номеру (см. выше) — переживает любые перестановки.
- **ГРАБЛИ systemd:** в ExecStart `$CARD` перехватывается systemd
  (`Referenced but unset environment variable: CARD`), а `${CARD#card}`
  падает как «Invalid environment variable name» — писать `$$CARD` /
  `$${CARD#card}` (доллар доллара = переменная шелла).
- **Утилита `hda-verb` на пути:** `which` может не найти, но бинарник
  `/usr/bin/hda-verb` есть — юнит вызывает его напрямую.

## Verification

1. Unplug everything from the front panel jack (important — see Pitfalls).
2. Plug headphones/speakers into the **rear green** jack.
3. Select the **Line Out** port in GNOME Settings → Sound → Output
   (or `pactl set-sink-port {SINK} analog-output-lineout`).
4. Play audio → sound comes from the rear jack.

## Pitfalls (all hit live)

1. **"Headphones" ≠ your headphones.** The UI port names follow the physical
   jack, not your device. Front panel = "Headphones", rear green = "Line Out".
   If you plug headphones into the rear green, always pick **Line Out**.
2. **Auto-Mute silently kills the rear jack while the front is plugged.**
   With `Auto-Mute Mode = Enabled`, plugging anything into the front panel
   mutes the rear output automatically. Testing the rear jack with headphones
   still in the front panel always fails — empty the front jack first.
3. **The "Digital Output (S/PDIF)" profile is a black hole.** Switching the
   card profile to `output:iec958-stereo*` makes the analog sinks disappear:
   "headphones are gone" in the UI, sound goes nowhere. Keep the profile on
   `output:analog-stereo+input:analog-stereo`.
4. **WirePlumber remembers the last port and reverts.** Port choice is saved
   in `~/.local/state/wireplumber/default-routes` (key
   `alsa_card.{CARD}:profile:output:analog-stereo...=[...]`). If the port
   keeps jumping back to Line Out/Headphones, switch it again via
   `pactl set-sink-port` — the file rewrites on the next change. (Removing
   the entry also works; WirePlumber recreates it.)
5. **`hda-verb` needs root** — without `sudo` you get
   `open: Permission denied`; with `sudo -n` it prints
   `nid = 0x14, verb = 0x707, param = 0x40` and exits 0.
6. **The mute bit on the pin amp is normal.** `Amp-Out vals: [0x80 0x80]`
   on the rear pin while the front port is selected is expected (that pin is
   muted because it is not the active port). Selecting Line Out flips it back.

## References

- bbs.archlinux.org/viewtopic.php?id=275507 — ALC887: rear green dead,
  front works; EAPD/front fix with `hda-verb` + systemd unit (same method).
- forum.manjaro.org/t/biostar-b450m-realtek-alc887-audio-line-out-back-panel-no-audio/169633
  — same chipset family: rear panel no audio; Auto-Mute + Front volume.
- github.com/JensGrote/ca0132-audio-fix — "root cause: line-out pin disabled
  (Pin-ctls: 0x00), amplifier powered down (EAPD: 0x0)" — same pattern,
  fix via pin enable + boot hook.
- wiki.archlinux.org/title/Advanced_Linux_Sound_Architecture/Troubleshooting
  — HDA codec troubleshooting, pin/amp basics.
- pipewire.pages.freedesktop.org/wireplumber — ALSA monitor, ACP paths,
  `default-routes` state.

## БОЛЕЗНЬ №2: пин СБРАСЫВАЕТСЯ ЧЕРЕЗ МИНУТЫ (codec power-save) — РЕШЕНО (авг 2026)

СИМПТОМ: hda-verb включает пин (0x40), НО через некоторое время он СНОВА
0x00 — «помогает на полчаса и сбрасывает». Юнит при boot active, но не спасает.

ПРИЧИНА: ядро усыпляет кодек через `power_save` секунд без звука:
`cat /sys/module/snd_hda_intel/parameters/power_save` → 10 (10 СЕКУНД!).
Кодек засыпает → при пробуждении драйвер ПЕРЕИНИЦИАЛИЗИРУЕТ кодек →
пины сбрасываются в 0x00. То есть ЛЮБАЯ пауза звука > power_save сбрасывает
пин заднего разъёма! (кауфми: bbs.archlinux 280488, Reddit r/hackintosh
17z9dnj «hda-verb settings don't persist beyond a couple minutes»).

ЛЕЧЕНИЕ (двойное):
1. ЯДРО — не спать кодеку никогда:
   `/etc/modprobe.d/audio-power-save.conf`:
   ```
   options snd_hda_intel power_save=0
   ```
   (применяется при загрузке модуля / reboot)
2. WIREPLUMBER — отключить power-save/suspend на уровне кодека
   (сработало сразу, без reboot!) — канон gist Jastreb:
   `~/.config/wireplumber/main.lua.d/51-audio-no-suspend.lua`:
   ```lua
   rule = {
     matches = {
       {
         { "device.name", "matches", "alsa_card.*" },
         { "device.bus", "equals", "pci" },
         { "api.alsa.driver", "equals", "snd_hda_intel" },
         { "device.profile.name", "matches", "analog-output.*" },
       },
     },
     apply_properties = {
       ["api.alsa.disable-power-save"] = true,
       ["api.alsa.disable-suspend"] = true,
     },
   }
   table.insert(alsa_monitor.rules, rule)
   ```
   `systemctl --user restart wireplumber`

ПРОВЕРКА: включить пин → подождать ДОЛЖЕ power_save (напр. 35-65 сек +
после звука) → `Pin-ctls: 0x40` держится = победа.
Проверено 23 авг 2026: пин 0x40 через 35 с, 65 с, и после звука. ✅

## БОЛЕЗНЬ №3: WirePlumber 0.5 УБИЛ Lua-защиту (авг 2026) — РЕШЕНО ✅

СИМПТОМ (повтор после «починили»): юнит active при boot, пин включается
0x40, НО через пару минут снова 0x00. power_save опять 10.

ПРИЧИНЫ (улики + кауфми, 22 источника):
1. `/etc/modprobe.d/audio-power-save.conf` создан ПОСЛЕ boot → модуль
   snd_hda_intel загружен со СТАРЫМ power_save=10 (опция действует при
   загрузке модуля, не «сейчас»). Проверка тайминга: `uptime -s` vs
   `stat -c %y /etc/modprobe.d/*.conf`.
2. **WirePlumber 0.5 НЕ читает Lua!** Лог: «Lua configuration files are NOT
   supported in WirePlumber 0.5. You need to port them to the new format».
   Наш `main.lua.d/51-audio-no-suspend.lua` МЁРТВ (0.4-канон), предупреждение
   пишется, но защита не работает. Нюанс: `power_save=10` + suspend ноды
   (`api.alsa.disable-suspend` больше не применяется) → кодек спит → пин
   сбрасывается. (Кауфми: migration doc pipewire.pages.freedesktop.org,
   ospi.fi blog, ArchWiki WirePlumber, daily.dev)
3. Fedora-канон (Ask Fedora 141784): tuned (профили `balanced`/
   `powersave`) перезаписывает power_save=10 при старте — править
   `/etc/tuned/profiles/*/tuned.conf` (копия), `[audio] timeout=0`.
   У нас профиль `throughput-performance` (секции [audio] нет — не трогает),
   но на случай смены профиля — знать.

ЛЕЧЕНИЕ (двойное, применяется при reboot автоматически):
1. Юнит `rear-lineout-fix.service` теперь САМ ставит power_save=0 ПЕРЕД
   hda-verb (ExecStartPre, работает ПОСЛЕ sound.target — модуль уже
   загружен, sysfs доступен):
   `ExecStartPre=/bin/sh -c 'echo 0 > /sys/module/snd_hda_intel/parameters/power_save'`
2. НОВЫЙ формат WirePlumber 0.5 (SPA-JSON, НЕ Lua):
   `~/.config/wireplumber/wireplumber.conf.d/51-audio-no-suspend.conf`:
   ```
   monitor.alsa.rules = [
     {
       matches = [ { node.name = "~alsa_output.pci-0000_00_1f.3.*" } ]
       actions = { update-props = { session.suspend-timeout-seconds = 0 } }
     }
   ]
   ```
   `session.suspend-timeout-seconds = 0` = нода НЕ усыпает (man pipewire-props:
   «Value 0 means the node will not be suspended»). Старый
   `main.lua.d/51-audio-no-suspend.lua` — УДАЛИТЬ.
3. `systemctl --user restart wireplumber` (всегда ставить `session.
   suspend-timeout-seconds` в `update-props` — это свойство НОДЫ, матчим
   `node.name`, НЕ `device.name`).

ПРОВЕРКА (23 авг 2026 ✅): юнит active (ExecStartPre SUCCESS),
`power_save=0`, `Pin-ctls: 0x40` держится 70 с и 2+ мин тишины,
sink IDLE (не SUSPENDED!), pw-dump показывает
`"session.suspend-timeout-seconds": 0` на ноде, логи wireplumber ЧИСТЫЕ.

ГРАБЛИ: `pactl list sinks | grep "Active Port"` давал пусто — смотреть
полный `pactl list sinks` / `pactl list short sinks` (состояние IDLE =
нода жива). Проверка «не спит ли» = IDLE, SUSPENDED = уснула.

## БОЛЕЗНЬ №4: юнит «сработал», но WirePlumber сбрасывает пин ПОСЛЕ него при boot (авг 2026) — РЕШЕНО ✅

СИМПТОМ (24 авг 2026): юнит `rear-lineout-fix.service` active (exited),
но пин снова `Pin-ctls: 0x00`. «Опять не слышно» на следующий день.

ПРИЧИНА (по таймстампам, не гадание): при загрузке юнит срабатывает
РАНЬШЕ wireplumber: юнит ExecStart 15:24:33, wireplumber стартует 15:24:48.
WirePlumber при старте применяет профиль карты (ACP/пути) и ПЕРЕЗАПИСЫВАЕТ
pin-ctls заново → пин возвращается в 0x00. Юнит остаётся «active» и больше
ничего не делает (RemainAfterExit). Вчера держалось, потому что юнит
дёргали вручную ПОСЛЕ старта wireplumber. Машина не спала, power_save=0,
нода IDLE — а пин 0x00: это НЕ «уснул кодек», это гонка старта.

ЛЕЧЕНИЕ: systemd-таймер-сторож — дёргает hda-verb каждые 5 минут
(идемпотентно, безвредно):
```
# /etc/systemd/system/rear-lineout-watch.timer
[Unit]
Description=Watch rear line-out pin - re-apply hda-verb every 5 min

[Timer]
OnBootSec=3min
OnUnitActiveSec=5min
Unit=rear-lineout-fix.service

[Install]
WantedBy=timers.target
```
```
sudo systemctl daemon-reload
sudo systemctl enable --now rear-lineout-watch.timer
```
ГРАБЛИ (проверено):
1. **`RemainAfterExit=yes` в юните ЛОМАЕТ таймер**: юнит после первого
   запуска висит «active», таймер делает `start` на активный юнит =
   NO-OP, hda-verb НЕ выполняется повторно (проверено: `systemctl show`
   → ActiveState=active, Main PID вчерашний). Флаг удалить.
2. `systemctl start` на уже активный (exited) юнит = no-op — сначала
   `systemctl stop`, только потом start (или рестарт).
3. Проверка механики: `systemctl list-timers rear-lineout-watch.timer`
   → NEXT через ~5 мин, LAST = срабатывание; `systemctl show
   rear-lineout-fix.service -p ActiveState` → inactive между тиками.
4. Верификация пина ТОЛЬКО по блоку узла 0x14 (awk/поиск до «Device:»):
   `grep -A3 "Pin-ctls" | head` НЕ годится — показывает ПЕРВЫЙ пин в дампе,
   а это соседний выключенный N/A-пин (false positive!).

Проверено на этой машине (24 авг 2026): пин 0x14 → 0x40, порт
analog-output-lineout, sink RUNNING, paplay bell.oga играет ✅; таймер
активен (NEXT=13:21), юнит inactive между тиками, пин держится ✅.
