#!/bin/bash
set -e  # Останавливаем скрипт при любой ошибке

echo "🚀 Старт настройки Happ..."

# --- 1. Подготовка окружения ---
echo "🛠️  Устанавливаем инструменты..."
# Нам понадобятся: wget (для скачивания), xdotool (робот для GUI), imagemagick (чтобы делать скриншоты), x11-apps (для тестов)
sudo apt-get update
sudo apt-get install -y wget xdotool imagemagick x11-apps

# --- 2. Установка Happ ---
echo "📦 Скачиваем и устанавливаем Happ..."
wget -O /tmp/happ.deb "https://github.com/Happ-proxy/happ-desktop/releases/latest/download/Happ.linux.x64.deb"
sudo dpkg -i /tmp/happ.deb
# На всякий случай доустановим недостающие зависимости
sudo apt-get install -f -y

# --- 3. Запуск виртуального рабочего стола (Xvfb) ---
echo "🖥️  Запускаем виртуальный экран..."
# Запускаем фоновый процесс, который будет притворяться монитором
Xvfb :99 -screen 0 1024x768x24 > /dev/null 2>&1 &
# Сохраняем ID процесса, чтобы потом его корректно завершить
XVFB_PID=$!
# Говорим системе, что наш "монитор" находится по адресу :99
export DISPLAY=:99

# --- 4. Загрузка свежих конфигураций ---
echo "⬇️  Качаем свежие конфиги из репозитория igareck/vpn-configs-for-russia..."
# Создадим временную папку
mkdir -p /tmp/vpn-configs
cd /tmp/vpn-configs
# Скачиваем конфиги. Я взял для примера несколько ссылок.
# Ты можешь добавить сюда любые другие из README того репозитория.
wget https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS_mobile.txt
wget https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/WHITE_VLESS_RUS_mobile.txt
# ... добавь другие файлы по необходимости
cd ~

# --- 5. Автоматизация Happ с помощью xdotool ---
echo "🤖 Запускаем Happ и начинаем автоматическую настройку..."

# Функция для безопасного завершения, если что-то пойдёт не так
cleanup() {
    echo "🧹 Завершаем процессы..."
    # Убиваем Happ, если он ещё жив
    pkill -f "/opt/Happ/happ" || true
    # Останавливаем виртуальный экран
    kill $XVFB_PID || true
}
# Устанавливаем ловушку: если скрипт завершится (штатно или с ошибкой), вызови функцию cleanup
trap cleanup EXIT ERR

# Запускаем Happ в фоне
/opt/Happ/happ &

# Ждём несколько секунд, чтобы окно точно появилось
sleep 5

# Делаем скриншот для отладки (можно будет посмотреть в логах Action)
import -window root /tmp/happ-initial.png
echo "📸 Скриншот после запуска сохранён: /tmp/happ-initial.png"

# --- Основной блок автоматизации. Это как писать макрос. ---
# ВНИМАНИЕ: Координаты кликов и время ожидания могут меняться
# в зависимости от версии Happ и разрешения экрана. Возможно,
# их придётся подбирать экспериментально.

# Жмём кнопку "+" в правом верхнем углу (координаты примерные!)
xdotool mousemove 980 50 click 1
sleep 1
# Жмём "Import from URL"
xdotool mousemove 500 200 click 1
sleep 1
# Вставляем URL подписки (можно использовать wl-paste или xclip, но мы просто "напечатаем")
xdotool type "https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS_mobile.txt"
sleep 1
# Жмём "OK" или "Import"
xdotool key Return
sleep 2

# Ждём, пока конфигурации загрузятся и обновятся. Это может занять время.
echo "⏳ Ждём 20 секунд, пока Happ обновит конфигурации..."
sleep 20

# Закрываем Happ
echo "🔚 Закрываем Happ..."
pkill -f "/opt/Happ/happ"

# Делаем финальный скриншот
import -window root /tmp/happ-final.png
echo "📸 Финальный скриншот сохранён: /tmp/happ-final.png"

echo "✅ Работа скрипта завершена!"
