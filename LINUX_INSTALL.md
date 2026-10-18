# OpenWrt Studio для Linux x86_64

Linux-версия использует интерфейс и службы Flutter-приложения OpenWrt Studio Mobile. Это нативное графическое приложение для управления OpenWrt через LuCI RPC; Windows/.NET/Wine не требуются. Оно содержит простой и экспертный режимы мобильного приложения. WPF-интерфейс Windows в этот пакет не входит.

## Совместимость

Предпочтительный пакет — **AppImage** для разных дистрибутивов x86_64. Сборка выполняется на Ubuntu 22.04 (glibc 2.35); нужен современный дистрибутив с glibc 2.35 или новее и графический сеанс X11/Wayland с поддержкой GTK 3/OpenGL. Ориентиры: Ubuntu 22.04+, Debian 12+, современные Fedora, openSUSE и Arch. AppImage включает библиотеки GTK, но для сохранения паролей нужен работающий пользовательский Secret Service (GNOME Keyring или совместимый сервис). Приложение не сохраняет пароли в незашифрованный файл при отсутствии keyring.

Alpine/musl, ARM64, старые glibc и каждый возможный дистрибутив этой сборкой не проверяются. Доступность GUI не означает, что проверена работа с конкретной прошивкой и VPN-сервером.

## AppImage

Скачайте AppImage и SHA256SUMS.txt из одной сборки, сравните контрольную сумму, затем:

```sh
sha256sum OpenWrtStudio-*-x86_64.AppImage
chmod +x OpenWrtStudio-*-x86_64.AppImage
./OpenWrtStudio-*-x86_64.AppImage
```

При отсутствии FUSE AppImage можно распаковать без установки драйвера:

```sh
./OpenWrtStudio-*-x86_64.AppImage --appimage-extract
./squashfs-root/AppRun
```

Вариант с FUSE: Ubuntu 22.04/Debian — пакет `libfuse2`, Ubuntu 24.04 — `libfuse2t64`. Для иных дистрибутивов название FUSE 2 отличается; распаковка выше работает без него.

## Обычный архив

```sh
tar -xzf OpenWrtStudio-*-linux-x86_64.tar.gz
cd OpenWrtStudio-*-linux-x86_64
./openwrt-studio
```

Сохраняйте `lib/` и `data/` рядом с исполняемым файлом. Для архива нужны системные GTK 3, libsecret, jsoncpp, libstdc++, графические драйверы и пользовательский keyring. Примеры зависимостей:

```sh
# Debian 12 / Ubuntu 22.04
sudo apt install libgtk-3-0 libsecret-1-0 libjsoncpp25 gnome-keyring
# Fedora
sudo dnf install gtk3 libsecret jsoncpp gnome-keyring
# Arch
sudo pacman -S gtk3 libsecret jsoncpp gnome-keyring
# openSUSE
sudo zypper install gtk3 libsecret-1-0 libjsoncpp25 gnome-keyring
```

Названия пакетов зависят от версии дистрибутива (в Ubuntu 24.04 GTK имеет суффикс t64). AppImage уменьшает зависимость от этих различий.

Установка архива для текущего пользователя с ярлыком:

```sh
./install-linux.sh
~/.local/bin/openwrt-studio
```

Удаление установленного таким способом приложения:

```sh
rm -f ~/.local/bin/openwrt-studio ~/.local/share/applications/openwrt-studio.desktop
rm -f ~/.local/share/icons/hicolor/256x256/apps/openwrt-studio.png
rm -rf ~/.local/lib/openwrt-studio
```

Удаление файлов приложения не удаляет записи keyring. Удалите сохранённые роутеры в интерфейсе до удаления приложения, если нужно очистить их данные.

## Подключение

Укажите адрес OpenWrt, логин и пароль. Приложению нужны LuCI/rpcd и разрешения пользователя на соответствующие ubus/UCI/file-операции. Не открывайте rpcd или контроллер VPN в интернет ради приложения. Для удалённого доступа используйте собственный VPN.

Список серверов и групп формируется из живого Clash API, конфигурации Sing-box и кэшей ForkOP. При недоступном API текущий выбор не выдумывается; неизвестная задержка показывается как N/A. Переключение подтверждается повторным чтением состояния роутера. Авто-группа меняет выбор сервера самостоятельно; это отличается от ручного выбора узла в селекторе.

Android APK-обновления в Linux отключены. Для обновления заменяйте AppImage/папку новой сборкой.

## Сборка из исходников

Нужны Flutter 3.47.7, clang, cmake, ninja, pkg-config, GTK 3/libsecret/jsoncpp development packages. На Ubuntu/Debian:

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libjsoncpp-dev liblzma-dev
flutter pub get
flutter analyze --fatal-infos
flutter test
./scripts/build-linux.sh
./scripts/package-linux.sh
```

Первая команда сборки генерирует стандартный Flutter Linux runner; существующие Dart-экраны не заменяются. Для AppImage укажите `LINUXDEPLOY` и добавьте `linuxdeploy-plugin-gtk.sh` в PATH, как в `.github/workflows/linux-vpn.yml`.
