# TG WS Proxy — Инструкция

## Что это

Локальный MTProto-прокси для Telegram Desktop. Трафик от Telegram идёт через WebSocket на сервера Telegram, что обходит DPI и блокировки.

Прокси слушает на **0.0.0.0:1443** и принимает подключения от Telegram Desktop по протоколу MTProto.

> **Сеть host:** контейнер запускается с `--network host`, поэтому порт пробрасывать через `-p` не нужно — прокси доступен напрямую на всех интерфейсах хоста.

---

## Сборка и запуск

```bash
# Собрать образ
make build

# Запустить контейнер (первый раз создаёт .secret с ключом)
make run
```

После запуска контейнер будет автоматически перезапускаться при падении (`--restart=always`).

---

## Секрет

Секрет — это 32-символьный hex-ключ, которым Telegram шифрует трафик к прокси.

При первом `make run` создаётся файл `.secret` со случайным ключом:

```bash
cat .secret
# ce6b517f89cd748635f70e0e052e79b9
```

**Секрет фиксирован.** После перезагрузки ПК и перезапуска контейнера секрет остаётся тем же. Настроил Telegram один раз — и забыл.

```important
Не удаляй `.secret`! Иначе при следующем запуске создастся новый ключ,
и Telegram перестанет подключаться. Если удалил — пропиши новый секрет в Telegram вручную.
```

Посмотреть секрет:
```bash
make secret
```

---

## Настройка Telegram Desktop

**Вручную (рекомендуется):**

1. Telegram → **Settings** → **Advanced** → **Connection Type** → **Proxy**
2. Добавить прокси:
   - **Type:** `MTProto`
   - **Server:** `127.0.0.1`
   - **Port:** `1443`
   - **Secret:** `dd` + содержимое `.secret`

   Пример (секрет из `.secret` выше):
   ```
   ddce6b517f89cd748635f70e0e052e79b9
   ```

3. Убедись, что напротив прокси стоит зелёный кружок ✅

**Через ссылку (автоматически):**

```bash
make link
# tg://proxy?server=172.16.147.64&port=1443&secret=dd...
```

Отправь эту ссылку себе в Избранное и кликни. **Важно:** в ссылке указывается IP хоста. Если телефон не в той же сети — используй публичный IP или настрой удалённый доступ (Tailscale / Cloudflare Tunnel).

---

## Автовосстановление при ошибках

Прокси умеет восстанавливаться сам, без внешних сервисов. Модуль `proxy/autorecover.py` отслеживает upstream-ошибки (WebSocket connect, CF proxy, TCP fallback, fronting) в скользящем окне **60 секунд**:

| Уровень | Порог | Что происходит |
|---|---|---|
| **Мягкий сброс** | 60+ ошибок за 60с | Очистка чёрного списка, кулдаунов, пулов WS/CF; обновление списка CF-доменов. Процесс продолжает работать |
| **Жёсткий сброс** | 300+ ошибок за 60с | Процесс завершается; контейнер перезапускается через `--restart=always` |

События видны в логах по префиксу `autorecover:`:

```bash
docker logs tg-ws-proxy 2>&1 | grep autorecover
# WARNING  autorecover: 67 upstream errors in 60s window -> SOFT reset ...
# ERROR    autorecover: 310 upstream errors in 60s window -> HARD reset ...
```

Между сбросами есть пауза (не чаще ~30с после мягкого сброса), чтобы не зациклиться.

---

## Автозапуск при загрузке ПК

```bash
sudo make install
```

Это установит systemd-сервис `tg-ws-proxy`, который запускает контейнер после старта Docker.

Управление сервисом:
```bash
sudo systemctl start tg-ws-proxy    # запустить сейчас
sudo systemctl stop tg-ws-proxy     # остановить
sudo systemctl status tg-ws-proxy   # статус
sudo journalctl -u tg-ws-proxy -f   # логи
```

---

## Cloudflare Worker (fallback)

Прокси может использовать Cloudflare Worker как fallback, когда прямое WebSocket-соединение и CF Proxy недоступны. Как настроить Worker — в [`docs/CfWorker.md`](./docs/CfWorker.md).

Указать домен Worker'а:

```bash
echo 'random-symbols-1234.username.workers.dev' > .cfworker
make run
```

Посмотреть текущий домен:
```bash
make cfworker
```

> `.cfworker` (как и `.secret`) не коммитится в git.

---

## Остальные команды Makefile

```bash
make build       # собрать Docker-образ
make rebuild     # пересобрать без кэша
make run         # запустить контейнер
make stop        # остановить
make restart     # перезапустить
make logs        # смотреть логи
make link        # показать tg:// ссылку
make link-file   # сохранить ссылку в файл (~/.config/tg-ws-proxy/link)
make secret      # показать секрет
make shell       # войти в контейнер
make rm          # удалить контейнер
make cfworker    # показать CF Worker домен
make install     # установить systemd-сервис
make uninstall   # удалить systemd-сервис
```

---

## Настройки через переменные окружения

При запуске через `docker run` можно задать:

```bash
docker run -d \
  --name tg-ws-proxy \
  --restart=always \
  --network host \
  -e TG_WS_PROXY_SECRET="$(cat .secret)" \
  -e TG_WS_PROXY_DC_IPS="2:149.154.167.220 4:149.154.167.220" \
  tg-ws-proxy:latest
```

> На host-сети порт задаётся переменной `TG_WS_PROXY_PORT` (по умолчанию 1443). Публиковать порт через `-p` не нужно.

---

## Если не работает

| Симптом | Причина | Решение |
|---|---|---|
| В логах `bad handshake` | Неверный секрет в Telegram | Проверь Secret в настройках Telegram. Должен быть с префиксом `dd` |
| В логах пусто, Telegram не подключается | Контейнер не запущен | `docker ps` — проверь статус. `make run` |
| Telegram пишет «требуется замена секрета» | Секрет не совпадает | `make secret`, сравни с тем, что в Telegram |
| После перезагрузки не работает | Docker не запущен | `sudo systemctl enable --now docker` |
| Не грузит фото/видео | Нужно меньше DC | `docker rm -f tg-ws-proxy && docker run ... -e TG_WS_PROXY_DC_IPS="4:149.154.167.220"` |
| Массовые `CF proxy failed: TimeoutError()` в логах | Провайдер блокирует Telegram/CF | Прокси сам сделает SOFT/HARD reset. Проверь `grep autorecover` в логах |
| В логах `Temporary failure in name resolution` | DNS не работает внутри контейнера | На host-сети контейнер использует DNS хоста. Проверь DNS на хосте |
| В логах `NameError: coerce_domain_list` | Устаревший образ | `make rebuild` — пересобрать с актуальным кодом |

---

## Документация

Подробнее в папке `docs/`:

- `docs/README.docker.md` — Docker
- `docs/BuildFromSource.md` — запуск без Docker
- `docs/CfProxy.md` — Cloudflare proxy domain
- `docs/CfWorker.md` — Cloudflare Worker relay
- `docs/FakeTlsNginx.md` — Fake TLS + nginx
