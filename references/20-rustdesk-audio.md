# 20 · RustDesk: партнёр не слышит звук (хост хватает не тот монитор)

<!-- meta
категория: E-сеть-и-удалённый-доступ
риск: L2 (правка конфига RustDesk; обратимо)
preflight-гейт: установлен RustDesk (rustdesk.service) + PipeWire/PulseAudio и БОЛЬШЕ ОДНОГО выхода (HDMI + аналог — типовой случай)
откат: в файле: убрать строку audio-input (или вернуть .bak), `sudo systemctl restart rustdesk`
-->

Проверено живьём: Fedora 44, GNOME/Wayland, PipeWire 1.6.9, NVIDIA (HDMI-звук)
+ Realtek ALC887 (аналог, колонки). Симптом ровно как у владельца: **партнёр
видит экран, но звука не слышит**, хотя локально колонки играют.

## Почему это вообще происходит (корень)

На Linux хост-сторону RustDesk пишет так: отдельный процесс-помощник `_pa`
берёт **монитор звукового выхода** (loopback) и гонит сырой звук по IPC в
audio-сервис. Когда в конфиге НЕ задан вход явно — вызывается
`get_pa_monitor()` (crate RustDesk, `src/platform/linux.rs`):

```rust
pub fn get_pa_monitor() -> String {
    get_pa_sources()
        .drain(..)
        .map(|x| x.0)
        .filter(|x| x.contains("monitor"))
        .next()                    // ← ПЕРВЫЙ монитор в списке, НЕ монитор дефолтного выхода!
        .unwrap_or("".to_owned())
}
```

Оно берёт **первый монитор из списка источников**, а не тот, куда реально
играет звук. Если в системе есть HDMI-звук (NVIDIA/AMD) и он оказался в
списке раньше аналогового — RustDesk слушает **HDMI**, где тишина. Партнёр
получает нули.

В логах это видно прямо:
```
[cm] INFO [src/ipc.rs:1379] pa monitor: "alsa_output.pci-0000_01_00.1.hdmi-stereo.monitor"
                                ^^^ HDMI, а музыка играет в аналог (колонки)
[src/server/audio_service.rs:477] Audio Zero Gate Attack   ← ~4 сек цифровой тишины
```

`Audio Zero Gate Attack` — НЕ ошибка сам по себе: это шумовые ворота
(`MAX_AUDIO_ZERO_COUNT=800`, ≈4–5 сек нулей) глушат тишину, чтоб не гнать
кадры зря. Но если он сыплется постоянно — значит на входе тишина, т.е. хост
слушает пустой выход.

## Диагностика (read-only, до правок)

```bash
# 1. Есть ли вообще несколько выходов (источников-monitor)?
pactl list short sources                      # ищи ...hdmi-stereo.monitor и ...analog-stereo.monitor

# 2. Куда RustDesk РЕАЛЬНО залип (во время живой сессии):
pactl list source-outputs | grep -E 'Source:|application.name'
#   видишь Source: <номер HDMI-монитора> → вот он, баг
#   видишь Source: <номер аналогового монитора> → всё ок

# 3. Какой выход дефолтный (может не совпадать с тем, что слушает RustDesk):
pactl get-default-sink

# 4. Точные ИМЯ и ОПИСАНИЕ источников (описание нужен для конфига):
pactl list sources | awk '/Name:/{n=$2} /Description:/{sub(/^\s*Description: /,""); print n" ||| "$0}'
```

## Фикс (заставить хост слушать нужный выход)

RustDesk хранит опции НЕ там, где можно подумать. Живьём выяснено:

- **Опции (в т.ч. `audio-input`) лежат в `RustDesk2.toml`**, а НЕ в `RustDesk.toml`.
  (`struct Config` в hbb_common вообще не имеет поля `options`; его имеет
  `struct Config2` = `RustDesk2.toml`; `Config::get_option()` читает `CONFIG2`.)
- Корневая служба RustDesk **синкает свой конфиг** в юзерский, поэтому правим
  оба файла — и юзера, и root (иначе через секунду после старта твоя строка
  исчезнет — проверено: контрольная левая опция вычищалась).

Значение `audio-input` в RustDesk матчится **по ОПИСАНИЮ источника**
(`get_pa_source_name` фильтрует `x.1 == desc`, где `x.1` — description), не по
имени. Берём описание нужного (аналогового) монитора из шага «Диагностика» 4.

```bash
# 0. Останавливаем службу (править конфиг ТОЛЬКО при остановленной!)
sudo systemctl stop rustdesk

# 1. Бэкапы
cp  ~/.config/rustdesk/RustDesk2.toml{,.bak.audiofix}
sudo cp /root/.config/rustdesk/RustDesk2.toml{,.bak.audiofix} 2>/dev/null

# 2. Вписать в [options] ОБОИХ файлов (значение — своё, из pactl list sources!)
LINE="audio-input = 'Monitor of Встроенное аудио Аналоговый стерео'"
for p in "$HOME/.config/rustdesk/RustDesk2.toml" /root/.config/rustdesk/RustDesk2.toml; do
  sudo python3 - "$p" "$LINE" <<'PY'
import sys
p, line = sys.argv[1], sys.argv[2]
s = open(p).read()
if 'audio-input' not in s:
    s = s.replace("[options]\n", "[options]\n" + line + "\n", 1)
    open(p, 'w').write(s)
print("---", p); print(open(p).read())
PY
done

# 3. Старт и проверка, что строка выжила в ОБОИХ файлах
sudo systemctl start rustdesk
grep audio-input ~/.config/rustdesk/RustDesk2.toml
sudo grep audio-input /root/.config/rustdesk/RustDesk2.toml
```

