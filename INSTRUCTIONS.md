# TG WS Proxy — Инструкция

## Что это

Локальный MTProto-прокси для Telegram Desktop. Трафик от Telegram идёт через WebSocket на сервера Telegram, что обходит DPI и блокировки.

Прокси слушает на **127.0.0.1:1443** и принимает подключения от Telegram Desktop по протоколу MTProto.

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

**Через ссылку (автоматически, но IP может быть неверным):**

```bash
make link
# tg://proxy?server=172.17.0.2&port=1443&secret=dd...
```

Отправь эту ссылку себе в Избранное и кликни. **Важно:** если IP в ссылке отличается от `127.0.0.1`, после клика проверь настройки и при необходимости замени Server на `127.0.0.1`.

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

## Остальные команды Makefile

```bash
make build       # собрать Docker-образ
make rebuild     # пересобрать без кэша
make run         # запустить контейнер
make stop        # остановить
make restart     # перезапустить
make logs        # смотреть логи
make link        # показать tg:// ссылку
make secret      # показать секрет
make shell       # войти в контейнер
make rm          # удалить контейнер
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
  -p 1443:1443 \
  -e TG_WS_PROXY_SECRET="$(cat .secret)" \
  -e TG_WS_PROXY_DC_IPS="2:149.154.167.220 4:149.154.167.220" \
  tg-ws-proxy:latest
```

Через Makefile:
```bash
make run SECRET="мой_секрет"
```

---

## Если не работает

| Симптом | Причина | Решение |
|---|---|---|
| В логах `bad handshake` | Неверный секрет в Telegram | Проверь Secret в настройках Telegram. Должен быть с префиксом `dd` |
| В логах пусто, Telegram не подключается | Контейнер не запущен | `docker ps` — проверь статус. `make run` |
| Telegram пишет «требуется замена секрета» | Секрет не совпадает | `make secret`, сравни с тем, что в Telegram |
| После перезагрузки не работает | Docker не запущен | `sudo systemctl enable --now docker` |
| Не грузит фото/видео | Нужно меньше DC | `make rm && docker run ... -e TG_WS_PROXY_DC_IPS="4:149.154.167.220"` |

---

## Документация

Подробнее в папке `docs/`:

- `docs/README.docker.md` — Docker
- `docs/BuildFromSource.md` — запуск без Docker
- `docs/CfProxy.md` — Cloudflare proxy domain
- `docs/CfWorker.md` — Cloudflare Worker relay
- `docs/FakeTlsNginx.md` — Fake TLS + nginx
