# 📱 OpenWrt Studio Mobile (Android)

<div align="center">
  <h3>Расширенный мобильный клиент для OpenWrt на базе LuCI Mobile</h3>
  <p>Все возможности стокового LuCI Mobile + мощный арсенал OpenWrt Studio прямо на вашем смартфоне.</p>
</div>

---

## Обновление 2.5.24

Исправлены определение активного VPN, чтение реальных групп ForkOP и подтверждение переключения состоянием роутера. APK проверен обновлением поверх предыдущей версии на Android-телефоне.

Подробности: [изменения 2.5.24](RELEASE_NOTES.md), [проверка на оборудовании](VPN_VALIDATION.md).

## 📸 Скриншоты интерфейса

| Простой режим | Экспертная панель | Управление клиентами |
| :---: | :---: | :---: |
| <img src="screenshots/01_simple_dashboard.jpg" width="240"/> | <img src="screenshots/02_expert_dashboard.jpg" width="240"/> | <img src="screenshots/03_clients_management.jpg" width="240"/> |

| Сетевые интерфейсы | Sentinel Watchdog | VPN и Протоколы |
| :---: | :---: | :---: |
| <img src="screenshots/04_network_interfaces.jpg" width="240"/> | <img src="screenshots/05_sentinel_watchdog.jpg" width="240"/> | <img src="screenshots/06_vpn_protocols.jpg" width="240"/> |

| ForkOP Прокси | Быстрые команды и терминал | Цветовые схемы | Сообщество и инструменты |
| :---: | :---: | :---: | :---: |
| <img src="screenshots/07_forkop_proxies.jpg" width="200"/> | <img src="screenshots/08_terminal_commands.jpg" width="200"/> | <img src="screenshots/09_custom_themes.jpg" width="200"/> | <img src="screenshots/10_community_and_tools.jpg" width="200"/> |

---

## 🌟 Возможности приложения

### ⚡ Расширенный функционал OpenWrt Studio:
1. **🌐 ForkOP (Узлы, Серверы, Подписки)**:
   - Поддержка ядер Mihomo (Clash Meta), Sing-box, PassWall 2, Xray.
   - Список всех прокси-серверов и селекторов (VLESS, VMess, Shadowsocks, Trojan, Hysteria 2, WireGuard, AmneziaWG).
   - Замер пинга (Latency / Delay test) в один клик по всем серверам.
   - Быстрое переключение активного сервера в группах `PROXY` / `GLOBAL`.
   - Выбор режима маршрутизации: `Rule` (по правилам), `Global` (весь трафик), `Direct` (напрямую).
   - Импорт и обновление подписок по ссылке.

2. **🛡️ VPN и Протоколы (Менеджер служб OpenWrt 24/25)**:
   - 7-уровневое сканирование установленных протоколов: AmneziaWG, WireGuard, Sing-box, Mihomo, PassWall 2, OpenVPN, Tailscale, ZeroTier, Xray.
   - Поддержка пакетных менеджеров `apk` (OpenWrt 24/25) и `opkg` (OpenWrt 23 и старше).
   - Просмотр статуса (Работает / Остановлен / Не установлен).
   - Быстрые кнопки управления: `Запустить`, `Остановить`, `Перезапуск`, `Установить`.

3. **👁️ Sentinel Watchdog (Мобильный сторожевой таймер)**:
   - Проверка обхода блокировок и связности ключевых сервисов (Google, YouTube, Telegram, GitHub, Cloudflare, RuTracker).
   - Замер задержки в мс до каждого узла.
   - Функция **Автохил**: перезапуск DNS (`dnsmasq`), сброс кэша и перезапуск туннеля в одно касание.

4. **💻 Быстрые команды и Мини-терминал**:
   - Быстрые действия: Очистка памяти RAM (`drop_caches`), перезагрузка правил Firewall 4 (`fw4 reload`), сброс DNS.
   - Просмотр системных журналов `logread` и логов ядра `dmesg`.
   - Ввод и выполнение любых команд shell прямо со смартфона.

