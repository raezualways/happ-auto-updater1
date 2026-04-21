#!/bin/bash
set -ex  # Включаем режим отладки: печатаем каждую команду и вылетаем при ошибке

LOG_FILE="/tmp/happ-setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1  # Пишем весь вывод и в консоль, и в файл лога

echo "🚀 Старт настройки Happ..."

# --- 1. Подготовка окружения ---
echo "🛠️  Устанавливаем инструменты..."
sudo apt-get update
sudo apt-get install -y wget xdotool imagemagick x11-apps xvfb

# --- 2. Установка Happ ---
echo "📦 Скачиваем и устанавливаем Happ..."
# Проверяем актуальную ссылку (на 2026-04-21 актуальна версия 3.8.0, уточним через API)
HAPP_URL=$(wget -qO- https://api.github.com/repos/Happ-proxy/happ-desktop/releases/latest | grep "browser_download_url.*Happ.linux.x64.deb" | cut -d '"' -f 4)
if [ -z "$HAPP_URL" ]; then
    echo "❌ Не удалось получить ссылку на скачивание Happ. Использую запасной вариант."
    HAPP_URL="https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.linux.x64.deb"
fi
echo "Ссылка для скачивания: $HAPP_URL"
wget -O /tmp/happ.deb "$HAPP_URL"
sudo dpkg -i /tmp/happ.deb
sudo apt-get install -f -y

# --- 3. Запуск виртуального рабочего стола ---
echo "🖥️  Запускаем виртуальный экран..."
Xvfb :99 -screen 0 1024x768x24 > /tmp/xvfb.log 2>&1 &
XVFB_PID=$!
export DISPLAY=:99
sleep 2  # Даём время на запуск Xvfb

# Проверяем, что DISPLAY работает
if ! xdpyinfo >/dev/null 2>&1; then
    echo "❌ Виртуальный дисплей :99 не отвечает. Содержимое xvfb.log:"
    cat /tmp/xvfb.log
    exit 1
fi
echo "✅ Виртуальный дисплей :99 работает."

# --- 4. Загрузка свежих конфигураций ---
echo "⬇️  Качаем свежие конфиги из репозитория igareck..."
mkdir -p /tmp/vpn-configs
cd /tmp/vpn-configs
# Скачиваем файлы с проверкой существования
wget --timeout=10 --tries=3 https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS_mobile.txt || echo "⚠️ Файл BLACK_VLESS_RUS_mobile.txt не скачался"
wget --timeout=10 --tries=3 https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/WHITE_VLESS_RUS_mobile.txt || echo "⚠️ Файл WHITE_VLESS_RUS_mobile.txt не скачался"
cd ~

# --- 5. Запуск Happ и автоматизация (упрощённая версия) ---
echo "🤖 Запускаем Happ..."
/opt/Happ/happ &

# Ждём появления окна
echo "⏳ Ожидаем появления окна Happ..."
for i in {1..20}; do
    if xdotool search --name "Happ" >/dev/null 2>&1; then
        echo "✅ Окно Happ обнаружено!"
        break
    fi
    sleep 2
done

# Делаем первый скриншот (даже если окна нет)
import -window root /tmp/happ-initial.png || echo "⚠️ Не удалось сделать скриншот"

# Если окно найдено, пробуем кликнуть
if WINDOW_ID=$(xdotool search --name "Happ" | head -n 1); then
    echo "Активируем окно и кликаем..."
    xdotool windowactivate $WINDOW_ID
    sleep 1
    # Пример клика в область (координаты можно подобрать позже)
    xdotool mousemove 980 50 click 1
    sleep 1
    xdotool mousemove 500 200 click 1
    sleep 1
    xdotool type "https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS_mobile.txt"
    xdotool key Return
    sleep 20
else
    echo "❌ Окно Happ не найдено! Happ, возможно, не запустился."
fi

# Делаем финальный скриншот
import -window root /tmp/happ-final.png || echo "⚠️ Не удалось сделать финальный скриншот"

# Завершаем процессы
echo "🔚 Завершаем Happ и Xvfb..."
pkill -f "/opt/Happ/happ" || true
kill $XVFB_PID || true

# Сохраняем лог в артефакты
cp "$LOG_FILE" /tmp/
echo "✅ Скрипт завершён."

# Устанавливаем обработчик выхода, чтобы артефакты подхватывались даже при ошибке
trap - EXIT
