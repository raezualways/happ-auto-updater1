#!/bin/bash
set -ex

echo "🔄 Скачиваем свежие конфиги..."
mkdir -p /tmp/xray-configs
cd /tmp/xray-configs

# Скачиваем подписки
wget -q -O black.txt "https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS_mobile.txt" || echo "⚠️ black не скачался"
wget -q -O white.txt "https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/WHITE_VLESS_RUS_mobile.txt" || echo "⚠️ white не скачался"

# Объединяем
cat black.txt white.txt > all-configs.txt 2>/dev/null || true
if [ ! -s all-configs.txt ]; then
    echo "❌ Нет конфигов для обработки"
    exit 1
fi

# Выбираем случайную строку
SELECTED=$(shuf -n 1 all-configs.txt)
echo "Выбран конфиг: $SELECTED"

# --- Парсинг VLESS ссылки ---
if [[ $SELECTED =~ ^vless://([^@]+)@([^:]+):([0-9]+)\?(.*)$ ]]; then
    UUID="${BASH_REMATCH[1]}"
    HOST="${BASH_REMATCH[2]}"
    PORT="${BASH_REMATCH[3]}"
    PARAMS="${BASH_REMATCH[4]}"

    # Парсим параметры запроса
    declare -A query
    IFS='&' read -ra pairs <<< "$PARAMS"
    for pair in "${pairs[@]}"; do
        IFS='=' read -r key value <<< "$pair"
        query["$key"]="$value"
    done

    ENCRYPTION="${query[encryption]:-none}"
    SECURITY="${query[security]:-tls}"
    TYPE="${query[type]:-tcp}"
    PATH="${query[path]:-/}"
    HOST_HEADER="${query[host]:-$HOST}"
    SNI="${query[sni]:-$HOST}"
    FLOW="${query[flow]:-}"

    echo "📋 Параметры:"
    echo "  UUID: $UUID"
    echo "  Host: $HOST"
    echo "  Port: $PORT"
    echo "  Security: $SECURITY"
    echo "  Type: $TYPE"
    echo "  Path: $PATH"

    # Генерируем конфиг Xray
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
          "encryption": "$ENCRYPTION",
          "flow": "$FLOW"
        }]
      }]
    },
    "streamSettings": {
      "network": "$TYPE",
      "security": "$SECURITY",
      "tlsSettings": {
        "serverName": "$SNI"
      },
      "wsSettings": {
        "path": "$PATH",
        "headers": {
          "Host": "$HOST_HEADER"
        }
      }
    }
  }]
}
EOF
else
    echo "❌ Строка не является валидной vless ссылкой"
    exit 1
fi

# --- Установка Xray ---
if ! command -v xray &> /dev/null; then
    echo "📦 Устанавливаем Xray-core..."
    curl -L https://github.com/XTLS/Xray-core/releases/download/v1.8.23/Xray-linux-64.zip -o /tmp/xray.zip
    unzip -q /tmp/xray.zip -d /tmp/xray
    sudo cp /tmp/xray/xray /usr/local/bin/
    sudo chmod +x /usr/local/bin/xray
fi

# --- Запуск и проверка ---
echo "🚀 Запускаем Xray..."
xray run -c /tmp/config.json &
XRAY_PID=$!
sleep 5

echo "🌐 Проверка IP через прокси..."
IP=$(curl -s --socks5 127.0.0.1:1080 ifconfig.me)
if [ -n "$IP" ]; then
    echo "✅ VPN работает. IP: $IP"
else
    echo "❌ Не удалось подключиться через прокси"
    cat /tmp/config.json
    exit 1
fi

kill $XRAY_PID
echo "✅ Готово."
echo "✅ Обновление конфигурации Xray завершено."