ГРАБЛИ (все пойманы живьём):
1. **`RustDesk.toml` — не тот файл.** Там `[options]` есть, но serde его игнорит
   (у `struct Config` нет поля `options`). Писать туда — впустую.
2. **Опции перезаписываются при старте** из синка корневой службы. Правь
   **оба** файла (юзер + `/root`) при остановленной службе, иначе строка
   исчезнет в первую секунду после `start` (симптом: `grep` пусто сразу после
   рестарта).
3. **Матч по ОПИСАНИЮ**, не по имени. `audio-input = 'alsa_output...monitor'`
   (имя) НЕ сработает — вернётся пусто и опять уедет в `get_pa_monitor()`.
4. **Описания локализованы** (пример — русский: `Monitor of Встроенное аудио
   Аналоговый стерео`). Берётся ровно та строка, что отдаёт
   `pactl list sources` на ЭТОЙ машине; чужую не тащить.
5. **Не путать с «мёртвым» выходом.** Тут проблема выбора источника, а не
   отключённого пина кодека (это `references/11-rear-audio-jack.md`, БОЛЕЗНИ
   №1/№5). Auto-Mute и USB-устройства тоже могут вмешиваться — смотри 11.

## Верификация (живая, по фактам)

1. Пусть партнёр/телефон подключится и на хосте заиграет звук.
2. Смотрим лог — должна появиться НАША строка:
   ```bash
   grep -h 'pa monitor' ~/.local/share/logs/RustDesk/cm/rustdesk_rCURRENT.log | tail -1
   # ОЖИДАЕМ: pa monitor: "alsa_output.pci-0000_00_1f.3.analog-stereo.monitor"
   ```
3. И захват должен идти с аналогового монитора:
   ```bash
   pactl list source-outputs | grep -E 'Source:|application.name'
   # ОЖИДАЕМ: Source: <номер analog-stereo.monitor> + application.name = "RustDesk"
   ```
4. Финальная верифа — **ушами партнёра**: играет = победа.

Живой монитор на время теста:
```bash
export LC_ALL=C
watch -n1 'echo "DEFAULT: $(pactl get-default-sink)"; pactl list source-outputs | grep -E "Source:|application.name"; echo ---; tail -2 ~/.local/share/logs/RustDesk/cm/rustdesk_rCURRENT.log'
```

## Откат

```bash
sudo systemctl stop rustdesk
cp ~/.config/rustdesk/RustDesk2.toml.bak.audiofix ~/.config/rustdesk/RustDesk2.toml
sudo cp /root/.config/rustdesk/RustDesk2.toml.bak.audiofix /root/.config/rustdesk/RustDesk2.toml
sudo systemctl start rustdesk
# либо просто убрать строку audio-input из [options] в обоих файлах
```

## Если не помогло (следующий уровень)

- **Проверить, что `pulsectl` видит то же описание**, что `pactl`. Если матч
  не срабатывает — вариант «из-под низу»: убрать лишний HDMI-монитор из
  системы (правило WirePlumber `node.name = "~alsa_output.pci-0000_01_00.1.*"`
  с `node.disabled`), тогда `get_pa_monitor()` физически не сможет выбрать
  пустоту. Плата: HDMI-звук пропадёт как источник (если он не нужен — годится).
- **`_pa` сдох во время сессии**: в логе `Failed to send audio data: Обрыв
  канала (os error 32)`, а в коде `if data.len() == 0 { send_f32(&zero_audio_frame...); continue; }`
  — RustDesk вместо падения гонит НУЛИ. Признак: capture исчез из
  `pactl list source-outputs`, звук пропал на середине. Лечится
  переподключением/рестартом `rustdesk`.
- **У партнёра «Mute»**: опция `disable-audio` в его клиенте (Настройки →
  Экран → Mute) или системная громкость/не тот выход. Проверять первым делом —
  бесплатно.
- **Дефолтный выход уехал на HDMI** (после воткнутого телека): тогда и
  `pactl get-default-sink` показывает HDMI. Вернуть/переключить выход.

## References

- Исходники RustDesk: `src/platform/linux.rs` (`get_pa_monitor`, `get_pa_source_name`,
  `get_pa_sources`), `src/ipc.rs` (`start_pa`, лог `pa monitor:`),
  `src/audio_service.rs` (`pa_impl`, шумовые ворота `MAX_AUDIO_ZERO_COUNT=800`),
  `libs/hbb_common/src/config.rs` (`Config2.options`, `is_option_can_save`).
- `references/07-rustdesk-games.md` — чёрный экран у партнёра и FPS (соседняя болячка).
- `references/11-rear-audio-jack.md` — мёртвый задний разъём и Auto-Mute (не путать).
- rustdesk.com/docs — Advanced settings: `enable-audio`, `disable-audio`.

Проверено на этой машине (26 сен 2026): до фикса `pa monitor: "...hdmi-stereo.monitor"`,
захват `Source 3780` (HDMI) = тишина; после фикса `pa monitor:
"...analog-stereo.monitor"`, захват `Source 3848` (аналог) — **звук у партнёра пошёл** ✅.
