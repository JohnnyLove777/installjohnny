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

    echo "🌟 Bem-vindo ao instalador! Vamos configurar seu ambiente 🚀"

    # Loop para solicitar e verificar o domínio
    while true; do
        read -p "Digite o domínio (por exemplo, johnny.com.br): " DOMINIO
        # Verifica se o domínio tem um formato válido
        if [[ $DOMINIO =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo "✅ Domínio válido: $DOMINIO"
            break
        else
            echo "⚠️ Por favor, insira um domínio válido no formato 'exemplo.com.br'."
        fi
    done    

    # Loop para solicitar e verificar o e-mail
    while true; do
        read -p "Digite o e-mail para cadastro do Certbot (sem espaços): " EMAIL
        # Verifica se o e-mail tem o formato correto e não contém espaços
        if [[ $EMAIL =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo "✅ E-mail válido: $EMAIL"
            break
        else
            echo "⚠️ Por favor, insira um endereço de e-mail válido sem espaços."
        fi
    done

    # Obter o IP da VPS automaticamente (sem precisar do usuário inserir)
    IP_VPS=$(curl -s ifconfig.me)
    echo "🌐 O IP da sua VPS é: $IP_VPS"

    # Geração da chave de autenticação segura
    AUTH_KEY=$(openssl rand -hex 16)
    echo "🔑 Sua chave de autenticação é: $AUTH_KEY"
    echo "⚠️ Por favor, copie esta chave e armazene em um local seguro."
    
    while true; do
        read -p "Confirme que você copiou a chave (y/n): " confirm
        if [[ $confirm == "y" ]]; then
            echo "✅ Chave confirmada!"
            break
        else
            echo "⚠️ Por favor, copie a chave antes de continuar."
        fi
    done

    # Armazena as informações inseridas pelo usuário nas variáveis globais
    EMAIL_INPUT=$EMAIL
    DOMINIO_INPUT=$DOMINIO
    AUTH_KEY_INPUT=$AUTH_KEY
    IP_VPS_INPUT=$IP_VPS
}

# Função para instalar Evolution API e JohnnyZap
function instalar_evolution_api_johnnyzap {

    echo "🔧 Iniciando a instalação e configuração do ambiente..."

    # Instalação do Docker e Docker Compose
    if ! command -v docker &> /dev/null; then
        echo "🐳 Docker não encontrado. Instalando Docker e Docker Compose..."
        
        # Adicionar repositório do Docker
        sudo apt update
        sudo apt install -y ca-certificates curl gnupg lsb-release
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Instalar Docker Engine e Docker Compose
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        checar_status "Falha ao instalar Docker e Docker Compose."
    else
        echo "✅ Docker já está instalado! Pulando a instalação."
    fi

    # Verificar se o NGINX está instalado
    if ! command -v nginx &> /dev/null; then
        echo "🌐 Instalando NGINX..."
        sudo apt install -y nginx
        checar_status "Falha ao instalar o NGINX."
    else
        echo "✅ NGINX já está instalado!"
    fi

    # Instalar Certbot se necessário
    if ! command -v certbot &> /dev/null; then
        echo "🔐 Instalando Certbot e plugins do NGINX..."
        sudo apt install -y certbot python3-certbot-nginx
        checar_status "Falha ao instalar Certbot."
    else
        echo "✅ Certbot já está instalado!"
    fi

    # Instalação do Node.js e PM2
    if ! command -v node &> /dev/null || ! command -v npm &> /dev/null; then
        echo "📦 Instalando Node.js e npm..."
        sudo apt install -y nodejs npm
        checar_status "Falha ao instalar Node.js e npm."
    fi

    if ! command -v pm2 &> /dev/null; then
        echo "📂 Instalando PM2..."
        sudo npm install -g pm2
        checar_status "Falha ao instalar PM2."
    fi

    # Solicita informações ao usuário
    solicitar_informacoes

    # Criação dos arquivos de configuração do NGINX para Evolution API e JohnnyZap
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

    # Criação dos links simbólicos e reinicialização do NGINX
    sudo ln -sf /etc/nginx/sites-available/evolution /etc/nginx/sites-enabled/
    sudo ln -sf /etc/nginx/sites-available/server /etc/nginx/sites-enabled/
    sudo systemctl restart nginx
    checar_status "Falha ao reiniciar o NGINX."

    # Função de Retry para o Certbot
    function certbot_retry {
        local retries=5
        local count=0
        while ((count < retries)); do
            sudo certbot --nginx --email $EMAIL_INPUT --redirect --agree-tos \
                -d evolution.$DOMINIO_INPUT -d server.$DOMINIO_INPUT
            if [ $? -eq 0 ]; then
                echo "✅ Certificado SSL obtido com sucesso!"
                return 0
            fi
            echo "⚠️ Certbot falhou. Tentando novamente... ($((count+1)) de $retries)"
            ((count++))
            sleep 5
        done
        echo "❌ Certbot falhou após $retries tentativas. Verifique a configuração."
        exit 1
    }

    # Chama a função de retry para o Certbot
    certbot_retry

    # Instalação e configuração da Evolution API usando Docker com volumes persistentes
    echo "🚀 Configurando Evolution API na porta 8099..."
    docker run -d \
        --name evolution-api \
        -p 8099:8099 \
        -e AUTHENTICATION_API_KEY=$AUTH_KEY_INPUT \
        -v evolution_store:/evolution/store \
        -v evolution_instances:/evolution/instances \
        atendai/evolution-api:v1.8.2
    echo "✅ Evolution API instalada e configurada com sucesso!"

    # Instalação do JohnnyZap no diretório do usuário atual
    echo "📂 Instalando JohnnyZap em /root/johnnyzap-classic..."
    cd /root || exit
    git clone https://github.com/JohnnyLove777/johnnyzap-classic.git
    cd johnnyzap-classic || exit

    echo "📦 Instalando dependências do JohnnyZap..."
    npm install

    # Criação do arquivo .env com o IP da VPS
    echo "🌍 Criando arquivo .env..."
cat <<EOF > .env
VPS_IP=$IP_VPS_INPUT
EOF

    # Inicializa o JohnnyZap com PM2
    pm2 start npm --name "johnnyzap" -- start
    pm2 save
    echo "✅ JohnnyZap instalado e rodando com PM2!"

    echo "🎉 Ambiente configurado com sucesso! Evolution API e JohnnyZap estão prontos 🚀"
}

# Chamada principal da função de instalação
instalar_evolution_api_johnnyzap
