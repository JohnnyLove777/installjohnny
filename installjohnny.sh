#!/bin/bash

# Função para exibir etapas com mensagens de feedback
function print_step {
    echo -e "\n🔹 $1"
}

# Função para exibir mensagens de sucesso
function print_success {
    echo -e "✅ $1\n"
}

# Função para verificar se o comando foi executado com sucesso
function checar_status {
    if [ $? -ne 0 ]; then
        echo "❌ Erro: $1"
        exit 1
    fi
}

# Função para solicitar informações ao usuário
function solicitar_informacoes {
    while true; do
        read -p "Digite o domínio (por exemplo, johnny.com.br): " DOMINIO
        if [[ $DOMINIO =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Por favor, insira um domínio válido no formato, por exemplo 'johnny.com.br'."
        fi
    done    

    while true; do
        read -p "Digite o e-mail para cadastro do Certbot (sem espaços): " EMAIL
        if [[ $EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Por favor, insira um endereço de e-mail válido sem espaços."
        fi
    done

    IP_VPS=$(curl -s ifconfig.me)
    echo "O IP da sua VPS é: $IP_VPS"

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

# Função para configurar Docker
function configurar_docker {
    print_step "1. Instalando dependências básicas... 🍀"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y software-properties-common apt-transport-https ca-certificates curl wget git nano nginx python3-certbot-nginx
    checar_status "Erro ao instalar dependências básicas."

    print_step "2. Instalando Docker... 🐳"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io
    sudo usermod -aG docker $USER
    checar_status "Erro ao instalar Docker."

    print_step "3. Instalando Docker Compose... 🔧"
    sudo curl -L "https://github.com/docker/compose/releases/download/2.26.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    checar_status "Erro ao instalar Docker Compose."

    print_success "Docker e Docker Compose instalados com sucesso!"
}

# Função principal de instalação
function instalar_evolution_api_johnnyzap {
    configurar_docker

    solicitar_informacoes

    print_step "4. Configurando NGINX... 🌐"
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
    checar_status "Erro ao reiniciar o NGINX."

    print_step "5. Gerando certificados SSL... 🔒"
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

    print_step "6. Configurando Evolution API... 🔧"
    docker run -d \
        --name evolution-api \
        -p 8099:8099 \
        -e AUTHENTICATION_API_KEY=$AUTH_KEY_INPUT \
        -v evolution_store:/evolution/store \
        -v evolution_instances:/evolution/instances \
        atendai/evolution-api:v1.8.0
    checar_status "Erro ao configurar Evolution API."

    print_step "7. Configurando JohnnyZap... 📦"
    cd /root || exit
    git clone https://github.com/JohnnyLove777/johnnyzap-classic.git
    cd johnnyzap-classic || exit
    npm install
    cat <<EOF > .env
IP_VPS=http://$IP_VPS_INPUT
EOF
    pm2 start ecosystem.config.js
    pm2 save
    print_success "JohnnyZap configurado e rodando com PM2."

    print_success "🎉 Instalação completa! Evolution API e JohnnyZap prontos 🚀"
}

# Chamada principal
instalar_evolution_api_johnnyzap
