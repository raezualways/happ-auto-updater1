#!/bin/bash
set -ex

LOG_FILE="/tmp/happ-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "🚀 Старт настройки Happ..."

# --- 1. Полная установка зависимостей для GUI-приложений ---
echo "🛠️  Устанавливаем инструменты и библиотеки..."
sudo apt-get update
sudo apt-get install -y wget xvfb xdotool imagemagick \
    libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 \
    xdg-utils libatspi2.0-0 libsecret-1-0 libasound2 \
    x11-apps

# --- 2. Скачивание и установка Happ ---
echo "📦 Скачиваем и устанавливаем Happ..."
HAPP_URL=$(wget -qO- https://api.github.com/repos/Happ-proxy/happ-desktop/releases/latest | grep "browser_download_url.*Happ.linux.x64.deb" | cut -d '"' -f 4)
if [ -z "$HAPP_URL" ]; then
    HAPP_URL="https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.linux.x64.deb"
fi
echo "Ссылка: $HAPP_URL"
wget -O /tmp/happ.deb "$HAPP_URL"
sudo dpkg -i /tmp/happ.deb
sudo apt-get install -f -y

# --- 3. Запуск виртуального дисплея ---
echo "🖥️  Запускаем Xvfb..."
Xvfb :99 -screen 0 1024x768x24 > /tmp/xvfb.log 2>&1 &
XVFB_PID=$!
export DISPLAY=:99
sleep 3

# Проверка дисплея
if ! xdpyinfo >/dev/null 2>&1; then
    echo "❌ Дисплей не работает. Лог Xvfb:"
    cat /tmp/xvfb.log
    exit 1
fi
echo "✅ Дисплей :99 активен."

# --- 4. Загрузка конфигов (пока без автоматизации GUI) ---
echo "⬇️  Качаем конфиги..."
mkdir -p /tmp/vpn-configs
cd /tmp/vpn-configs
wget --timeout=10 --tries=3 https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS_mobile.txt || echo "⚠️ Файл не скачался"
wget --timeout=10 --tries=3 https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/WHITE_VLESS_RUS_mobile.txt || echo "⚠️ Файл не скачался"
cd ~

# --- 5. Пробный запуск Happ (без автоматизации) ---
echo "🤖 Запускаем Happ..."
/opt/Happ/happ &
HAPP_PID=$!

# Ждём появления окна (до 15 секунд)
for i in {1..15}; do
    if xdotool search --name "Happ" >/dev/null 2>&1; then
        echo "✅ Окно Happ появилось!"
        break
    fi
    sleep 1
done

# Делаем скриншот рабочего стола
import -window root /tmp/happ-running.png

# Даём Happ поработать 10 секунд и закрываем
sleep 10
kill $HAPP_PID || true
sleep 2

# Финальный скриншот
import -window root /tmp/happ-closed.png

# Завершаем Xvfb
kill $XVFB_PID || true

echo "✅ Скрипт успешно завершён (базовая проверка Happ)."
