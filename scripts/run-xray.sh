#!/bin/bash
set -e

echo "🔄 Скачиваем свежие конфиги..."
mkdir -p /tmp/xray-configs
cd /tmp/xray-configs

# Скачиваем конфиги (можно добавить несколько)
wget -q -O config1.txt "https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS_mobile.txt"
wget -q -O config2.txt "https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/WHITE_VLESS_RUS_mobile.txt"

# Объединяем все конфиги в один файл
cat *.txt > all-configs.txt

# Выбираем случайный конфиг (или первый) и конвертируем в JSON для Xray
SELECTED=$(shuf -n 1 all-configs.txt)
echo "Выбран конфиг: ${SELECTED:0:50}..."

# Устанавливаем Xray-core, если ещё не установлен
if ! command -v xray &> /dev/null; then
    echo "📦 Устанавливаем Xray-core..."
    bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install --version 1.8.23
fi

# Создаём временный конфиг Xray из выбранной ссылки
# Простейший парсер для vless:// ссылок (для демонстрации)
# В реальности лучше использовать готовый инструмент, но для примера сойдёт
if [[ $SELECTED == vless://* ]]; then
    # Извлекаем UUID, host, port, path и т.д. (упрощённо)
    UUID=$(echo "$SELECTED" | sed -n 's|vless://\([^@]*\)@.*|\1|p')
    HOST=$(echo "$SELECTED" | sed -n 's|.*@\([^:]*\):.*|\1|p')
    PORT=$(echo "$SELECTED" | sed -n 's|.*:\([0-9]*\)/.*|\1|p')
    # Генерируем базовый конфиг SOCKS5 прокси на localhost:1080
    cat > /tmp/config.json <<EOF
{
  "inbounds": [{
    "port": 1080,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": {
      "udp": true
    }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "$HOST",
        "port": $PORT,
        "users": [{
          "id": "$UUID",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "ws",
      "security": "tls",
      "wsSettings": {
        "path": "/"
      }
    }
  }]
}
EOF
else
    echo "❌ Неподдерживаемый формат конфига, пропускаем."
    exit 1
fi

echo "🚀 Запускаем Xray с обновлённым конфигом..."
# Останавливаем предыдущий экземпляр, если есть
pkill xray || true
# Запускаем Xray в фоне
xray run -c /tmp/config.json &
XRAY_PID=$!

# Даём Xray время на подключение
sleep 5

# Проверяем, что прокси работает (запрос к ifconfig.me через SOCKS5)
echo "🌐 Проверка IP через прокси..."
CURRENT_IP=$(curl -s --socks5 localhost:1080 ifconfig.me)
echo "Текущий IP: $CURRENT_IP"

# Убиваем Xray (для экономии времени GitHub Actions, т.к. нам важно только обновление)
kill $XRAY_PID

echo "✅ Обновление конфигурации Xray завершено."
