#!/bin/bash

# Função para verificar se o comando foi executado com sucesso
function checar_status {
    if [ $? -ne 0 ]; then
        echo "❌ Erro: $1"
        exit 1
    fi
}

# Função para solicitar informações ao usuário e armazená-las em variáveis
function solicitar_informacoes {

    # Loop para solicitar e verificar o domínio
    while true; do
        read -p "Digite o domínio (por exemplo, johnny.com.br): " DOMINIO
        if [[ $DOMINIO =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Por favor, insira um domínio válido no formato, por exemplo 'johnny.com.br'."
        fi
    done    

    # Loop para solicitar e verificar o e-mail
    while true; do
        read -p "Digite o e-mail para cadastro do Certbot (sem espaços): " EMAIL
        if [[ $EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Por favor, insira um endereço de e-mail válido sem espaços."
        fi
    done

    # Obter o IP da VPS automaticamente
    IP_VPS=$(curl -s ifconfig.me)
    echo "O IP da sua VPS é: $IP_VPS"

    # Geração da chave de autenticação segura
    AUTH_KEY=$(openssl rand -hex 16)
    echo "Sua chave de autenticação é: $AUTH_KEY"
    echo "Por favor, copie esta chave e armazene em um local seguro."
    
    while true; do
        read -p "Confirme que você copiou a chave (y/n): " confirm
        if [[ $confirm == "y" ]]; then
            break
        else
            echo "Por favor, copie a chave antes de continuar."
        fi
    done

    EMAIL_INPUT=$EMAIL
    DOMINIO_INPUT=$DOMINIO
    AUTH_KEY_INPUT=$AUTH_KEY
    IP_VPS_INPUT=$IP_VPS
}

# Função para instalar Evolution API e JohnnyZap
function instalar_evolution_api_johnnyzap {

    cd ~ || exit
    echo "🌟 Diretório atual: $(pwd)"

    # Instalação de dependências
    echo "🔧 Instalando dependências..."
    sudo apt update
    sudo apt install -y ca-certificates curl gnupg lsb-release nginx certbot python3-certbot-nginx nodejs npm
    checar_status "Erro ao instalar dependências."

    if ! command -v docker &> /dev/null; then
        echo "🐳 Instalando Docker..."
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        checar_status "Erro ao instalar Docker."
    else
        echo "✅ Docker já instalado."
    fi

    if ! command -v pm2 &> /dev/null; then
        echo "🚀 Instalando PM2..."
        sudo npm install -g pm2
        checar_status "Erro ao instalar PM2."
    fi

    solicitar_informacoes

    # Configurações do NGINX
    echo "📝 Configurando NGINX..."
    cat <<EOF > /etc/nginx/sites-available/evolution
server {
    server_name evolution.$DOMINIO_INPUT;

    location / {
        proxy_pass http://127.0.0.1:8099;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    cat <<EOF > /etc/nginx/sites-available/server
server {
    server_name server.$DOMINIO_INPUT;

    location / {
        proxy_pass http://127.0.0.1:3030;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

    sudo ln -sf /etc/nginx/sites-available/evolution /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/server /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl restart nginx
    checar_status "Erro ao reiniciar NGINX."

    # Certificados SSL
    echo "🔒 Gerando certificados SSL com Certbot..."
    certbot_retry() {
        for i in {1..5}; do
            sudo certbot --nginx --email $EMAIL_INPUT --redirect --agree-tos \
                -d evolution.$DOMINIO_INPUT -d server.$DOMINIO_INPUT && return 0
            echo "⚠️ Tentativa $i de 5 falhou. Tentando novamente..."
            sleep 5
        done
        echo "❌ Falha ao gerar certificados SSL."
        exit 1
    }
    certbot_retry

    # Instalação do Evolution API
    echo "🐳 Configurando Evolution API (v1.8.0)..."
    docker run -d \
        --name evolution-api \
        -p 8099:8099 \
        -e AUTHENTICATION_API_KEY=$AUTH_KEY_INPUT \
        -v evolution_store:/evolution/store \
        -v evolution_instances:/evolution/instances \
        atendai/evolution-api:v1.8.0
    checar_status "Erro ao configurar Evolution API."

    # Instalação do JohnnyZap
    echo "📦 Configurando JohnnyZap..."
    cd /root || exit
    git clone https://github.com/JohnnyLove777/johnnyzap-classic.git
    cd johnnyzap-classic || exit
    npm install
    cat <<EOF > .env
IP_VPS=http://$IP_VPS_INPUT
EOF
    pm2 start ecosystem.config.js
    pm2 save
    echo "✅ JohnnyZap configurado e rodando com PM2."

    echo "🎉 Instalação completa! Evolution API e JohnnyZap prontos 🚀"
}

# Chamada principal
instalar_evolution_api_johnnyzap
