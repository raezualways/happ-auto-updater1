#!/bin/bash
set -e

echo "🔄 Скачиваем свежие конфиги..."
mkdir -p /tmp/xray-configs
cd /tmp/xray-configs

# Скачиваем конфиги
wget -q -O black.txt "https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/BLACK_VLESS_RUS_mobile.txt" || echo "⚠️ black не скачался"
wget -q -O white.txt "https://raw.githubusercontent.com/igareck/vpn-configs-for-russia/main/WHITE_VLESS_RUS_mobile.txt" || echo "⚠️ white не скачался"

# Объединяем все в один файл
cat black.txt white.txt > all-configs.txt 2>/dev/null || true
if [ ! -s all-configs.txt ]; then
    echo "❌ Нет конфигов для обработки"
    exit 1
fi

# Выбираем случайную строку и пытаемся её распарсить
ATTEMPTS=0
while [ $ATTEMPTS -lt 10 ]; do
    SELECTED=$(shuf -n 1 all-configs.txt)
    echo "Попытка $((ATTEMPTS+1)): $SELECTED"

    if [[ $SELECTED =~ ^vless:// ]]; then
        PROTO="vless"
        break
    elif [[ $SELECTED =~ ^trojan:// ]]; then
        PROTO="trojan"
        break
    else
        echo "⚠️ Неподдерживаемый протокол, пробуем другой..."
        ATTEMPTS=$((ATTEMPTS+1))
    fi
done

if [ -z "$PROTO" ]; then
    echo "❌ Не удалось найти подходящий конфиг"
    exit 1
fi

# --- Установка Xray, если ещё нет ---
if ! command -v xray &> /dev/null; then
    echo "📦 Устанавливаем Xray-core..."
    curl -L https://github.com/XTLS/Xray-core/releases/download/v1.8.23/Xray-linux-64.zip -o /tmp/xray.zip
    unzip -q /tmp/xray.zip -d /tmp/xray
    sudo cp /tmp/xray/xray /usr/local/bin/
    sudo chmod +x /usr/local/bin/xray
fi

# --- Парсинг и генерация конфига в зависимости от протокола ---
if [ "$PROTO" = "vless" ]; then
    # Парсинг vless://...
    if [[ $SELECTED =~ ^vless://([^@]+)@([^:]+):([0-9]+)\?(.*)$ ]]; then
        UUID="${BASH_REMATCH[1]}"
        HOST="${BASH_REMATCH[2]}"
        PORT="${BASH_REMATCH[3]}"
        PARAMS="${BASH_REMATCH[4]}"

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

        cat > /tmp/config.json <<EOF
{
  "inbounds": [{
    "port": 1080,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": { "udp": true }
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
      "tlsSettings": { "serverName": "$SNI" },
      "wsSettings": {
        "path": "$PATH",
        "headers": { "Host": "$HOST_HEADER" }
      }
    }
  }]
}
EOF
    else
        echo "❌ Ошибка парсинга vless"
        exit 1
    fi

elif [ "$PROTO" = "trojan" ]; then
    # Парсинг trojan://password@host:port?params#name
    if [[ $SELECTED =~ ^trojan://([^@]+)@([^:]+):([0-9]+)\?(.*)#.*$ ]]; then
        PASSWORD="${BASH_REMATCH[1]}"
        HOST="${BASH_REMATCH[2]}"
        PORT="${BASH_REMATCH[3]}"
        PARAMS="${BASH_REMATCH[4]}"

        declare -A query
        IFS='&' read -ra pairs <<< "$PARAMS"
        for pair in "${pairs[@]}"; do
            IFS='=' read -r key value <<< "$pair"
            # URL декодирование (упрощённо)
            value=$(echo "$value" | sed 's/%2F/\//g; s/%3D/=/g; s/%3A/:/g')
            query["$key"]="$value"
        done

        SECURITY="${query[security]:-tls}"
        TYPE="${query[type]:-tcp}"
        PATH="${query[path]:-/}"
        HOST_HEADER="${query[host]:-$HOST}"
        SNI="${query[sni]:-$HOST}"

        cat > /tmp/config.json <<EOF
{
  "inbounds": [{
    "port": 1080,
    "listen": "127.0.0.1",
    "protocol": "socks",
    "settings": { "udp": true }
  }],
  "outbounds": [{
    "protocol": "trojan",
    "settings": {
      "servers": [{
        "address": "$HOST",
        "port": $PORT,
        "password": "$PASSWORD"
      }]
    },
    "streamSettings": {
      "network": "$TYPE",
      "security": "$SECURITY",
      "tlsSettings": { "serverName": "$SNI" },
      "wsSettings": {
        "path": "$PATH",
        "headers": { "Host": "$HOST_HEADER" }
      }
    }
  }]
}
EOF
    else
        echo "❌ Ошибка парсинга trojan"
        exit 1
    fi
fi

# --- Запуск и проверка ---
echo "🚀 Запускаем Xray с протоколом $PROTO..."
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