5. **🎨 Цветовые схемы OpenWrt Studio (Fluent & Material 3)**:
   - Кибер Циан (`#00D2FF`)
   - Изумрудный Оазис (`#10B981`)
   - Киберпанк Неон (`#8B5CF6`)
   - Королевский Сапфир (`#3B82F6`)
   - Солнечный Янтарь (`#F59E0B`)
   - Рубиновый Закат (`#EF4444`)
   - Мгновенное переключение Светлой / Тёмной темы.

---

### 📦 Стоковые функции LuCI Mobile (полностью сохранены):
- Дашборд с нагрузкой CPU, RAM, аптаймом и графиками скорости в реальном времени.
- Список подключенных клиентов (DHCP-аренды, Wi-Fi ассоциации, определение производителей устройств по MAC).
- Управление проводными и беспроводными интерфейсами.
- Сканирование сетей Wi-Fi вокруг роутера.
- Поддержка профилей нескольких роутеров с безопасным хранением учетных данных (`flutter_secure_storage`).

---

## 💬 Сообщество и поддержка
- 📢 **Telegram-канал программы**: [@OpenWrtStudio](https://t.me/OpenWrtStudio)
- 📢 **Telegram-канал автора**: [@RichkovChannel](https://t.me/RichkovChannel)
- 🐛 **Сообщить о баге (Bug Report)**: [GitHub Issues](https://github.com/RichkovGit/OpenWrtStudio/issues)
- 🌐 **Десктопная версия**: [OpenWrtStudio](https://github.com/RichkovGit/OpenWrtStudio)

---

## 🚀 Скачать APK для Android

Установочные файлы `.apk` доступны на странице релизов. Подготовка новых Android-релизов запускается вручную через GitHub Actions после создания проверенного тега:
- **[Страница релизов GitHub Releases](../../releases)**

| Вариант | Описание |
|---|---|
| 📱 **app-arm64-v8a-release.apk** | Оптимизированный для современных 64-битных смартфонов (быстрее и компактнее) |
| 🛠️ **app-armeabi-v7a-release.apk** | Для 32-битных устаревших Android-устройств |
| 💻 **app-x86_64-release.apk** | Для эмуляторов Android на ПК |
| 📦 **app-release.aab** | Android App Bundle для публикации |

`SHA256SUMS.txt` содержит контрольные суммы файлов выпуска. Встроенное обновление предлагает стабильные релизы; черновики и prerelease в него не попадают.

## Сборка и подготовка Android-релиза

Проверенная версия SDK — **Flutter 3.47.7 stable**. Android-проект использует Java 21 для сборки, Android SDK 37 и NDK 28.2.13676358.

Из корня репозитория:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
flutter build apk --split-per-abi --release
flutter build appbundle --release
```

Для обновления поверх установленного приложения требуется прежний ключ подписи, настроенный через локальный `android/key.properties`. Перед распространением сравните сертификат новой APK с сертификатом предыдущей версии с помощью `apksigner verify --print-certs` из Android SDK Build Tools. Ключи и пароли не добавляются в репозиторий.

Рабочий процесс [Prepare Android release](.github/workflows/release.yml) запускается из Actions → Run workflow с существующим тегом, например `v2.5.23`. Тег должен совпадать с версией в `pubspec.yaml`. В репозитории должны быть настроены прежние секреты `ANDROID_KEYSTORE_BASE64` и `ANDROID_KEY_PROPERTIES_BASE64`; `storeFile` должен указывать на восстанавливаемый файл `android/app/luci_mobile_keystore.jks` относительно `android/` или `android/app/`.

Процесс выполняет форматирование, статический анализ и тесты, собирает все три APK и AAB, затем сохраняет контрольные суммы и создаёт **draft + prerelease**, не назначая его latest. Существующий релиз не изменяется. Публикация тега сама по себе не запускает выпуск и не создаёт пустой стабильный релиз.

После установки на реальный телефон проверьте обновление поверх предыдущей версии, сохранность профилей, подключение и смену роутера, USB-настройки, управление службами и выход из аккаунта. Затем кандидат можно опубликовать как стабильный релиз вручную. iOS-сборка и подпись IPA в этот процесс не входят.

---

## 📄 Лицензия
Проект распространяется под свободной лицензией **GNU General Public License v3.0 (GPL-3.0)**.
Оригинальный проект: [cogwheel0/luci-mobile](https://github.com/cogwheel0/luci-mobile).
