#!/bin/bash

# Script Admin Completo para Gerenciamento do Servidor Web - Oracle Cloud Compatible
# Suporte para Oracle Linux, Ubuntu, CentOS, RHEL e outras distribuições
# Autor: @VEM_BRABO - Versão Oracle Cloud Enhanced

# Cores para interface
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Configurações
SCRIPT_VERSION="2.1-OCI"
LOG_FILE="/var/log/webadmin.log"

# Detectar distribuição do sistema
detect_os() {
    if [[ -f /etc/oracle-release ]]; then
        OS="oracle"
        OS_VERSION=$(grep -oP '\d+' /etc/oracle-release | head -1)
        PKG_MANAGER="dnf"
        SERVICE_MANAGER="systemctl"
        WEB_USER="apache"
        WEB_GROUP="apache"
        WEB_SERVICE="httpd"
        PHP_SERVICE="php-fpm"
        MYSQL_SERVICE="mariadb"
        FIREWALL_SERVICE="firewalld"
        echo "Oracle Linux $OS_VERSION detectado"
    elif [[ -f /etc/redhat-release ]]; then
        if grep -q "CentOS\|Red Hat" /etc/redhat-release; then
            OS="rhel"
            OS_VERSION=$(grep -oP '\d+' /etc/redhat-release | head -1)
            PKG_MANAGER="dnf"
            [[ "$OS_VERSION" -lt 8 ]] && PKG_MANAGER="yum"
            SERVICE_MANAGER="systemctl"
            WEB_USER="apache"
            WEB_GROUP="apache"
            WEB_SERVICE="httpd"
            PHP_SERVICE="php-fpm"
            MYSQL_SERVICE="mariadb"
            FIREWALL_SERVICE="firewalld"
            echo "RHEL/CentOS $OS_VERSION detectado"
        fi
    elif [[ -f /etc/lsb-release ]] || command -v lsb_release >/dev/null 2>&1; then
        OS="ubuntu"
        OS_VERSION=$(lsb_release -rs 2>/dev/null || grep VERSION_ID /etc/os-release | cut -d'"' -f2)
        PKG_MANAGER="apt"
        SERVICE_MANAGER="systemctl"
        WEB_USER="www-data"
        WEB_GROUP="www-data"
        WEB_SERVICE="apache2"
        PHP_SERVICE="php8.1-fpm"
        MYSQL_SERVICE="mysql"
        FIREWALL_SERVICE="ufw"
        echo "Ubuntu $OS_VERSION detectado"
    elif [[ -f /etc/debian_version ]]; then
        OS="debian"
        OS_VERSION=$(cat /etc/debian_version)
        PKG_MANAGER="apt"
        SERVICE_MANAGER="systemctl"
        WEB_USER="www-data"
        WEB_GROUP="www-data"
        WEB_SERVICE="apache2"
        PHP_SERVICE="php8.1-fpm"
        MYSQL_SERVICE="mysql"
        FIREWALL_SERVICE="ufw"
        echo "Debian $OS_VERSION detectado"
    else
        OS="unknown"
        echo "Sistema operacional não reconhecido, usando configurações padrão"
        PKG_MANAGER="apt"
        SERVICE_MANAGER="systemctl"
        WEB_USER="www-data"
        WEB_GROUP="www-data"
        WEB_SERVICE="apache2"
        PHP_SERVICE="php8.1-fpm"
        MYSQL_SERVICE="mysql"
        FIREWALL_SERVICE="ufw"
    fi
    
    # Detectar versão PHP disponível para sistemas RHEL
    if [[ "$OS" == "oracle" || "$OS" == "rhel" ]]; then
        if command -v php >/dev/null 2>&1; then
            PHP_VERSION=$(php -v | head -1 | grep -oP '\d\.\d' | head -1)
            PHP_SERVICE="php-fpm"
        fi
    fi
}

# Função universal para instalar pacotes
install_package() {
    local packages="$@"
    
    case $PKG_MANAGER in
        "apt")
            apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y $packages
            ;;
        "dnf")
            dnf install -y $packages
            ;;
        "yum")
            yum install -y $packages
            ;;
    esac
}

# Função universal para atualizar sistema
update_system_universal() {
    echo -e "${YELLOW}Atualizando sistema ($OS)...${NC}"
    
    case $PKG_MANAGER in
        "apt")
            apt-get update && apt-get upgrade -y
            apt-get autoremove -y && apt-get autoclean
            ;;
        "dnf")
            dnf update -y
            dnf autoremove -y
            ;;
        "yum")
            yum update -y
            yum autoremove -y
            ;;
    esac
}

# Detectar e configurar MySQL/MariaDB
setup_database_service() {
    echo -e "${YELLOW}Configurando banco de dados...${NC}"
    
    if [[ "$OS" == "oracle" ]] || [[ "$OS" == "rhel" ]]; then
        # Oracle Linux e RHEL usam MariaDB por padrão
        if ! systemctl is-active mariadb >/dev/null 2>&1 && ! systemctl is-active mysqld >/dev/null 2>&1; then
            echo -e "${YELLOW}Instalando MariaDB...${NC}"
            install_package mariadb-server mariadb
            systemctl enable mariadb
            systemctl start mariadb
            MYSQL_SERVICE="mariadb"
            
            # Configuração básica de segurança
            mysql -e "UPDATE mysql.user SET Password=PASSWORD('root123!@#') WHERE User='root';" 2>/dev/null
            mysql -e "DELETE FROM mysql.user WHERE User='';" 2>/dev/null
            mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
        fi
    else
        # Ubuntu/Debian usam MySQL
        if ! systemctl is-active mysql >/dev/null 2>&1; then
            echo -e "${YELLOW}Instalando MySQL...${NC}"
            install_package mysql-server mysql-client
            systemctl enable mysql
            systemctl start mysql
            MYSQL_SERVICE="mysql"
        fi
    fi
}

# Configurar PHP baseado na distribuição
setup_php_service() {
    echo -e "${YELLOW}Configurando PHP...${NC}"
    
    case $OS in
        "oracle"|"rhel")
            # Oracle Linux e RHEL
            if [[ "$OS_VERSION" -ge 8 ]]; then
                install_package php php-fpm php-mysqlnd php-gd php-mbstring php-xml php-curl php-zip php-json php-opcache
                PHP_SERVICE="php-fpm"
                systemctl enable php-fpm
                systemctl start php-fpm
                
                # Configurar PHP-FPM para trabalhar com Apache
                if [[ -f "/etc/php-fpm.d/www.conf" ]]; then
                    sed -i 's/user = apache/user = apache/g' /etc/php-fpm.d/www.conf
                    sed -i 's/group = apache/group = apache/g' /etc/php-fpm.d/www.conf
                fi
            fi
            ;;
        "ubuntu"|"debian")
            # Ubuntu e Debian
            install_package php libapache2-mod-php php-mysql php-gd php-mbstring php-xml php-curl php-zip php-opcache
            # Também instalar PHP-FPM como opção
            install_package php8.1-fpm
            systemctl enable php8.1-fpm
            systemctl start php8.1-fpm
            ;;
    esac
}

# Configurar Apache baseado na distribuição
setup_apache_service() {
    echo -e "${YELLOW}Configurando Apache...${NC}"
    
    case $OS in
        "oracle"|"rhel")
            install_package httpd httpd-tools mod_ssl
            systemctl enable httpd
            systemctl start httpd
            
            # Configurar diretórios específicos para Oracle Linux
            mkdir -p /var/www/html/sites
            mkdir -p /etc/httpd/sites-available
            mkdir -p /etc/httpd/sites-enabled
            
            # Adicionar include no httpd.conf se não existir
            if ! grep -q "sites-enabled" /etc/httpd/conf/httpd.conf; then
                echo "IncludeOptional sites-enabled/*.conf" >> /etc/httpd/conf/httpd.conf
            fi
            
            # Habilitar mod_rewrite
            if ! grep -q "LoadModule rewrite_module" /etc/httpd/conf/httpd.conf; then
                echo "LoadModule rewrite_module modules/mod_rewrite.so" >> /etc/httpd/conf/httpd.conf
            fi
            ;;
        "ubuntu"|"debian")
            install_package apache2 apache2-utils
            systemctl enable apache2
            systemctl start apache2
            
            a2enmod rewrite
            a2enmod ssl
            a2enmod headers
            a2enmod expires
            ;;
    esac
}

# Função para logging
log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$OS] - $1" >> "$LOG_FILE"
}

# Função para cabeçalho adaptada
show_header() {
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}                    🌐 WEB SERVER ADMIN v$SCRIPT_VERSION ($OS)                    ${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}                Sistema Completo de Administração Web Oracle Cloud          ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Função para mostrar status geral adaptada
show_status() {
    echo -e "${WHITE}┌─ STATUS DO SISTEMA ($OS $OS_VERSION) ──────────────────────────────────────────┐${NC}"
    
    # Lista de serviços baseada no OS
    case $OS in
        "oracle"|"rhel")
            services=("httpd" "mariadb" "php-fpm" "redis" "memcached" "firewalld")
            ;;
        "ubuntu"|"debian")
            services=("apache2" "mysql" "php8.1-fpm" "redis-server" "memcached" "ufw")
            ;;
        *)
            services=("apache2" "mysql" "php-fpm")
            ;;
    esac
    
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo -e "${WHITE}│${NC} ${GREEN}✅ $service${NC} $(printf '%*s' $((60-${#service})) '') ${GREEN}ATIVO${NC}   ${WHITE}│${NC}"
        else
            echo -e "${WHITE}│${NC} ${RED}❌ $service${NC} $(printf '%*s' $((60-${#service})) '') ${RED}INATIVO${NC} ${WHITE}│${NC}"
        fi
    done
    
    echo -e "${WHITE}├──────────────────────────────────────────────────────────────────────────────┤${NC}"
    
    # Informações do sistema
    local os_info
    case $OS in
        "oracle")
            os_info="Oracle Linux $OS_VERSION"
            ;;
        "ubuntu")
            os_info=$(lsb_release -ds 2>/dev/null || echo "Ubuntu $OS_VERSION")
            ;;
        *)
            os_info="$OS $OS_VERSION"
            ;;
    esac
    
    echo -e "${WHITE}│${NC} ${BLUE}🖥️  Sistema:${NC} $os_info $(printf '%*s' $((47-${#os_info})) '') ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC} ${BLUE}⏱️  Uptime:${NC} $(uptime -p) $(printf '%*s' $((52-${#$(uptime -p)})) '') ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC} ${BLUE}🌐 IP Ext:${NC} $(curl -s ifconfig.me 2>/dev/null || echo 'N/A') $(printf '%*s' $((47-${#$(curl -s ifconfig.me 2>/dev/null || echo 'N/A')})) '') ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC} ${BLUE}🐘 PHP:${NC} $(php -v 2>/dev/null | head -1 | awk '{print $2}' || echo 'N/A') $(printf '%*s' $((52-${#$(php -v 2>/dev/null | head -1 | awk '{print $2}' || echo 'N/A')})) '') ${WHITE}│${NC}"
    
    # Uso de recursos
    memory_info=$(free | grep Mem | awk '{printf "%.1f%% (%.1fG/%.1fG)", ($3/$2)*100, $3/1024/1024, $2/1024/1024}')
    disk_info=$(df -h / | tail -1 | awk '{print $5 " (" $3 "/" $2 ")"}')
    
    echo -e "${WHITE}│${NC} ${YELLOW}💾 RAM:${NC} $memory_info $(printf '%*s' $((50-${#memory_info})) '') ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC} ${YELLOW}💽 Disco:${NC} $disk_info $(printf '%*s' $((49-${#disk_info})) '') ${WHITE}│${NC}"
    
    echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Menu principal
show_main_menu() {
    echo -e "${WHITE}┌─ MENU PRINCIPAL ($OS) ──────────────────────────────────────────────────────┐${NC}"
    echo -e "${WHITE}│${NC}                                                                              ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC}  ${GREEN}1.${NC}  🌐 Gerenciar Domínios e Sites              ${GREEN}11.${NC} 📊 Estatísticas Web    ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC}  ${GREEN}2.${NC}  📁 Gerenciar Projetos                      ${GREEN}12.${NC} 📈 Monitor Sistema     ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC}  ${GREEN}3.${NC}  🐘 Gerenciar PHP                           ${GREEN}13.${NC} 🔐 Gerenciar SSL       ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC}  ${GREEN}4.${NC}  🗄️  Gerenciar MySQL/Banco                   ${GREEN}14.${NC} 🛡️  Segurança           ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC}  ${GREEN}5.${NC}  🚀 Apache & Serviços                       ${GREEN}15.${NC} 📋 Logs do Sistema     ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC}  ${GREEN}6.${NC}  💾 Backup & Restore                        ${GREEN}16.${NC} ⚙️  Configurações       ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC}  ${GREEN}7.${NC}  🔧 Manutenção & Otimização                 ${GREEN}17.${NC} 🌡️  Temperaturas        ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC}  ${GREEN}8.${NC}  📦 Instalar Software                       ${GREEN}18.${NC} 🔄 Atualizações        ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC}  ${GREEN}9.${NC}  🔌 Cache (Redis/Memcached)                 ${GREEN}19.${NC} 📖 Documentação       ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC}  ${GREEN}10.${NC} 🛠️  Ferramentas do Sistema                  ${GREEN}88.${NC} 🔧 Config Inicial     ${WHITE}│${NC}"
    echo -e "${WHITE}│${NC}  ${GREEN}0.${NC}  🚪 Sair                                    ${GREEN}99.${NC} ℹ️  Info Sistema        ${WHITE}│${NC}"
    echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
}

# Função para adicionar domínio (adaptada)
add_domain_universal() {
    local domain=$1
    local type=${2:-"domain"}
    
    case $OS in
        "oracle"|"rhel")
            add_domain_rhel "$domain" "$type"
            ;;
        "ubuntu"|"debian")
            add_domain_debian "$domain" "$type"
            ;;
    esac
}

add_domain_rhel() {
    local domain=$1
    local type=$2
    
    # Criar estrutura de diretórios
    mkdir -p "/var/www/html/sites/$domain"
    mkdir -p "/var/log/httpd/domains/$domain"
    
    # Criar arquivo de configuração
    cat > "/etc/httpd/sites-available/$domain.conf" << VHOST
<VirtualHost *:80>
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot /var/www/html/sites/$domain
    
    ErrorLog /var/log/httpd/domains/$domain/error.log
    CustomLog /var/log/httpd/domains/$domain/access.log combined
    
    <Directory /var/www/html/sites/$domain>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
    
    # PHP-FPM Configuration
    <FilesMatch \.php$>
        SetHandler "proxy:fcgi://127.0.0.1:9000"
    </FilesMatch>
</VirtualHost>
VHOST
    
    # Habilitar site
    ln -sf "/etc/httpd/sites-available/$domain.conf" "/etc/httpd/sites-enabled/$domain.conf"
    
    # Criar página de teste
    cat > "/var/www/html/sites/$domain/index.html" << HTML
<!DOCTYPE html>
<html>
<head>
    <title>$domain - Funcionando!</title>
    <style>body{font-family:Arial,sans-serif;text-align:center;margin-top:100px;}</style>
</head>
<body>
    <h1>🎉 Domínio $domain configurado com sucesso!</h1>
    <p>Oracle Linux - Apache - PHP - Sistema funcionando</p>
    <p><small>$(date)</small></p>
</body>
</html>
HTML
    
    # Criar página PHP de teste
    cat > "/var/www/html/sites/$domain/info.php" << 'PHP'
<?php
echo "<h1>PHP Funcionando!</h1>";
echo "<p>Versão PHP: " . PHP_VERSION . "</p>";
echo "<p>Sistema: " . php_uname() . "</p>";
echo "<p>Data: " . date('Y-m-d H:i:s') . "</p>";
?>
PHP
    
    # Definir permissões
    chown -R $WEB_USER:$WEB_GROUP "/var/www/html/sites/$domain"
    chmod -R 755 "/var/www/html/sites/$domain"
    
    # Reiniciar Apache
    systemctl reload httpd
    
    echo -e "${GREEN}Domínio $domain configurado com sucesso!${NC}"
}

add_domain_debian() {
    local domain=$1
    local type=$2
    
    # Usar o método original para Ubuntu/Debian
    mkdir -p "/var/www/html/sites/$domain"
    mkdir -p "/var/log/apache2/domains/$domain"
    
    cat > "/etc/apache2/sites-available/$domain.conf" << VHOST
<VirtualHost *:80>
    ServerName $domain
    ServerAlias www.$domain
    DocumentRoot /var/www/html/sites/$domain
    
    ErrorLog /var/log/apache2/domains/$domain/error.log
    CustomLog /var/log/apache2/domains/$domain/access.log combined
    
    <Directory /var/www/html/sites/$domain>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
VHOST
    
    a2ensite "$domain"
    
    cat > "/var/www/html/sites/$domain/index.html" << HTML
<!DOCTYPE html>
<html>
<head>
    <title>$domain - Funcionando!</title>
    <style>body{font-family:Arial,sans-serif;text-align:center;margin-top:100px;}</style>
</head>
<body>
    <h1>🎉 Domínio $domain configurado com sucesso!</h1>
    <p>Ubuntu - Apache - PHP - Sistema funcionando</p>
    <p><small>$(date)</small></p>
</body>
</html>
HTML
    
    cat > "/var/www/html/sites/$domain/info.php" << 'PHP'
<?php
echo "<h1>PHP Funcionando!</h1>";
echo "<p>Versão PHP: " . PHP_VERSION . "</p>";
echo "<p>Sistema: " . php_uname() . "</p>";
echo "<p>Data: " . date('Y-m-d H:i:s') . "</p>";
?>
PHP
    
    chown -R $WEB_USER:$WEB_GROUP "/var/www/html/sites/$domain"
    chmod -R 755 "/var/www/html/sites/$domain"
    
    systemctl reload apache2
    
    echo -e "${GREEN}Domínio $domain configurado com sucesso!${NC}"
}

# Função para configurar firewall baseado na distribuição
configure_firewall() {
    case $OS in
        "oracle"|"rhel")
            if systemctl is-active firewalld >/dev/null 2>&1; then
                echo -e "${YELLOW}Configurando FirewallD...${NC}"
                firewall-cmd --permanent --add-service=http
                firewall-cmd --permanent --add-service=https
                firewall-cmd --permanent --add-service=ssh
                firewall-cmd --reload
                echo -e "${GREEN}FirewallD configurado!${NC}"
            else
                echo -e "${YELLOW}Iniciando FirewallD...${NC}"
                systemctl enable firewalld
                systemctl start firewalld
                firewall-cmd --permanent --add-service=http
                firewall-cmd --permanent --add-service=https
                firewall-cmd --permanent --add-service=ssh
                firewall-cmd --reload
            fi
            ;;
        "ubuntu"|"debian")
            if command -v ufw >/dev/null; then
                echo -e "${YELLOW}Configurando UFW...${NC}"
                ufw --force enable
                ufw allow 22/tcp
                ufw allow 80/tcp
                ufw allow 443/tcp
                echo -e "${GREEN}UFW configurado!${NC}"
            fi
            ;;
    esac
}

# Função para instalar SSL (Let's Encrypt) - universal
install_ssl_universal() {
    local domain=$1
    
    # Instalar certbot baseado na distribuição
    case $PKG_MANAGER in
        "apt")
            install_package certbot python3-certbot-apache
            ;;
        "dnf"|"yum")
            if [[ "$OS" == "oracle" ]]; then
                # Oracle Linux precisa do EPEL
                dnf install -y oracle-epel-release-el$OS_VERSION
                install_package certbot python3-certbot-apache
            else
                install_package certbot python3-certbot-apache
            fi
            ;;
    esac
    
    # Obter certificado
    certbot --apache -d "$domain" -d "www.$domain" --non-interactive --agree-tos --email admin@"$domain" --redirect
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}SSL configurado com sucesso para $domain!${NC}"
        log_action "SSL configurado para $domain"
    else
        echo -e "${RED}Erro ao configurar SSL para $domain${NC}"
    fi
}

# Função principal de instalação inicial
initial_setup() {
    echo -e "${CYAN}═══ CONFIGURAÇÃO INICIAL PARA ORACLE CLOUD ═══${NC}"
    echo ""
    
    # Atualizar sistema
    update_system_universal
    
    # Instalar dependências básicas
    case $PKG_MANAGER in
        "apt")
            install_package wget curl unzip git nano htop net-tools tree
            ;;
        "dnf"|"yum")
            install_package wget curl unzip git nano htop net-tools tree
            # Instalar EPEL para Oracle Linux
            if [[ "$OS" == "oracle" ]]; then
                dnf install -y oracle-epel-release-el$OS_VERSION
            fi
            ;;
    esac
    
    # Configurar serviços
    setup_apache_service
    setup_php_service
    setup_database_service
    
    # Configurar firewall
    configure_firewall
    
    # Criar estruturas básicas
    mkdir -p /var/www/html/sites
    mkdir -p /var/backups/websites
    mkdir -p /var/backups/databases
    
    echo -e "${GREEN}Configuração inicial concluída!${NC}"
    log_action "Configuração inicial concluída para $OS"
}

# Verificar se é primeira execução
first_run_check() {
    if [[ ! -f "/etc/webadmin-configured" ]]; then
        echo -e "${YELLOW}Primeira execução detectada. Iniciando configuração inicial...${NC}"
        initial_setup
        touch "/etc/webadmin-configured"
        echo "OS=$OS" > "/etc/webadmin-configured"
        echo "PKG_MANAGER=$PKG_MANAGER" >> "/etc/webadmin-configured"
    fi
}

# Função de gerenciamento de domínios adaptada
manage_domains() {
    while true; do
        clear
        show_header
        echo -e "${WHITE}┌─ GERENCIAMENTO DE DOMÍNIOS ($OS) ────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}1.${NC} Adicionar Domínio Principal                                            ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}2.${NC} Adicionar Subdomínio                                                  ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}3.${NC} Listar Todos os Domínios                                              ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}4.${NC} Remover Domínio                                                       ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}5.${NC} Configurar SSL (Let's Encrypt)                                        ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}6.${NC} Verificar Status dos Sites                                            ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}0.${NC} Voltar ao Menu Principal                                              ${WHITE}│${NC}"
        echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
        
        case $choice in
            1)
                echo ""
                read -p "$(echo -e ${CYAN}"Digite o nome do domínio (ex: exemplo.com): "${NC})" domain
                if [[ -n "$domain" ]]; then
                    echo -e "${YELLOW}Adicionando domínio $domain...${NC}"
                    add_domain_universal "$domain" "domain"
                    log_action "Domínio adicionado: $domain"
                    read -p "Pressione Enter para continuar..."
                fi
                ;;
            2)
                echo ""
                read -p "$(echo -e ${CYAN}"Digite o subdomínio (ex: blog.exemplo.com): "${NC})" subdomain
                if [[ -n "$subdomain" ]]; then
                    echo -e "${YELLOW}Adicionando subdomínio $subdomain...${NC}"
                    add_domain_universal "$subdomain" "subdomain"
                    log_action "Subdomínio adicionado: $subdomain"
                    read -p "Pressione Enter para continuar..."
                fi
                ;;
            3)
                echo ""
                echo -e "${CYAN}═══ DOMÍNIOS CONFIGURADOS ═══${NC}"
                list_domains_universal
                echo ""
                read -p "Pressione Enter para continuar..."
                ;;
            4)
                remove_domain_universal
                ;;
            5)
                echo ""
                read -p "$(echo -e ${CYAN}"Digite o domínio para SSL: "${NC})" domain
                if [[ -n "$domain" ]]; then
                    echo -e "${YELLOW}Configurando SSL para $domain...${NC}"
                    install_ssl_universal "$domain"
                    read -p "Pressione Enter para continuar..."
                fi
                ;;
            6)
                check_sites_status_universal
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}Opção inválida!${NC}"
                sleep 2
                ;;
        esac
    done
}

# Listar domínios de forma universal
# Continuação do script - Listar domínios e demais funcionalidades

list_domains_universal() {
    case $OS in
        "oracle"|"rhel")
            if [[ -d "/etc/httpd/sites-available" ]]; then
                for conf in /etc/httpd/sites-available/*.conf; do
                    if [[ -f "$conf" ]]; then
                        domain=$(basename "$conf" .conf)
                        if [[ -L "/etc/httpd/sites-enabled/$domain.conf" ]]; then
                            echo -e "${GREEN}✅ $domain (ativo)${NC}"
                        else
                            echo -e "${YELLOW}⚠️  $domain (inativo)${NC}"
                        fi
                    fi
                done
            else
                echo "Nenhum domínio encontrado"
            fi
            ;;
        "ubuntu"|"debian")
            if [[ -d "/etc/apache2/sites-available" ]]; then
                for conf in /etc/apache2/sites-available/*.conf; do
                    if [[ -f "$conf" ]]; then
                        domain=$(basename "$conf" .conf)
                        if [[ "$domain" != "000-default" && "$domain" != "default-ssl" ]]; then
                            if [[ -L "/etc/apache2/sites-enabled/$domain.conf" ]]; then
                                echo -e "${GREEN}✅ $domain (ativo)${NC}"
                            else
                                echo -e "${YELLOW}⚠️  $domain (inativo)${NC}"
                            fi
                        fi
                    fi
                done
            else
                echo "Nenhum domínio encontrado"
            fi
            ;;
    esac
}

# Remover domínio universal
remove_domain_universal() {
    echo ""
    echo -e "${CYAN}Domínios disponíveis para remoção:${NC}"
    list_domains_universal
    echo ""
    
    read -p "$(echo -e ${CYAN}"Digite o domínio para remover: "${NC})" domain
    if [[ -n "$domain" ]]; then
        read -p "$(echo -e ${RED}"Tem certeza que deseja remover $domain? (s/N): "${NC})" confirm
        if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
            case $OS in
                "oracle"|"rhel")
                    # Desabilitar site
                    rm -f "/etc/httpd/sites-enabled/$domain.conf"
                    rm -f "/etc/httpd/sites-available/$domain.conf"
                    systemctl reload httpd
                    ;;
                "ubuntu"|"debian")
                    a2dissite "$domain" 2>/dev/null
                    rm -f "/etc/apache2/sites-available/$domain.conf"
                    systemctl reload apache2
                    ;;
            esac
            
            # Perguntar se deve remover arquivos
            read -p "$(echo -e ${YELLOW}"Remover também os arquivos do site? (s/N): "${NC})" remove_files
            if [[ "$remove_files" == "s" || "$remove_files" == "S" ]]; then
                rm -rf "/var/www/html/sites/$domain"
            fi
            
            # Remover logs
            rm -rf "/var/log/httpd/domains/$domain" 2>/dev/null
            rm -rf "/var/log/apache2/domains/$domain" 2>/dev/null
            
            echo -e "${GREEN}Domínio $domain removido com sucesso!${NC}"
            log_action "Domínio removido: $domain"
        fi
    fi
    read -p "Pressione Enter para continuar..."
}

# Verificar status dos sites
check_sites_status_universal() {
    echo ""
    echo -e "${CYAN}═══ STATUS DOS SITES ═══${NC}"
    
    if [[ -d "/var/www/html/sites" ]]; then
        for site_dir in /var/www/html/sites/*/; do
            if [[ -d "$site_dir" ]]; then
                domain=$(basename "$site_dir")
                
                # Testar conectividade local
                if curl -s -o /dev/null -w "%{http_code}" "http://localhost" -H "Host: $domain" | grep -q "200\|301\|302"; then
                    echo -e "${GREEN}✅ $domain - OK (local)${NC}"
                else
                    echo -e "${RED}❌ $domain - ERRO (local)${NC}"
                fi
                
                # Mostrar tamanho do site
                size=$(du -sh "$site_dir" 2>/dev/null | awk '{print $1}')
                echo -e "${BLUE}   📁 Tamanho: $size${NC}"
            fi
        done
    else
        echo -e "${YELLOW}Nenhum site encontrado${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Gerenciar projetos
manage_projects() {
    while true; do
        clear
        show_header
        echo -e "${WHITE}┌─ GERENCIAMENTO DE PROJETOS ($OS) ───────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}1.${NC} Criar Novo Projeto                                                    ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}2.${NC} Listar Projetos Existentes                                            ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}3.${NC} Criar Projeto Laravel                                                 ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}4.${NC} Criar Projeto WordPress                                               ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}5.${NC} Configurar Permissões                                                 ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}6.${NC} Remover Projeto                                                       ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}0.${NC} Voltar ao Menu Principal                                              ${WHITE}│${NC}"
        echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
        
        case $choice in
            1) create_generic_project ;;
            2) list_projects_universal ;;
            3) create_framework_project "laravel" ;;
            4) create_framework_project "wordpress" ;;
            5) fix_permissions_universal ;;
            6) remove_project_universal ;;
            0) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 2 ;;
        esac
    done
}

# Listar projetos de forma universal
list_projects_universal() {
    echo ""
    echo -e "${CYAN}═══ PROJETOS EXISTENTES ═══${NC}"
    
    if [[ -d "/var/www/html/sites" ]]; then
        for domain_dir in /var/www/html/sites/*/; do
            if [[ -d "$domain_dir" ]]; then
                domain=$(basename "$domain_dir")
                echo -e "${WHITE}📁 Domínio: $domain${NC}"
                
                # Verificar se é um projeto framework específico
                if [[ -f "$domain_dir/artisan" ]]; then
                    echo -e "${PURPLE}  └── Laravel Project${NC}"
                elif [[ -f "$domain_dir/wp-config.php" ]]; then
                    echo -e "${BLUE}  └── WordPress Site${NC}"
                elif [[ -f "$domain_dir/index.php" ]]; then
                    echo -e "${GREEN}  └── PHP Project${NC}"
                else
                    echo -e "${YELLOW}  └── Static Website${NC}"
                fi
                
                # Mostrar arquivos importantes
                file_count=$(find "$domain_dir" -type f | wc -l)
                echo -e "${CYAN}      📄 Arquivos: $file_count${NC}"
                echo ""
            fi
        done
    else
        echo -e "${YELLOW}Nenhum projeto encontrado${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Criar projeto genérico
create_generic_project() {
    echo ""
    read -p "$(echo -e ${CYAN}"Nome do domínio: "${NC})" domain
    
    if [[ -n "$domain" ]]; then
        echo -e "${YELLOW}Criando projeto para $domain...${NC}"
        add_domain_universal "$domain" "domain"
        
        # Criar estrutura básica
        cat > "/var/www/html/sites/$domain/index.php" << 'PHP'
<!DOCTYPE html>
<html>
<head>
    <title>Projeto PHP - <?php echo $_SERVER['HTTP_HOST']; ?></title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 0 auto; padding: 20px; }
        .info { background: #f0f8ff; padding: 15px; border-radius: 5px; margin: 10px 0; }
    </style>
</head>
<body>
    <h1>🎉 Projeto PHP Funcionando!</h1>
    
    <div class="info">
        <h3>Informações do Servidor:</h3>
        <p><strong>Domínio:</strong> <?php echo $_SERVER['HTTP_HOST']; ?></p>
        <p><strong>PHP:</strong> <?php echo PHP_VERSION; ?></p>
        <p><strong>Sistema:</strong> <?php echo php_uname('s') . ' ' . php_uname('r'); ?></p>
        <p><strong>Servidor Web:</strong> <?php echo $_SERVER['SERVER_SOFTWARE']; ?></p>
        <p><strong>Data/Hora:</strong> <?php echo date('Y-m-d H:i:s'); ?></p>
    </div>
    
    <div class="info">
        <h3>Próximos Passos:</h3>
        <ul>
            <li>Editar arquivos em: /var/www/html/sites/<?php echo $_SERVER['HTTP_HOST']; ?></li>
            <li>Ver logs em: /var/log/apache2/ ou /var/log/httpd/</li>
            <li>Configurar SSL com Let's Encrypt</li>
            <li>Configurar banco de dados se necessário</li>
        </ul>
    </div>
</body>
</html>
PHP
        
        chown -R $WEB_USER:$WEB_GROUP "/var/www/html/sites/$domain"
        
        echo -e "${GREEN}Projeto criado com sucesso!${NC}"
        echo "Acesse: http://$domain"
        log_action "Projeto criado: $domain"
    fi
    read -p "Pressione Enter para continuar..."
}

# Criar projeto framework específico
create_framework_project() {
    local framework=$1
    echo ""
    read -p "$(echo -e ${CYAN}"Nome do domínio: "${NC})" domain
    
    if [[ -n "$domain" ]]; then
        echo -e "${YELLOW}Criando projeto $framework para $domain...${NC}"
        
        case $framework in
            "laravel")
                install_laravel_project "$domain"
                ;;
            "wordpress")
                install_wordpress_project "$domain"
                ;;
        esac
    fi
    read -p "Pressione Enter para continuar..."
}

# Instalar Laravel
install_laravel_project() {
    local domain=$1
    
    # Verificar se o Composer está instalado
    if ! command -v composer >/dev/null 2>&1; then
        echo -e "${YELLOW}Instalando Composer...${NC}"
        curl -sS https://getcomposer.org/installer | php
        mv composer.phar /usr/local/bin/composer
        chmod +x /usr/local/bin/composer
    fi
    
    # Criar domínio primeiro
    add_domain_universal "$domain" "domain"
    
    # Instalar Laravel
    cd /var/www/html/sites/
    rm -rf "$domain" # Remove diretório padrão
    composer create-project laravel/laravel "$domain" --prefer-dist
    
    if [[ -d "$domain" ]]; then
        # Configurar permissões Laravel
        chown -R $WEB_USER:$WEB_GROUP "/var/www/html/sites/$domain"
        chmod -R 755 "/var/www/html/sites/$domain"
        chmod -R 775 "/var/www/html/sites/$domain/storage"
        chmod -R 775 "/var/www/html/sites/$domain/bootstrap/cache"
        
        # Atualizar VirtualHost para apontar para public/
        case $OS in
            "oracle"|"rhel")
                sed -i "s|DocumentRoot /var/www/html/sites/$domain|DocumentRoot /var/www/html/sites/$domain/public|g" "/etc/httpd/sites-available/$domain.conf"
                systemctl reload httpd
                ;;
            "ubuntu"|"debian")
                sed -i "s|DocumentRoot /var/www/html/sites/$domain|DocumentRoot /var/www/html/sites/$domain/public|g" "/etc/apache2/sites-available/$domain.conf"
                systemctl reload apache2
                ;;
        esac
        
        echo -e "${GREEN}Laravel instalado com sucesso!${NC}"
        echo "Acesse: http://$domain"
        log_action "Laravel instalado: $domain"
    else
        echo -e "${RED}Erro na instalação do Laravel${NC}"
    fi
}

# Instalar WordPress
install_wordpress_project() {
    local domain=$1
    
    # Criar domínio primeiro
    add_domain_universal "$domain" "domain"
    
    # Download WordPress
    cd /var/www/html/sites/
    rm -rf "$domain" # Remove diretório padrão
    
    echo -e "${YELLOW}Baixando WordPress...${NC}"
    wget -q https://wordpress.org/latest.tar.gz
    
    if [[ -f "latest.tar.gz" ]]; then
        tar -xzf latest.tar.gz
        mv wordpress "$domain"
        rm latest.tar.gz
        
        # Configurar permissões
        chown -R $WEB_USER:$WEB_GROUP "/var/www/html/sites/$domain"
        chmod -R 755 "/var/www/html/sites/$domain"
        
        # Criar banco de dados para WordPress
        echo ""
        echo -e "${CYAN}Configuração do banco de dados para WordPress:${NC}"
        read -p "Nome do banco de dados: " db_name
        read -p "Usuário do banco: " db_user
        read -p "Senha do banco: " db_pass
        
        if [[ -n "$db_name" && -n "$db_user" && -n "$db_pass" ]]; then
            create_wordpress_database "$db_name" "$db_user" "$db_pass"
            
            # Configurar wp-config.php
            if [[ -f "/var/www/html/sites/$domain/wp-config-sample.php" ]]; then
                cp "/var/www/html/sites/$domain/wp-config-sample.php" "/var/www/html/sites/$domain/wp-config.php"
                sed -i "s/database_name_here/$db_name/g" "/var/www/html/sites/$domain/wp-config.php"
                sed -i "s/username_here/$db_user/g" "/var/www/html/sites/$domain/wp-config.php"
                sed -i "s/password_here/$db_pass/g" "/var/www/html/sites/$domain/wp-config.php"
                
                # Gerar salt keys
                SALT=$(curl -s https://api.wordpress.org/secret-key/1.1/salt/)
                sed -i "/#@-/,/#@+/d" "/var/www/html/sites/$domain/wp-config.php"
                echo "$SALT" >> "/var/www/html/sites/$domain/wp-config.php"
            fi
        fi
        
        echo -e "${GREEN}WordPress instalado com sucesso!${NC}"
        echo "Acesse: http://$domain/wp-admin/install.php"
        log_action "WordPress instalado: $domain"
    else
        echo -e "${RED}Erro ao baixar WordPress${NC}"
    fi
}

# Criar banco WordPress
create_wordpress_database() {
    local db_name=$1
    local db_user=$2
    local db_pass=$3
    
    case $OS in
        "oracle"|"rhel")
            mysql -e "CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
            mysql -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';" 2>/dev/null
            mysql -e "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';" 2>/dev/null
            mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
            ;;
        "ubuntu"|"debian")
            mysql -e "CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null
            mysql -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';" 2>/dev/null
            mysql -e "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';" 2>/dev/null
            mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
            ;;
    esac
    
    echo -e "${GREEN}Banco de dados $db_name criado!${NC}"
}

# Remover projeto universal
remove_project_universal() {
    echo ""
    echo -e "${CYAN}Projetos disponíveis:${NC}"
    list_projects_universal
    echo ""
    
    read -p "$(echo -e ${CYAN}"Digite o domínio do projeto para remover: "${NC})" domain
    if [[ -n "$domain" && -d "/var/www/html/sites/$domain" ]]; then
        echo -e "${RED}⚠️  ATENÇÃO: Isso removerá todos os arquivos do projeto!${NC}"
        read -p "$(echo -e ${RED}"Tem certeza? Digite 'REMOVER' para confirmar: "${NC})" confirm
        if [[ "$confirm" == "REMOVER" ]]; then
            rm -rf "/var/www/html/sites/$domain"
            remove_domain_universal_silent "$domain"
            echo -e "${GREEN}Projeto $domain removido completamente!${NC}"
            log_action "Projeto removido completamente: $domain"
        else
            echo -e "${YELLOW}Operação cancelada${NC}"
        fi
    else
        echo -e "${RED}Projeto não encontrado!${NC}"
    fi
    read -p "Pressione Enter para continuar..."
}

# Remover domínio silencioso (para uso interno)
remove_domain_universal_silent() {
    local domain=$1
    case $OS in
        "oracle"|"rhel")
            rm -f "/etc/httpd/sites-enabled/$domain.conf"
            rm -f "/etc/httpd/sites-available/$domain.conf"
            systemctl reload httpd
            ;;
        "ubuntu"|"debian")
            a2dissite "$domain" 2>/dev/null
            rm -f "/etc/apache2/sites-available/$domain.conf"
            systemctl reload apache2
            ;;
    esac
    rm -rf "/var/log/httpd/domains/$domain" 2>/dev/null
    rm -rf "/var/log/apache2/domains/$domain" 2>/dev/null
}

# Corrigir permissões universal
fix_permissions_universal() {
    echo ""
    echo -e "${YELLOW}Corrigindo permissões dos sites...${NC}"
    
    # Corrigir permissões dos sites
    chown -R $WEB_USER:$WEB_GROUP /var/www/html/
    find /var/www/html/ -type d -exec chmod 755 {} \;
    find /var/www/html/ -type f -exec chmod 644 {} \;
    
    # Permissões especiais para Laravel
    find /var/www/html/ -name "storage" -type d -exec chmod -R 775 {} \; 2>/dev/null
    find /var/www/html/ -path "*/bootstrap/cache" -type d -exec chmod -R 775 {} \; 2>/dev/null
    
    # Permissões para WordPress
    find /var/www/html/ -name "wp-content" -type d -exec chmod -R 775 {} \; 2>/dev/null
    find /var/www/html/ -name "wp-config.php" -type f -exec chmod 644 {} \; 2>/dev/null
    
    echo -e "${GREEN}Permissões corrigidas para $WEB_USER:$WEB_GROUP!${NC}"
    log_action "Permissões corrigidas"
    read -p "Pressione Enter para continuar..."
}

# Gerenciar PHP adaptado
manage_php() {
    while true; do
        clear
        show_header
        echo -e "${WHITE}┌─ GERENCIAMENTO DO PHP ($OS) ────────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}1.${NC} Verificar Versão Atual                                                ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}2.${NC} Listar Extensões Instaladas                                           ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}3.${NC} Instalar Extensão PHP                                                 ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}4.${NC} Configurar php.ini                                                    ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}5.${NC} Reiniciar PHP-FPM                                                     ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}6.${NC} Status PHP-FPM                                                        ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}7.${NC} Ver PHPInfo                                                           ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}8.${NC} Otimizar Configuração PHP                                             ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}0.${NC} Voltar ao Menu Principal                                              ${WHITE}│${NC}"
        echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
        
        case $choice in
            1) show_php_info ;;
            2) show_php_extensions ;;
            3) install_php_extension_universal ;;
            4) edit_php_ini_universal ;;
            5) restart_php_service ;;
            6) show_php_status ;;
            7) create_phpinfo_universal ;;
            8) optimize_php_config ;;
            0) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 2 ;;
        esac
    done
}

# Mostrar informações do PHP
show_php_info() {
    echo ""
    echo -e "${CYAN}═══ INFORMAÇÕES DO PHP ═══${NC}"
    
    if command -v php >/dev/null 2>&1; then
        php -v
        echo ""
        echo -e "${BLUE}Configurações importantes:${NC}"
        php -r 'echo "Memory Limit: " . ini_get("memory_limit") . "\n";' 2>/dev/null
        php -r 'echo "Upload Max: " . ini_get("upload_max_filesize") . "\n";' 2>/dev/null
        php -r 'echo "Post Max: " . ini_get("post_max_size") . "\n";' 2>/dev/null
        php -r 'echo "Max Execution: " . ini_get("max_execution_time") . "s\n";' 2>/dev/null
        php -r 'echo "Max Input Vars: " . ini_get("max_input_vars") . "\n";' 2>/dev/null
        echo ""
        echo -e "${YELLOW}Caminho do php.ini: $(php --ini | grep "Loaded Configuration File" | cut -d: -f2)${NC}"
        
        # Mostrar módulos críticos
        echo ""
        echo -e "${BLUE}Módulos críticos:${NC}"
        critical_modules=("mysqli" "pdo_mysql" "gd" "curl" "mbstring" "xml" "zip" "opcache")
        for module in "${critical_modules[@]}"; do
            if php -m | grep -qi "^$module$"; then
                echo -e "${GREEN}✅ $module${NC}"
            else
                echo -e "${RED}❌ $module (não instalado)${NC}"
            fi
        done
    else
        echo -e "${RED}PHP não encontrado no sistema!${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Mostrar extensões PHP
show_php_extensions() {
    echo ""
    echo -e "${CYAN}═══ EXTENSÕES PHP INSTALADAS ═══${NC}"
    if command -v php >/dev/null 2>&1; then
        echo ""
        echo -e "${WHITE}Extensões carregadas:${NC}"
        php -m | sort | column -c 80
        echo ""
        echo -e "${BLUE}Total de extensões: $(php -m | wc -l)${NC}"
    else
        echo "PHP não encontrado"
    fi
    read -p "Pressione Enter para continuar..."
}

# Instalar extensão PHP universal
install_php_extension_universal() {
    echo ""
    echo -e "${CYAN}Extensões PHP comuns:${NC}"
    echo "1. imagick - Manipulação de imagens"
    echo "2. redis - Cache Redis"
    echo "3. memcached - Cache Memcached"
    echo "4. xdebug - Debug e profiling"
    echo "5. mongodb - Database MongoDB"
    echo "6. gd - Biblioteca de imagens"
    echo "7. intl - Internacionalização"
    echo "8. soap - Web services SOAP"
    echo "9. imap - Email IMAP"
    echo "10. Outra extensão"
    echo ""
    
    read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
    
    case $choice in
        1) ext="imagick" ;;
        2) ext="redis" ;;
        3) ext="memcached" ;;
        4) ext="xdebug" ;;
        5) ext="mongodb" ;;
        6) ext="gd" ;;
        7) ext="intl" ;;
        8) ext="soap" ;;
        9) ext="imap" ;;
        10) 
            read -p "$(echo -e ${CYAN}"Nome da extensão (sem php-): "${NC})" ext
            ;;
        *)
            echo -e "${RED}Opção inválida!${NC}"
            return
            ;;
    esac
    
    if [[ -n "$ext" ]]; then
        echo -e "${YELLOW}Instalando php-$ext...${NC}"
        
        case $PKG_MANAGER in
            "apt")
                install_package "php-$ext"
                ;;
            "dnf"|"yum")
                install_package "php-$ext"
                ;;
        esac
        
        restart_php_service
        echo -e "${GREEN}Extensão php-$ext instalada!${NC}"
        log_action "Extensão PHP instalada: $ext"
    fi
    read -p "Pressione Enter para continuar..."
}

# Editar php.ini universal
edit_php_ini_universal() {
    echo ""
    
    # Encontrar arquivo php.ini
    local ini_file
    case $OS in
        "oracle"|"rhel")
            ini_file="/etc/php.ini"
            ;;
        "ubuntu"|"debian")
            ini_file="/etc/php/$(php -v | head -1 | grep -oP '\d\.\d')/apache2/php.ini"
            if [[ ! -f "$ini_file" ]]; then
                ini_file="/etc/php/8.1/apache2/php.ini"
            fi
            ;;
        *)
            ini_file=$(php --ini | grep "Loaded Configuration File" | cut -d: -f2 | tr -d ' ')
            ;;
    esac
    
    if [[ -f "$ini_file" ]]; then
        echo -e "${YELLOW}Editando $ini_file${NC}"
        echo "Pressione Ctrl+X para salvar e sair do nano"
        sleep 2
        nano "$ini_file"
        
        read -p "$(echo -e ${CYAN}"Reiniciar serviços para aplicar mudanças? (S/n): "${NC})" restart
        if [[ "$restart" != "n" && "$restart" != "N" ]]; then
            restart_php_service
            systemctl restart $WEB_SERVICE
            echo -e "${GREEN}Serviços reiniciados!${NC}"
        fi
    else
        echo -e "${RED}Arquivo php.ini não encontrado: $ini_file${NC}"
    fi
    read -p "Pressione Enter para continuar..."
}

# Reiniciar PHP service universal
restart_php_service() {
    echo -e "${YELLOW}Reiniciando PHP-FPM...${NC}"
    
    # Tentar diferentes nomes de serviço
    php_services=("$PHP_SERVICE" "php-fpm" "php8.1-fpm" "php7.4-fpm")
    
    for service in "${php_services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            systemctl restart "$service"
            if systemctl is-active "$service" >/dev/null 2>&1; then
                echo -e "${GREEN}$service reiniciado com sucesso!${NC}"
                return 0
            fi
        fi
    done
    
    # Se não encontrou PHP-FPM, reiniciar Apache (mod_php)
    systemctl restart $WEB_SERVICE
    echo -e "${GREEN}$WEB_SERVICE reiniciado (usando mod_php)!${NC}"
}

# Status do PHP
# Continuação - Status do PHP e demais funcionalidades

show_php_status() {
    echo ""
    echo -e "${CYAN}═══ STATUS PHP-FPM ═══${NC}"
    
    php_services=("$PHP_SERVICE" "php-fpm" "php8.1-fpm")
    
    for service in "${php_services[@]}"; do
        if systemctl is-enabled "$service" >/dev/null 2>&1; then
            echo -e "${BLUE}Serviço: $service${NC}"
            systemctl status "$service" --no-pager -l
            return 0
        fi
    done
    
    echo -e "${YELLOW}PHP-FPM não encontrado, verificando mod_php...${NC}"
    if command -v php >/dev/null 2>&1; then
        echo -e "${GREEN}PHP está funcionando via mod_php${NC}"
        php -v
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Criar PHPInfo universal
create_phpinfo_universal() {
    local phpinfo_file="/var/www/html/phpinfo.php"
    
    cat > "$phpinfo_file" << 'PHPINFO'
<?php
// Remover este arquivo após uso por segurança
if (!isset($_GET['confirm']) || $_GET['confirm'] !== 'yes') {
    echo '<h1>PHPInfo - Confirmação Necessária</h1>';
    echo '<p>Por motivos de segurança, confirme o acesso:</p>';
    echo '<p><a href="' . $_SERVER['REQUEST_URI'] . '?confirm=yes" style="background:#007cba;color:white;padding:10px;text-decoration:none;border-radius:5px;">Acessar PHPInfo</a></p>';
    exit;
}

echo '<style>body{font-family:Arial,sans-serif;}</style>';
echo '<div style="background:#f0f0f0;padding:20px;margin:20px;border-radius:5px;">';
echo '<h2>Sistema: ' . php_uname() . '</h2>';
echo '<p><strong>Data:</strong> ' . date('Y-m-d H:i:s') . '</p>';
echo '<p style="color:red;"><strong>⚠️ REMOVA ESTE ARQUIVO APÓS O USO!</strong></p>';
echo '</div>';

phpinfo();
?>
PHPINFO
    
    chown $WEB_USER:$WEB_GROUP "$phpinfo_file"
    chmod 644 "$phpinfo_file"
    
    local ip=$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
    echo -e "${GREEN}PHPInfo criado em: http://$ip/phpinfo.php?confirm=yes${NC}"
    echo -e "${RED}⚠️  ATENÇÃO: Remova este arquivo após uso por segurança!${NC}"
    echo "Comando para remover: rm $phpinfo_file"
    read -p "Pressione Enter para continuar..."
}

# Otimizar configuração PHP
optimize_php_config() {
    echo ""
    echo -e "${YELLOW}Otimizando configuração PHP...${NC}"
    
    # Encontrar php.ini
    local ini_file
    case $OS in
        "oracle"|"rhel")
            ini_file="/etc/php.ini"
            ;;
        "ubuntu"|"debian")
            ini_file="/etc/php/$(php -v | head -1 | grep -oP '\d\.\d')/apache2/php.ini"
            ;;
    esac
    
    if [[ -f "$ini_file" ]]; then
        # Backup do arquivo original
        cp "$ini_file" "$ini_file.backup.$(date +%Y%m%d)"
        
        # Otimizações recomendadas
        sed -i 's/^memory_limit = .*/memory_limit = 256M/' "$ini_file"
        sed -i 's/^upload_max_filesize = .*/upload_max_filesize = 64M/' "$ini_file"
        sed -i 's/^post_max_size = .*/post_max_size = 64M/' "$ini_file"
        sed -i 's/^max_execution_time = .*/max_execution_time = 300/' "$ini_file"
        sed -i 's/^max_input_vars = .*/max_input_vars = 3000/' "$ini_file"
        
        # Ativar OPcache se disponível
        if php -m | grep -q opcache; then
            sed -i 's/^;opcache.enable=.*/opcache.enable=1/' "$ini_file"
            sed -i 's/^;opcache.memory_consumption=.*/opcache.memory_consumption=128/' "$ini_file"
            sed -i 's/^;opcache.max_accelerated_files=.*/opcache.max_accelerated_files=4000/' "$ini_file"
        fi
        
        restart_php_service
        systemctl restart $WEB_SERVICE
        
        echo -e "${GREEN}PHP otimizado com sucesso!${NC}"
        echo "Backup salvo em: $ini_file.backup.$(date +%Y%m%d)"
        log_action "Configuração PHP otimizada"
    else
        echo -e "${RED}Arquivo php.ini não encontrado${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Gerenciar MySQL/MariaDB
manage_mysql() {
    while true; do
        clear
        show_header
        echo -e "${WHITE}┌─ GERENCIAMENTO DO MYSQL/MARIADB ($OS) ───────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}1.${NC} Status do Banco de Dados                                              ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}2.${NC} Listar Bancos de Dados                                                ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}3.${NC} Criar Novo Banco                                                      ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}4.${NC} Criar Usuário                                                         ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}5.${NC} Backup de Banco                                                       ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}6.${NC} Restaurar Backup                                                      ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}7.${NC} Otimizar Bancos                                                       ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}8.${NC} Console MySQL                                                         ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}9.${NC} Configurar Senha Root                                                 ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}0.${NC} Voltar ao Menu Principal                                              ${WHITE}│${NC}"
        echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
        
        case $choice in
            1) show_mysql_status ;;
            2) list_databases_universal ;;
            3) create_database_universal ;;
            4) create_mysql_user_universal ;;
            5) backup_database_universal ;;
            6) restore_database_universal ;;
            7) optimize_databases_universal ;;
            8) mysql_console ;;
            9) configure_mysql_root ;;
            0) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 2 ;;
        esac
    done
}

# Status do MySQL/MariaDB
show_mysql_status() {
    echo ""
    echo -e "${CYAN}═══ STATUS DO BANCO DE DADOS ═══${NC}"
    systemctl status $MYSQL_SERVICE --no-pager
    echo ""
    
    if systemctl is-active $MYSQL_SERVICE >/dev/null 2>&1; then
        echo -e "${GREEN}Serviço ativo${NC}"
        
        # Tentar mostrar versão
        if command -v mysql >/dev/null 2>&1; then
            mysql -e "SELECT VERSION() AS 'Versão', NOW() AS 'Data/Hora';" 2>/dev/null || echo "Erro ao conectar no banco"
        fi
    else
        echo -e "${RED}Serviço inativo${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Listar bancos universal
list_databases_universal() {
    echo ""
    echo -e "${CYAN}═══ BANCOS DE DADOS ═══${NC}"
    
    if systemctl is-active $MYSQL_SERVICE >/dev/null 2>&1; then
        mysql -e "SHOW DATABASES;" 2>/dev/null || echo "Erro ao conectar. Verifique credenciais."
        echo ""
        
        # Mostrar tamanho dos bancos
        echo -e "${BLUE}Tamanho dos bancos de dados:${NC}"
        mysql -e "SELECT table_schema AS 'Database', 
                  ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS 'Size (MB)'
                  FROM information_schema.tables 
                  GROUP BY table_schema;" 2>/dev/null
    else
        echo -e "${RED}Serviço de banco não está ativo${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Criar banco universal
create_database_universal() {
    echo ""
    read -p "$(echo -e ${CYAN}"Nome do novo banco: "${NC})" db_name
    
    if [[ -n "$db_name" ]]; then
        read -p "$(echo -e ${CYAN}"Nome do usuário (opcional): "${NC})" db_user
        if [[ -n "$db_user" ]]; then
            read -p "$(echo -e ${CYAN}"Senha do usuário: "${NC})" db_pass
        fi
        
        # Criar banco
        if mysql -e "CREATE DATABASE \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null; then
            echo -e "${GREEN}Banco $db_name criado com sucesso!${NC}"
            
            # Criar usuário se fornecido
            if [[ -n "$db_user" && -n "$db_pass" ]]; then
                mysql -e "CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';" 2>/dev/null
                mysql -e "GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';" 2>/dev/null
                mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
                echo -e "${GREEN}Usuário $db_user criado e vinculado ao banco!${NC}"
            fi
            
            log_action "Banco criado: $db_name"
        else
            echo -e "${RED}Erro ao criar banco de dados${NC}"
        fi
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Criar usuário MySQL universal
create_mysql_user_universal() {
    echo ""
    read -p "$(echo -e ${CYAN}"Nome do usuário: "${NC})" username
    read -p "$(echo -e ${CYAN}"Senha do usuário: "${NC})" password
    echo ""
    echo "Nível de permissões:"
    echo "1. Acesso total (ALL PRIVILEGES)"
    echo "2. Somente leitura (SELECT)"
    echo "3. Leitura e escrita (SELECT, INSERT, UPDATE, DELETE)"
    echo "4. Específico para um banco"
    echo ""
    read -p "$(echo -e ${YELLOW}"Escolha o nível: "${NC})" perm_level
    
    case $perm_level in
        1) privileges="ALL PRIVILEGES"; database="*" ;;
        2) privileges="SELECT"; database="*" ;;
        3) privileges="SELECT, INSERT, UPDATE, DELETE"; database="*" ;;
        4) 
            read -p "$(echo -e ${CYAN}"Nome do banco: "${NC})" database
            privileges="ALL PRIVILEGES"
            ;;
        *) 
            echo -e "${RED}Opção inválida!${NC}"
            return
            ;;
    esac
    
    if [[ "$database" == "*" ]]; then
        db_grant="*.*"
    else
        db_grant="\`$database\`.*"
    fi
    
    if mysql -e "CREATE USER '$username'@'localhost' IDENTIFIED BY '$password';" 2>/dev/null; then
        mysql -e "GRANT $privileges ON $db_grant TO '$username'@'localhost';" 2>/dev/null
        mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
        echo -e "${GREEN}Usuário $username criado com sucesso!${NC}"
        log_action "Usuário MySQL criado: $username"
    else
        echo -e "${RED}Erro ao criar usuário${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Backup de banco universal
backup_database_universal() {
    echo ""
    echo -e "${CYAN}Bancos disponíveis:${NC}"
    mysql -e "SHOW DATABASES;" 2>/dev/null | grep -v "Database\|information_schema\|performance_schema\|mysql\|sys" | nl
    echo ""
    
    read -p "$(echo -e ${CYAN}"Nome do banco para backup: "${NC})" db_name
    
    if [[ -n "$db_name" ]]; then
        backup_dir="/var/backups/databases"
        mkdir -p "$backup_dir"
        backup_file="$backup_dir/${db_name}_$(date +%Y%m%d_%H%M%S).sql"
        
        if mysqldump "$db_name" > "$backup_file" 2>/dev/null; then
            # Comprimir backup
            gzip "$backup_file"
            backup_file="$backup_file.gz"
            
            echo -e "${GREEN}Backup criado: $backup_file${NC}"
            echo -e "${BLUE}Tamanho: $(du -sh "$backup_file" | awk '{print $1}')${NC}"
            log_action "Backup do banco $db_name criado"
        else
            echo -e "${RED}Erro ao criar backup!${NC}"
        fi
    fi
    read -p "Pressione Enter para continuar..."
}

# Restaurar backup de banco
restore_database_universal() {
    echo ""
    echo -e "${CYAN}Backups disponíveis:${NC}"
    if [[ -d "/var/backups/databases" ]]; then
        ls -lah /var/backups/databases/*.sql* 2>/dev/null | nl || echo "Nenhum backup encontrado"
    fi
    echo ""
    
    read -p "$(echo -e ${CYAN}"Caminho completo do backup: "${NC})" backup_file
    read -p "$(echo -e ${CYAN}"Nome do banco de destino: "${NC})" db_name
    
    if [[ -f "$backup_file" && -n "$db_name" ]]; then
        echo -e "${RED}⚠️  Isso sobrescreverá o banco $db_name completamente!${NC}"
        read -p "$(echo -e ${RED}"Continuar? (s/N): "${NC})" confirm
        if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
            # Verificar se é arquivo comprimido
            if [[ "$backup_file" == *.gz ]]; then
                gunzip -c "$backup_file" | mysql "$db_name"
            else
                mysql "$db_name" < "$backup_file"
            fi
            
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}Banco $db_name restaurado com sucesso!${NC}"
                log_action "Banco $db_name restaurado de $backup_file"
            else
                echo -e "${RED}Erro na restauração${NC}"
            fi
        fi
    else
        echo -e "${RED}Arquivo não encontrado ou nome do banco inválido${NC}"
    fi
    read -p "Pressione Enter para continuar..."
}

# Otimizar bancos universal
optimize_databases_universal() {
    echo ""
    echo -e "${YELLOW}Otimizando bancos de dados...${NC}"
    
    # Obter lista de bancos (excluindo sistema)
    databases=$(mysql -e "SHOW DATABASES;" 2>/dev/null | grep -v "Database\|information_schema\|performance_schema\|mysql\|sys")
    
    for db in $databases; do
        echo -e "${BLUE}Otimizando banco: $db${NC}"
        
        # Obter tabelas do banco
        tables=$(mysql -e "USE $db; SHOW TABLES;" 2>/dev/null | grep -v "Tables_in")
        
        for table in $tables; do
            mysql -e "USE $db; OPTIMIZE TABLE $table;" 2>/dev/null >/dev/null
        done
        
        mysql -e "USE $db; ANALYZE TABLE $(echo $tables | tr ' ' ',');" 2>/dev/null >/dev/null
        echo -e "${GREEN}✅ $db otimizado${NC}"
    done
    
    echo -e "${GREEN}Otimização concluída!${NC}"
    log_action "Bancos de dados otimizados"
    read -p "Pressione Enter para continuar..."
}

# Console MySQL
mysql_console() {
    echo ""
    echo -e "${YELLOW}Abrindo console MySQL...${NC}"
    echo "Digite 'exit' para sair do console"
    echo ""
    sleep 2
    mysql
}

# Configurar senha root MySQL
configure_mysql_root() {
    echo ""
    echo -e "${CYAN}═══ CONFIGURAR SENHA ROOT MYSQL ═══${NC}"
    echo ""
    read -p "$(echo -e ${CYAN}"Nova senha para root: "${NC})" new_password
    
    if [[ -n "$new_password" ]]; then
        case $OS in
            "oracle"|"rhel")
                # MariaDB
                mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$new_password';" 2>/dev/null
                ;;
            "ubuntu"|"debian")
                # MySQL
                mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$new_password';" 2>/dev/null
                ;;
        esac
        
        if [[ $? -eq 0 ]]; then
            echo -e "${GREEN}Senha root configurada com sucesso!${NC}"
            echo -e "${YELLOW}⚠️  Anote esta senha em local seguro${NC}"
            log_action "Senha root MySQL configurada"
        else
            echo -e "${RED}Erro ao configurar senha${NC}"
        fi
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Gerenciar serviços
manage_services() {
    while true; do
        clear
        show_header
        echo -e "${WHITE}┌─ APACHE & SERVIÇOS ($OS) ────────────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}1.${NC} Status de Todos os Serviços                                           ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}2.${NC} Reiniciar Apache                                                      ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}3.${NC} Reiniciar Todos os Serviços                                           ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}4.${NC} Testar Configuração Apache                                            ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}5.${NC} Habilitar/Desabilitar Módulos                                         ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}6.${NC} Gerenciar Firewall                                                    ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}7.${NC} Ver Logs em Tempo Real                                                ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}8.${NC} Configurações de Rede                                                 ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}0.${NC} Voltar ao Menu Principal                                              ${WHITE}│${NC}"
        echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
        
        case $choice in
            1) show_all_services_status ;;
            2) restart_apache ;;
            3) restart_all_services ;;
            4) test_apache_config ;;
            5) manage_apache_modules ;;
            6) manage_firewall ;;
            7) view_logs_realtime ;;
            8) network_configuration ;;
            0) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 2 ;;
        esac
    done
}

# Status de todos os serviços
show_all_services_status() {
    echo ""
    echo -e "${CYAN}═══ STATUS DE TODOS OS SERVIÇOS ═══${NC}"
    echo ""
    
    case $OS in
        "oracle"|"rhel")
            services=("httpd" "mariadb" "php-fpm" "redis" "memcached" "firewalld" "sshd")
            ;;
        "ubuntu"|"debian")
            services=("apache2" "mysql" "php8.1-fpm" "redis-server" "memcached" "ufw" "ssh")
            ;;
    esac
    
    for service in "${services[@]}"; do
        if systemctl is-active "$service" >/dev/null 2>&1; then
            uptime=$(systemctl show "$service" --property=ActiveEnterTimestamp --value 2>/dev/null)
            printf "%-15s ${GREEN}ATIVO${NC}   %s\n" "$service:" "$uptime"
        else
            printf "%-15s ${RED}INATIVO${NC}\n" "$service:"
        fi
    done
    
    echo ""
    echo -e "${BLUE}Portas em uso:${NC}"
    netstat -tlnp 2>/dev/null | grep -E ':80|:443|:22|:3306|:6379|:11211' | head -10
    
    echo ""
    echo -e "${BLUE}Uso de recursos:${NC}"
    echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
    echo "Memória: $(free -h | grep Mem | awk '{printf "%s/%s (%.1f%%)", $3, $2, ($3/$2)*100}')"
    echo "Disco: $(df -h / | tail -1 | awk '{print $3 "/" $2 " (" $5 ")"}')"
    
    read -p "Pressione Enter para continuar..."
}

# Reiniciar Apache
restart_apache() {
    echo ""
    echo -e "${YELLOW}Reiniciando $WEB_SERVICE...${NC}"
    
    systemctl restart $WEB_SERVICE
    
    if systemctl is-active $WEB_SERVICE >/dev/null 2>&1; then
        echo -e "${GREEN}$WEB_SERVICE reiniciado com sucesso!${NC}"
    else
        echo -e "${RED}Erro ao reiniciar $WEB_SERVICE${NC}"
        systemctl status $WEB_SERVICE --no-pager
    fi
    
    log_action "$WEB_SERVICE reiniciado"
    read -p "Pressione Enter para continuar..."
}

# Reiniciar todos os serviços
restart_all_services() {
    echo ""
    echo -e "${YELLOW}Reiniciando todos os serviços...${NC}"
    echo ""
    
    case $OS in
        "oracle"|"rhel")
            services=("mariadb" "php-fpm" "httpd" "redis" "memcached")
            ;;
        "ubuntu"|"debian")
            services=("mysql" "php8.1-fpm" "apache2" "redis-server" "memcached")
            ;;
    esac
    
    for service in "${services[@]}"; do
        echo -e "Reiniciando $service..."
        systemctl restart "$service" 2>/dev/null
        
        if systemctl is-active "$service" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ $service${NC}"
        else
            echo -e "${RED}❌ $service (erro ou não instalado)${NC}"
        fi
    done
    
    echo ""
    log_action "Todos os serviços reiniciados"
    read -p "Pressione Enter para continuar..."
}

# Testar configuração Apache
test_apache_config() {
    echo ""
    echo -e "${CYAN}═══ TESTE DE CONFIGURAÇÃO APACHE ═══${NC}"
    echo ""
    
    case $OS in
        "oracle"|"rhel")
            httpd -t
            ;;
        "ubuntu"|"debian")
            apache2ctl configtest
            ;;
    esac
    
    echo ""
    echo -e "${BLUE}Sites habilitados:${NC}"
    case $OS in
        "oracle"|"rhel")
            ls -la /etc/httpd/sites-enabled/ 2>/dev/null || echo "Nenhum site habilitado"
            ;;
        "ubuntu"|"debian")
            apache2ctl -S 2>/dev/null
            ;;
    esac
    
    read -p "Pressione Enter para continuar..."
}

# Gerenciar módulos Apache
manage_apache_modules() {
    while true; do
        echo ""
        echo -e "${CYAN}═══ MÓDULOS APACHE ═══${NC}"
        echo ""
        echo "1. Listar módulos habilitados"
        echo "2. Habilitar módulo"
        echo "3. Desabilitar módulo"
        echo "4. Listar módulos disponíveis"
        echo "0. Voltar"
        echo ""
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
        
        case $choice in
            1)
                echo ""
                echo -e "${CYAN}═══ MÓDULOS HABILITADOS ═══${NC}"
                case $OS in
                    "oracle"|"rhel")
                        httpd -M 2>/dev/null | sort
                        ;;
                    "ubuntu"|"debian")
                        apache2ctl -M | sort
                        ;;
                esac
                ;;
            2)
                echo ""
                read -p "$(echo -e ${CYAN}"Nome do módulo para habilitar: "${NC})" module
                if [[ -n "$module" ]]; then
                    case $OS in
                        "oracle"|"rhel")
                            # No RHEL/Oracle, módulos são habilitados editando configuração
                            echo "LoadModule ${module}_module modules/mod_${module}.so" >> /etc/httpd/conf/httpd.conf
                            ;;
                        "ubuntu"|"debian")
                            a2enmod "$module"
                            ;;
                    esac
                    systemctl restart $WEB_SERVICE
                    echo -e "${GREEN}Módulo $module habilitado!${NC}"
                    log_action "Módulo Apache habilitado: $module"
                fi
                ;;
            3)
                echo ""
                read -p "$(echo -e ${CYAN}"Nome do módulo para desabilitar: "${NC})" module
                if [[ -n "$module" ]]; then
                    case $OS in
                        "ubuntu"|"debian")
                            a2dismod "$module"
                            systemctl restart $WEB_SERVICE
                            echo -e "${GREEN}Módulo $module desabilitado!${NC}"
                            log_action "Módulo Apache desabilitado: $module"
                            ;;
                        *)
                            echo -e "${YELLOW}Funcionalidade não implementada para $OS${NC}"
                            ;;
                    esac
                fi
                ;;
            4)
                echo ""
                echo -e "${CYAN}═══ MÓDULOS DISPONÍVEIS ═══${NC}"
                case $OS in
                    "ubuntu"|"debian")
                        ls /etc/apache2/mods-available/ | grep -E '\.load$' | sed 's/.load$//' | sort
                        ;;
                    "oracle"|"rhel")
                        ls /usr/lib64/httpd/modules/mod_*.so 2>/dev/null | sed 's|.*mod_||; s|\.so||' | sort
                        ;;
                esac
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}Opção inválida!${NC}"
                sleep 1
                ;;
        esac
        
        if [[ "$choice" != "0" ]]; then
            read -p "Pressione Enter para continuar..."
        fi
    done
}

# Gerenciar firewall
manage_firewall() {
    while true; do
        echo ""
        echo -e "${CYAN}═══ GERENCIAMENTO FIREWALL ($FIREWALL_SERVICE) ═══${NC}"
        echo ""
        echo "1. Status do Firewall"
        echo "2. Listar regras"
        echo "3. Adicionar regra"
        echo "4. Remover regra"
        echo "5. Habilitar Firewall"
        echo "6. Desabilitar Firewall"
        echo "7. Reset Firewall"
        echo "0. Voltar"
        echo ""
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
        
        case $choice in
            1)
                echo ""
                case $FIREWALL_SERVICE in
                    "firewalld")
                        firewall-cmd --state 2>/dev/null && firewall-cmd --list-all
                        ;;
                    "ufw")
                        ufw status verbose
                        ;;
                esac
                ;;
            2)
                echo ""
                case $FIREWALL_SERVICE in
                    "firewalld")
                        firewall-cmd --list-all
                        ;;
                    "ufw")
                        ufw status numbered
                        ;;
                esac
                ;;
            # Continuação - Gerenciar firewall e demais funcionalidades

            3)
                echo ""
                echo "Exemplos de regras:"
                case $FIREWALL_SERVICE in
                    "firewalld")
                        echo "  firewall-cmd --add-port=8080/tcp"
                        echo "  firewall-cmd --add-service=ftp"
                        echo ""
                        read -p "$(echo -e ${CYAN}"Digite a regra firewalld: "${NC})" rule
                        if [[ -n "$rule" ]]; then
                            firewall-cmd --permanent --$rule
                            firewall-cmd --reload
                            echo -e "${GREEN}Regra adicionada!${NC}"
                            log_action "Regra firewalld adicionada: $rule"
                        fi
                        ;;
                    "ufw")
                        echo "  ufw allow 8080"
                        echo "  ufw allow from 192.168.1.0/24"
                        echo "  ufw deny 21"
                        echo ""
                        read -p "$(echo -e ${CYAN}"Digite a regra UFW: "${NC})" rule
                        if [[ -n "$rule" ]]; then
                            ufw $rule
                            log_action "Regra UFW adicionada: $rule"
                        fi
                        ;;
                esac
                ;;
            4)
                echo ""
                case $FIREWALL_SERVICE in
                    "firewalld")
                        firewall-cmd --list-all
                        echo ""
                        read -p "$(echo -e ${CYAN}"Regra para remover: "${NC})" rule
                        if [[ -n "$rule" ]]; then
                            firewall-cmd --permanent --remove-$rule
                            firewall-cmd --reload
                        fi
                        ;;
                    "ufw")
                        ufw status numbered
                        echo ""
                        read -p "$(echo -e ${CYAN}"Número da regra para remover: "${NC})" rule_num
                        if [[ -n "$rule_num" ]]; then
                            ufw delete "$rule_num"
                        fi
                        ;;
                esac
                ;;
            5)
                case $FIREWALL_SERVICE in
                    "firewalld")
                        systemctl enable firewalld
                        systemctl start firewalld
                        echo -e "${GREEN}FirewallD habilitado!${NC}"
                        ;;
                    "ufw")
                        ufw --force enable
                        echo -e "${GREEN}UFW habilitado!${NC}"
                        ;;
                esac
                ;;
            6)
                case $FIREWALL_SERVICE in
                    "firewalld")
                        systemctl stop firewalld
                        echo -e "${YELLOW}FirewallD desabilitado!${NC}"
                        ;;
                    "ufw")
                        ufw disable
                        echo -e "${YELLOW}UFW desabilitado!${NC}"
                        ;;
                esac
                ;;
            7)
                read -p "$(echo -e ${RED}"Tem certeza que deseja resetar o firewall? (s/N): "${NC})" confirm
                if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
                    case $FIREWALL_SERVICE in
                        "firewalld")
                            firewall-cmd --complete-reload
                            echo -e "${GREEN}FirewallD resetado!${NC}"
                            ;;
                        "ufw")
                            ufw --force reset
                            echo -e "${GREEN}UFW resetado!${NC}"
                            ;;
                    esac
                fi
                ;;
            0)
                break
                ;;
            *)
                echo -e "${RED}Opção inválida!${NC}"
                sleep 1
                ;;
        esac
        
        if [[ "$choice" != "0" ]]; then
            read -p "Pressione Enter para continuar..."
        fi
    done
}

# Ver logs em tempo real
view_logs_realtime() {
    echo ""
    echo -e "${CYAN}Logs disponíveis:${NC}"
    echo "1. Apache Access Log"
    echo "2. Apache Error Log"
    echo "3. PHP Error Log"
    echo "4. MySQL/MariaDB Log"
    echo "5. Sistema (journalctl)"
    echo ""
    
    read -p "$(echo -e ${YELLOW}"Escolha um log: "${NC})" choice
    
    case $choice in
        1)
            case $OS in
                "oracle"|"rhel") tail -f /var/log/httpd/access_log ;;
                "ubuntu"|"debian") tail -f /var/log/apache2/access.log ;;
            esac
            ;;
        2)
            case $OS in
                "oracle"|"rhel") tail -f /var/log/httpd/error_log ;;
                "ubuntu"|"debian") tail -f /var/log/apache2/error.log ;;
            esac
            ;;
        3)
            case $OS in
                "oracle"|"rhel") tail -f /var/log/php_errors.log 2>/dev/null || echo "Log PHP não encontrado" ;;
                "ubuntu"|"debian") tail -f /var/log/php8.1-fpm.log 2>/dev/null || echo "Log PHP não encontrado" ;;
            esac
            ;;
        4)
            case $OS in
                "oracle"|"rhel") tail -f /var/log/mariadb/mariadb.log 2>/dev/null || journalctl -f -u mariadb ;;
                "ubuntu"|"debian") tail -f /var/log/mysql/error.log 2>/dev/null || journalctl -f -u mysql ;;
            esac
            ;;
        5)
            journalctl -f
            ;;
        *)
            echo -e "${RED}Opção inválida!${NC}"
            return
            ;;
    esac
}

# Configuração de rede
network_configuration() {
    echo ""
    echo -e "${CYAN}═══ CONFIGURAÇÃO DE REDE ═══${NC}"
    echo ""
    echo -e "${BLUE}Interface de rede:${NC}"
    ip addr show | grep -E "^[0-9]|inet " | head -10
    echo ""
    echo -e "${BLUE}Roteamento:${NC}"
    ip route show
    echo ""
    echo -e "${BLUE}DNS:${NC}"
    cat /etc/resolv.conf 2>/dev/null | grep nameserver
    echo ""
    
    read -p "Pressione Enter para continuar..."
}

# Gerenciar backup
manage_backup() {
    while true; do
        clear
        show_header
        echo -e "${WHITE}┌─ BACKUP & RESTORE ($OS) ─────────────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}1.${NC} Fazer Backup Completo                                                 ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}2.${NC} Backup Apenas Sites                                                   ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}3.${NC} Backup Apenas Bancos                                                  ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}4.${NC} Listar Backups                                                        ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}5.${NC} Restaurar Backup                                                      ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}6.${NC} Configurar Backup Automático                                          ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}7.${NC} Limpar Backups Antigos                                                ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}8.${NC} Sincronizar com Servidor Remoto                                       ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}0.${NC} Voltar ao Menu Principal                                              ${WHITE}│${NC}"
        echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
        
        case $choice in
            1) full_backup ;;
            2) sites_backup_only ;;
            3) databases_backup_only ;;
            4) list_backups ;;
            5) restore_backup_menu ;;
            6) configure_auto_backup ;;
            7) clean_old_backups ;;
            8) sync_remote_backup ;;
            0) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 2 ;;
        esac
    done
}

# Backup completo
full_backup() {
    echo ""
    echo -e "${YELLOW}Iniciando backup completo...${NC}"
    
    backup_date=$(date +%Y%m%d_%H%M%S)
    backup_dir="/var/backups"
    full_backup_dir="$backup_dir/full_$backup_date"
    
    mkdir -p "$full_backup_dir"
    
    # Backup dos sites
    echo -e "${BLUE}Fazendo backup dos sites...${NC}"
    tar -czf "$full_backup_dir/websites.tar.gz" -C /var/www/html . 2>/dev/null
    
    # Backup dos bancos
    echo -e "${BLUE}Fazendo backup dos bancos...${NC}"
    databases=$(mysql -e "SHOW DATABASES;" 2>/dev/null | grep -v "Database\|information_schema\|performance_schema\|mysql\|sys")
    
    for db in $databases; do
        mysqldump "$db" | gzip > "$full_backup_dir/${db}.sql.gz" 2>/dev/null
    done
    
    # Backup das configurações
    echo -e "${BLUE}Fazendo backup das configurações...${NC}"
    case $OS in
        "oracle"|"rhel")
            tar -czf "$full_backup_dir/apache_config.tar.gz" -C /etc/httpd . 2>/dev/null
            ;;
        "ubuntu"|"debian")
            tar -czf "$full_backup_dir/apache_config.tar.gz" -C /etc/apache2 . 2>/dev/null
            ;;
    esac
    
    # Backup dos logs importantes
    echo -e "${BLUE}Fazendo backup dos logs...${NC}"
    cp "$LOG_FILE" "$full_backup_dir/" 2>/dev/null
    
    # Criar arquivo de informações
    cat > "$full_backup_dir/backup_info.txt" << INFO
Backup Completo - $(date)
Sistema: $OS $OS_VERSION
Servidor: $(hostname)
IP: $(curl -s ifconfig.me 2>/dev/null)

Conteúdo:
- Sites e arquivos web
- Bancos de dados: $databases
- Configurações Apache
- Logs do sistema

Comando para restaurar:
1. Extrair websites.tar.gz em /var/www/html/
2. Importar arquivos *.sql.gz nos bancos
3. Extrair apache_config.tar.gz no diretório apropriado
INFO
    
    # Criar arquivo compactado final
    cd "$backup_dir"
    tar -czf "backup_completo_$backup_date.tar.gz" "full_$backup_date/"
    rm -rf "full_$backup_date"
    
    backup_size=$(du -sh "backup_completo_$backup_date.tar.gz" | awk '{print $1}')
    
    echo -e "${GREEN}Backup completo finalizado!${NC}"
    echo -e "${BLUE}Arquivo: $backup_dir/backup_completo_$backup_date.tar.gz${NC}"
    echo -e "${BLUE}Tamanho: $backup_size${NC}"
    
    log_action "Backup completo realizado - $backup_size"
    read -p "Pressione Enter para continuar..."
}

# Backup apenas sites
sites_backup_only() {
    echo ""
    echo -e "${YELLOW}Fazendo backup apenas dos sites...${NC}"
    
    backup_dir="/var/backups/websites"
    mkdir -p "$backup_dir"
    backup_file="$backup_dir/sites_$(date +%Y%m%d_%H%M%S).tar.gz"
    
    tar -czf "$backup_file" -C /var/www/html . 2>/dev/null
    
    if [[ -f "$backup_file" ]]; then
        backup_size=$(du -sh "$backup_file" | awk '{print $1}')
        echo -e "${GREEN}Backup dos sites criado: $backup_file${NC}"
        echo -e "${BLUE}Tamanho: $backup_size${NC}"
        log_action "Backup dos sites realizado - $backup_size"
    else
        echo -e "${RED}Erro ao criar backup dos sites${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Backup apenas bancos
databases_backup_only() {
    echo ""
    echo -e "${YELLOW}Fazendo backup de todos os bancos...${NC}"
    
    backup_dir="/var/backups/databases"
    mkdir -p "$backup_dir"
    backup_date=$(date +%Y%m%d_%H%M%S)
    
    # Backup de todos os bancos em um arquivo
    all_db_file="$backup_dir/all_databases_$backup_date.sql.gz"
    mysqldump --all-databases | gzip > "$all_db_file" 2>/dev/null
    
    # Backup individual de cada banco
    databases=$(mysql -e "SHOW DATABASES;" 2>/dev/null | grep -v "Database\|information_schema\|performance_schema\|mysql\|sys")
    
    for db in $databases; do
        db_file="$backup_dir/${db}_$backup_date.sql.gz"
        mysqldump "$db" | gzip > "$db_file" 2>/dev/null
        echo -e "${GREEN}✅ $db${NC}"
    done
    
    total_size=$(du -sh "$backup_dir" | awk '{print $1}')
    echo -e "${GREEN}Backup dos bancos finalizado!${NC}"
    echo -e "${BLUE}Total usado: $total_size${NC}"
    
    log_action "Backup dos bancos realizado"
    read -p "Pressione Enter para continuar..."
}

# Listar backups
list_backups() {
    echo ""
    echo -e "${CYAN}═══ BACKUPS DISPONÍVEIS ═══${NC}"
    echo ""
    
    # Backups completos
    if [[ -d "/var/backups" ]]; then
        echo -e "${WHITE}📦 Backups Completos:${NC}"
        ls -lah /var/backups/backup_completo_*.tar.gz 2>/dev/null | while read -r line; do
            echo "  $line"
        done
        echo ""
    fi
    
    # Backups de sites
    if [[ -d "/var/backups/websites" ]]; then
        echo -e "${WHITE}🌐 Backups de Sites:${NC}"
        ls -lah /var/backups/websites/ | tail -5
        echo ""
    fi
    
    # Backups de bancos
    if [[ -d "/var/backups/databases" ]]; then
        echo -e "${WHITE}🗄️ Backups de Bancos:${NC}"
        ls -lah /var/backups/databases/ | tail -5
        echo ""
    fi
    
    # Espaço total usado
    echo -e "${BLUE}Espaço total usado pelos backups:${NC}"
    du -sh /var/backups/ 2>/dev/null || echo "Nenhum backup encontrado"
    
    # Espaço livre
    echo -e "${BLUE}Espaço livre no disco:${NC}"
    df -h /var/backups | tail -1
    
    read -p "Pressione Enter para continuar..."
}

# Menu de restauração
restore_backup_menu() {
    echo ""
    echo -e "${CYAN}═══ RESTAURAR BACKUP ═══${NC}"
    echo ""
    echo "1. Restaurar backup completo"
    echo "2. Restaurar apenas sites"
    echo "3. Restaurar apenas bancos"
    echo "0. Voltar"
    echo ""
    
    read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
    
    case $choice in
        1) restore_full_backup ;;
        2) restore_sites_backup ;;
        3) restore_databases_backup ;;
        0) return ;;
        *) echo -e "${RED}Opção inválida!${NC}"; sleep 2 ;;
    esac
}

# Restaurar backup completo
restore_full_backup() {
    echo ""
    echo -e "${CYAN}Backups completos disponíveis:${NC}"
    ls -la /var/backups/backup_completo_*.tar.gz 2>/dev/null | nl
    echo ""
    
    read -p "$(echo -e ${CYAN}"Caminho completo do backup: "${NC})" backup_file
    
    if [[ -f "$backup_file" ]]; then
        echo -e "${RED}⚠️  ATENÇÃO: Isso substituirá TODOS os dados atuais!${NC}"
        echo -e "${RED}Sites, bancos de dados e configurações serão sobrescritos!${NC}"
        echo ""
        read -p "$(echo -e ${RED}"Digite 'RESTAURAR' para confirmar: "${NC})" confirm
        
        if [[ "$confirm" == "RESTAURAR" ]]; then
            echo -e "${YELLOW}Restaurando backup completo...${NC}"
            
            # Extrair backup
            temp_dir="/tmp/restore_$(date +%s)"
            mkdir -p "$temp_dir"
            tar -xzf "$backup_file" -C "$temp_dir"
            
            extracted_dir=$(find "$temp_dir" -maxdepth 1 -type d -name "full_*" | head -1)
            
            if [[ -d "$extracted_dir" ]]; then
                # Restaurar sites
                if [[ -f "$extracted_dir/websites.tar.gz" ]]; then
                    echo -e "${BLUE}Restaurando sites...${NC}"
                    rm -rf /var/www/html/*
                    tar -xzf "$extracted_dir/websites.tar.gz" -C /var/www/html/
                    chown -R $WEB_USER:$WEB_GROUP /var/www/html/
                fi
                
                # Restaurar bancos
                echo -e "${BLUE}Restaurando bancos...${NC}"
                for sql_file in "$extracted_dir"/*.sql.gz; do
                    if [[ -f "$sql_file" ]]; then
                        db_name=$(basename "$sql_file" .sql.gz)
                        mysql -e "DROP DATABASE IF EXISTS \`$db_name\`; CREATE DATABASE \`$db_name\`;" 2>/dev/null
                        gunzip -c "$sql_file" | mysql "$db_name" 2>/dev/null
                        echo -e "${GREEN}✅ $db_name${NC}"
                    fi
                done
                
                # Restaurar configurações Apache
                if [[ -f "$extracted_dir/apache_config.tar.gz" ]]; then
                    echo -e "${BLUE}Restaurando configurações Apache...${NC}"
                    case $OS in
                        "oracle"|"rhel")
                            tar -xzf "$extracted_dir/apache_config.tar.gz" -C /etc/httpd/
                            ;;
                        "ubuntu"|"debian")
                            tar -xzf "$extracted_dir/apache_config.tar.gz" -C /etc/apache2/
                            ;;
                    esac
                fi
                
                # Reiniciar serviços
                echo -e "${BLUE}Reiniciando serviços...${NC}"
                systemctl restart $WEB_SERVICE
                systemctl restart $MYSQL_SERVICE
                
                # Limpar arquivos temporários
                rm -rf "$temp_dir"
                
                echo -e "${GREEN}Backup completo restaurado com sucesso!${NC}"
                log_action "Backup completo restaurado de $backup_file"
            else
                echo -e "${RED}Erro: estrutura do backup não reconhecida${NC}"
            fi
        else
            echo -e "${YELLOW}Restauração cancelada${NC}"
        fi
    else
        echo -e "${RED}Arquivo de backup não encontrado!${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Restaurar backup de sites
restore_sites_backup() {
    echo ""
    echo -e "${CYAN}Backups de sites disponíveis:${NC}"
    ls -la /var/backups/websites/*.tar.gz 2>/dev/null | nl
    echo ""
    
    read -p "$(echo -e ${CYAN}"Caminho completo do backup: "${NC})" backup_file
    
    if [[ -f "$backup_file" ]]; then
        echo -e "${RED}⚠️  Isso substituirá todos os sites atuais!${NC}"
        read -p "$(echo -e ${RED}"Continuar? (s/N): "${NC})" confirm
        if [[ "$confirm" == "s" || "$confirm" == "S" ]]; then
            echo -e "${YELLOW}Restaurando sites...${NC}"
            
            # Backup dos sites atuais
            current_backup="/var/backups/websites/backup_antes_restore_$(date +%Y%m%d_%H%M%S).tar.gz"
            tar -czf "$current_backup" -C /var/www/html . 2>/dev/null
            echo -e "${BLUE}Backup atual salvo em: $current_backup${NC}"
            
            # Restaurar
            rm -rf /var/www/html/*
            tar -xzf "$backup_file" -C /var/www/html/
            chown -R $WEB_USER:$WEB_GROUP /var/www/html/
            
            systemctl restart $WEB_SERVICE
            
            echo -e "${GREEN}Sites restaurados com sucesso!${NC}"
            log_action "Sites restaurados de $backup_file"
        fi
    else
        echo -e "${RED}Arquivo de backup não encontrado!${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Configurar backup automático
configure_auto_backup() {
    echo ""
    echo -e "${CYAN}═══ CONFIGURAR BACKUP AUTOMÁTICO ═══${NC}"
    echo ""
    echo "Configuração atual do cron:"
    crontab -l 2>/dev/null | grep -i backup || echo "Nenhum backup automático configurado"
    echo ""
    
    echo "Opções de frequência:"
    echo "1. Diário (2:00 AM)"
    echo "2. Semanal (Domingos 2:00 AM)"  
    echo "3. Mensal (Dia 1, 2:00 AM)"
    echo "4. Personalizado"
    echo "5. Desativar backup automático"
    echo ""
    
    read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
    
    # Criar script de backup se não existir
    backup_script="/usr/local/bin/auto-backup.sh"
    cat > "$backup_script" << 'BACKUP_SCRIPT'
#!/bin/bash
# Script de backup automático
LOG_FILE="/var/log/auto-backup.log"
BACKUP_DIR="/var/backups"

echo "$(date): Iniciando backup automático" >> "$LOG_FILE"

# Backup completo
cd "$BACKUP_DIR"
backup_date=$(date +%Y%m%d_%H%M%S)

# Sites
tar -czf "auto_sites_$backup_date.tar.gz" -C /var/www/html . 2>>"$LOG_FILE"

# Bancos
mysqldump --all-databases | gzip > "auto_databases_$backup_date.sql.gz" 2>>"$LOG_FILE"

# Limpar backups antigos (manter apenas 7 dias)
find "$BACKUP_DIR" -name "auto_*" -type f -mtime +7 -delete 2>>"$LOG_FILE"

echo "$(date): Backup automático finalizado" >> "$LOG_FILE"
BACKUP_SCRIPT

    chmod +x "$backup_script"
    
    case $choice in
        1)
            (crontab -l 2>/dev/null; echo "0 2 * * * $backup_script") | crontab -
            echo -e "${GREEN}Backup diário configurado para 2:00 AM!${NC}"
            ;;
        2)
            (crontab -l 2>/dev/null; echo "0 2 * * 0 $backup_script") | crontab -
            echo -e "${GREEN}Backup semanal configurado para domingos 2:00 AM!${NC}"
            ;;
        3)
            (crontab -l 2>/dev/null; echo "0 2 1 * * $backup_script") | crontab -
            echo -e "${GREEN}Backup mensal configurado para dia 1, 2:00 AM!${NC}"
            ;;
        4)
            echo ""
            read -p "$(echo -e ${CYAN}"Digite a expressão cron (ex: '0 2 * * *'): "${NC})" cron_expr
            if [[ -n "$cron_expr" ]]; then
                (crontab -l 2>/dev/null; echo "$cron_expr $backup_script") | crontab -
                echo -e "${GREEN}Backup personalizado configurado!${NC}"
            fi
            ;;
        5)
            crontab -l 2>/dev/null | grep -v backup | crontab -
            echo -e "${YELLOW}Backup automático desativado!${NC}"
            ;;
        *)
            echo -e "${RED}Opção inválida!${NC}"
            ;;
    esac
    
    log_action "Backup automático configurado"
    read -p "Pressione Enter para continuar..."
}

# Limpar backups antigos
clean_old_backups() {
    echo ""
    read -p "$(echo -e ${CYAN}"Quantos dias de backups manter? (padrão: 30): "${NC})" days
    days=${days:-30}
    
    echo -e "${YELLOW}Removendo backups com mais de $days dias...${NC}"
    
    # Contar arquivos antes
    before_count=$(find /var/backups -type f -name "*.tar.gz" -o -name "*.sql.gz" | wc -l)
    before_size=$(du -sh /var/backups 2>/dev/null | awk '{print $1}')
    
    # Remover arquivos antigos
    find /var/backups -type f \( -name "*.tar.gz" -o -name "*.sql.gz" \) -mtime +$days -delete
    
    # Contar arquivos depois
    after_count=$(find /var/backups -type f -name "*.tar.gz" -o -name "*.sql.gz" | wc -l)
    after_size=$(du -sh /var/backups 2>/dev/null | awk '{print $1}')
    
    removed_count=$((before_count - after_count))
    
    echo -e "${GREEN}Limpeza concluída!${NC}"
    echo -e "${BLUE}Arquivos removidos: $removed_count${NC}"
    echo -e "${BLUE}Tamanho antes: $before_size${NC}"
    echo -e "${BLUE}Tamanho depois: $after_size${NC}"
    
    log_action "Backups antigos limpos - $removed_count arquivos removidos"
    read -p "Pressione Enter para continuar..."
}

# Sincronizar com servidor remoto
sync_remote_backup() {
    echo ""
    echo -e "${CYAN}═══ SINCRONIZAÇÃO COM SERVIDOR REMOTO ═══${NC}"
    echo ""
    
    read -p "$(echo -e ${CYAN}"Servidor remoto (user@host): "${NC})" remote_server
    read -p "$(echo -e ${CYAN}"Diretório remoto: "${NC})" remote_dir
    
    if [[ -n "$remote_server" && -n "$remote_dir" ]]; then
        echo -e "${YELLOW}Testando conexão...${NC}"
        
        if ssh -o ConnectTimeout=5 "$remote_server" "echo 'Conexão OK'" 2>/dev/null; then
            echo -e "${GREEN}Conexão estabelecida!${NC}"
            
            echo -e "${YELLOW}Sincronizando backups...${NC}"
            rsync -avz --progress /var/backups/ "$remote_server:$remote_dir/"
            
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}Sincronização concluída com sucesso!${NC}"
                log_action "Backups sincronizados com $remote_server:$remote_dir"
            else
                echo -e "${RED}Erro na sincronização${NC}"
            fi
        else
            echo -e "${RED}Erro: Não foi possível conectar ao servidor remoto${NC}"
            echo "Verifique:"
            echo "- Conexão de rede"
            echo "- Chaves SSH configuradas"
            echo "- Permissões no servidor remoto"
        fi
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Instalar software comum
install_software_menu() {
    while true; do
        clear
        show_header
        echo -e "${WHITE}┌─ INSTALAR SOFTWARE ($OS) ────────────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}1.${NC} Instalar Node.js e NPM                                                ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}2.${NC} Instalar Composer (PHP)                                               ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}3.${NC} Instalar Git                                                          ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}4.${NC} Instalar Redis                                                        ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}5.${NC} Instalar Memcached                                                    ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}6.${NC} Instalar Certbot (Let's Encrypt)                                      ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}7.${NC} Instalar phpMyAdmin                                                   ${WHITE}│${NC}"
        # Continuação - Instalar software e demais funcionalidades

        echo -e "${WHITE}│${NC}  ${GREEN}8.${NC} Instalar Docker                                                       ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}9.${NC} Instalar Python e pip                                                 ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}10.${NC} Ferramentas de Monitoramento                                          ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}0.${NC} Voltar ao Menu Principal                                              ${WHITE}│${NC}"
        echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
        
        case $choice in
            1) install_nodejs ;;
            2) install_composer ;;
            3) install_git ;;
            4) install_redis ;;
            5) install_memcached ;;
            6) install_certbot ;;
            7) install_phpmyadmin ;;
            8) install_docker ;;
            9) install_python ;;
            10) install_monitoring_tools ;;
            0) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 2 ;;
        esac
    done
}

# Instalar Node.js
install_nodejs() {
    echo ""
    echo -e "${YELLOW}Instalando Node.js...${NC}"
    
    case $PKG_MANAGER in
        "apt")
            curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
            install_package nodejs
            ;;
        "dnf"|"yum")
            curl -fsSL https://rpm.nodesource.com/setup_lts.x | bash -
            install_package nodejs npm
            ;;
    esac
    
    if command -v node >/dev/null 2>&1; then
        echo -e "${GREEN}Node.js instalado: $(node --version)${NC}"
        echo -e "${GREEN}NPM instalado: $(npm --version)${NC}"
        log_action "Node.js instalado"
    else
        echo -e "${RED}Erro na instalação do Node.js${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Instalar Composer
install_composer() {
    echo ""
    echo -e "${YELLOW}Instalando Composer...${NC}"
    
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer
    chmod +x /usr/local/bin/composer
    
    if command -v composer >/dev/null 2>&1; then
        echo -e "${GREEN}Composer instalado: $(composer --version)${NC}"
        log_action "Composer instalado"
    else
        echo -e "${RED}Erro na instalação do Composer${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Instalar Git
install_git() {
    echo ""
    echo -e "${YELLOW}Instalando Git...${NC}"
    
    install_package git
    
    if command -v git >/dev/null 2>&1; then
        echo -e "${GREEN}Git instalado: $(git --version)${NC}"
        
        # Configuração básica
        read -p "Nome para configuração do Git (opcional): " git_name
        read -p "Email para configuração do Git (opcional): " git_email
        
        if [[ -n "$git_name" ]]; then
            git config --global user.name "$git_name"
        fi
        
        if [[ -n "$git_email" ]]; then
            git config --global user.email "$git_email"
        fi
        
        log_action "Git instalado"
    else
        echo -e "${RED}Erro na instalação do Git${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Instalar Redis
install_redis() {
    echo ""
    echo -e "${YELLOW}Instalando Redis...${NC}"
    
    case $PKG_MANAGER in
        "apt")
            install_package redis-server
            systemctl enable redis-server
            systemctl start redis-server
            redis_service="redis-server"
            ;;
        "dnf"|"yum")
            install_package redis
            systemctl enable redis
            systemctl start redis
            redis_service="redis"
            ;;
    esac
    
    if systemctl is-active "$redis_service" >/dev/null 2>&1; then
        echo -e "${GREEN}Redis instalado e ativo!${NC}"
        
        # Teste básico
        if command -v redis-cli >/dev/null 2>&1; then
            echo "PING" | redis-cli && echo -e "${GREEN}Redis funcionando corretamente!${NC}"
        fi
        
        log_action "Redis instalado"
    else
        echo -e "${RED}Erro na instalação do Redis${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Instalar Memcached
install_memcached() {
    echo ""
    echo -e "${YELLOW}Instalando Memcached...${NC}"
    
    install_package memcached
    systemctl enable memcached
    systemctl start memcached
    
    if systemctl is-active memcached >/dev/null 2>&1; then
        echo -e "${GREEN}Memcached instalado e ativo!${NC}"
        
        # Instalar extensão PHP se disponível
        case $PKG_MANAGER in
            "apt")
                install_package php-memcached
                ;;
            "dnf"|"yum")
                install_package php-memcached
                ;;
        esac
        
        restart_php_service
        
        log_action "Memcached instalado"
    else
        echo -e "${RED}Erro na instalação do Memcached${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Instalar Certbot
install_certbot() {
    echo ""
    echo -e "${YELLOW}Instalando Certbot (Let's Encrypt)...${NC}"
    
    case $PKG_MANAGER in
        "apt")
            install_package certbot python3-certbot-apache
            ;;
        "dnf"|"yum")
            # Instalar EPEL se necessário
            if [[ "$OS" == "oracle" ]]; then
                dnf install -y oracle-epel-release-el$OS_VERSION
            fi
            install_package certbot python3-certbot-apache
            ;;
    esac
    
    if command -v certbot >/dev/null 2>&1; then
        echo -e "${GREEN}Certbot instalado: $(certbot --version)${NC}"
        
        # Configurar renovação automática
        (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
        
        echo -e "${GREEN}Renovação automática configurada!${NC}"
        log_action "Certbot instalado"
    else
        echo -e "${RED}Erro na instalação do Certbot${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Instalar phpMyAdmin
install_phpmyadmin() {
    echo ""
    echo -e "${YELLOW}Instalando phpMyAdmin...${NC}"
    
    # Download da versão mais recente
    cd /tmp
    wget https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz
    
    if [[ -f "phpMyAdmin-latest-all-languages.tar.gz" ]]; then
        tar -xzf phpMyAdmin-latest-all-languages.tar.gz
        pma_dir=$(ls -d phpMyAdmin-*-all-languages | head -1)
        
        if [[ -d "$pma_dir" ]]; then
            mv "$pma_dir" /var/www/html/phpmyadmin
            chown -R $WEB_USER:$WEB_GROUP /var/www/html/phpmyadmin
            
            # Configurar phpMyAdmin
            cp /var/www/html/phpmyadmin/config.sample.inc.php /var/www/html/phpmyadmin/config.inc.php
            
            # Gerar blowfish secret
            secret=$(openssl rand -base64 32)
            sed -i "s/\$cfg\['blowfish_secret'\] = '';/\$cfg['blowfish_secret'] = '$secret';/" /var/www/html/phpmyadmin/config.inc.php
            
            # Criar diretório temporário
            mkdir -p /var/www/html/phpmyadmin/tmp
            chown $WEB_USER:$WEB_GROUP /var/www/html/phpmyadmin/tmp
            chmod 777 /var/www/html/phpmyadmin/tmp
            
            echo -e "${GREEN}phpMyAdmin instalado com sucesso!${NC}"
            echo -e "${BLUE}Acesso: http://$(curl -s ifconfig.me)/phpmyadmin${NC}"
            echo -e "${YELLOW}Use as credenciais do MySQL/MariaDB para fazer login${NC}"
            
            log_action "phpMyAdmin instalado"
        fi
        
        # Limpar arquivos temporários
        rm -rf /tmp/phpMyAdmin-*
    else
        echo -e "${RED}Erro ao baixar phpMyAdmin${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Instalar Docker
install_docker() {
    echo ""
    echo -e "${YELLOW}Instalando Docker...${NC}"
    
    case $PKG_MANAGER in
        "apt")
            install_package apt-transport-https ca-certificates curl gnupg lsb-release
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
            apt-get update
            install_package docker-ce docker-ce-cli containerd.io docker-compose-plugin
            ;;
        "dnf"|"yum")
            install_package docker docker-compose
            ;;
    esac
    
    systemctl enable docker
    systemctl start docker
    
    if systemctl is-active docker >/dev/null 2>&1; then
        echo -e "${GREEN}Docker instalado e ativo!${NC}"
        echo -e "${GREEN}Versão: $(docker --version)${NC}"
        
        # Adicionar usuário atual ao grupo docker
        usermod -aG docker root
        
        log_action "Docker instalado"
    else
        echo -e "${RED}Erro na instalação do Docker${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Instalar Python
install_python() {
    echo ""
    echo -e "${YELLOW}Instalando Python e pip...${NC}"
    
    case $PKG_MANAGER in
        "apt")
            install_package python3 python3-pip python3-venv
            ;;
        "dnf"|"yum")
            install_package python3 python3-pip
            ;;
    esac
    
    if command -v python3 >/dev/null 2>&1; then
        echo -e "${GREEN}Python instalado: $(python3 --version)${NC}"
        echo -e "${GREEN}pip instalado: $(pip3 --version)${NC}"
        log_action "Python instalado"
    else
        echo -e "${RED}Erro na instalação do Python${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Ferramentas de monitoramento
install_monitoring_tools() {
    echo ""
    echo -e "${YELLOW}Instalando ferramentas de monitoramento...${NC}"
    
    # Instalar htop, iotop, nethogs
    case $PKG_MANAGER in
        "apt")
            install_package htop iotop nethogs ncdu
            ;;
        "dnf"|"yum")
            install_package htop iotop nethogs ncdu
            ;;
    esac
    
    echo -e "${GREEN}Ferramentas instaladas:${NC}"
    echo "- htop: monitor de processos"
    echo "- iotop: monitor de I/O"
    echo "- nethogs: monitor de rede por processo"
    echo "- ncdu: analisador de uso de disco"
    
    log_action "Ferramentas de monitoramento instaladas"
    read -p "Pressione Enter para continuar..."
}

# Estatísticas web
show_web_stats() {
    clear
    show_header
    echo -e "${WHITE}┌─ ESTATÍSTICAS WEB ───────────────────────────────────────────────────────────┐${NC}"
    
    # Log do Apache
    case $OS in
        "oracle"|"rhel")
            access_log="/var/log/httpd/access_log"
            error_log="/var/log/httpd/error_log"
            ;;
        "ubuntu"|"debian")
            access_log="/var/log/apache2/access.log"
            error_log="/var/log/apache2/error.log"
            ;;
    esac
    
    if [[ -f "$access_log" ]]; then
        echo -e "${WHITE}│${NC} ${CYAN}📊 Estatísticas Apache (últimas 24h):${NC}$(printf '%*s' $((37)) '')${WHITE}│${NC}"
        
        total_requests=$(grep "$(date '+%d/%b/%Y')" "$access_log" 2>/dev/null | wc -l)
        unique_ips=$(grep "$(date '+%d/%b/%Y')" "$access_log" 2>/dev/null | awk '{print $1}' | sort | uniq | wc -l)
        
        echo -e "${WHITE}│${NC}   Total de Requests: $total_requests$(printf '%*s' $((52-${#total_requests})) '')${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}   IPs Únicos: $unique_ips$(printf '%*s' $((57-${#unique_ips})) '')${WHITE}│${NC}"
        
        echo -e "${WHITE}│${NC} ${CYAN}🔝 Top 5 IPs mais ativos:${NC}$(printf '%*s' $((41)) '')${WHITE}│${NC}"
        grep "$(date '+%d/%b/%Y')" "$access_log" 2>/dev/null | awk '{print $1}' | sort | uniq -c | sort -nr | head -5 | while read count ip; do
            echo -e "${WHITE}│${NC}   $ip: $count requests$(printf '%*s' $((50-${#ip}-${#count})) '')${WHITE}│${NC}"
        done
    fi
    
    echo -e "${WHITE}├──────────────────────────────────────────────────────────────────────────────┤${NC}"
    
    # Recursos do sistema
    echo -e "${WHITE}│${NC} ${CYAN}🖥️ Recursos do Sistema:${NC}$(printf '%*s' $((46)) '')${WHITE}│${NC}"
    
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//')
    echo -e "${WHITE}│${NC}   Load Average: $load_avg$(printf '%*s' $((52-${#load_avg})) '')${WHITE}│${NC}"
    
    memory_usage=$(free | grep Mem | awk '{printf "%.1f%%", ($3/$2)*100}')
    echo -e "${WHITE}│${NC}   Uso de Memória: $memory_usage$(printf '%*s' $((48-${#memory_usage})) '')${WHITE}│${NC}"
    
    disk_usage=$(df -h / | tail -1 | awk '{print $5}')
    echo -e "${WHITE}│${NC}   Uso de Disco: $disk_usage$(printf '%*s' $((50-${#disk_usage})) '')${WHITE}│${NC}"
    
    echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    read -p "Pressione Enter para continuar..."
}

# Monitor do sistema em tempo real
system_monitor() {
    while true; do
        clear
        show_header
        echo -e "${WHITE}┌─ MONITOR DO SISTEMA ─────────────────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│${NC} Pressione 'q' para sair$(printf '%*s' $((53)) '')${WHITE}│${NC}"
        echo -e "${WHITE}├──────────────────────────────────────────────────────────────────────────────┤${NC}"
        
        # CPU e Load
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[ \t]*//')
        echo -e "${WHITE}│${NC} ${YELLOW}⚡ Load Average:${NC} $load_avg$(printf '%*s' $((45-${#load_avg})) '')${WHITE}│${NC}"
        
        # Memória
        memory_info=$(free -h | grep Mem | awk '{printf "%s/%s (%.1f%%)", $3, $2, ($3/$2)*100}')
        echo -e "${WHITE}│${NC} ${BLUE}💾 Memória:${NC} $memory_info$(printf '%*s' $((50-${#memory_info})) '')${WHITE}│${NC}"
        
        # Processos
        process_count=$(ps aux | wc -l)
        echo -e "${WHITE}│${NC} ${GREEN}🔄 Processos:${NC} $process_count$(printf '%*s' $((52-${#process_count})) '')${WHITE}│${NC}"
        
        # Conexões ativas
        connections=$(netstat -an 2>/dev/null | grep :80 | grep ESTABLISHED | wc -l)
        echo -e "${WHITE}│${NC} ${CYAN}🌐 Conexões HTTP:${NC} $connections$(printf '%*s' $((46-${#connections})) '')${WHITE}│${NC}"
        
        echo -e "${WHITE}├──────────────────────────────────────────────────────────────────────────────┤${NC}"
        echo -e "${WHITE}│${NC} ${PURPLE}📈 Top 5 Processos (CPU):${NC}$(printf '%*s' $((41)) '')${WHITE}│${NC}"
        
        ps aux --sort=-%cpu | head -6 | tail -5 | while read line; do
            process=$(echo "$line" | awk '{printf "%-12s %s%%", $11, $3}')
            echo -e "${WHITE}│${NC}   $process$(printf '%*s' $((55-${#process})) '')${WHITE}│${NC}"
        done
        
        echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        
        # Aguardar 3 segundos ou tecla 'q'
        read -t 3 -n 1 key
        if [[ "$key" == "q" || "$key" == "Q" ]]; then
            break
        fi
    done
}

# Manutenção e otimização
manage_maintenance() {
    while true; do
        clear
        show_header
        echo -e "${WHITE}┌─ MANUTENÇÃO & OTIMIZAÇÃO ($OS) ──────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}1.${NC} Otimização Completa do Servidor                                       ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}2.${NC} Limpar Cache e Arquivos Temporários                                   ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}3.${NC} Atualizar Sistema                                                     ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}4.${NC} Verificar e Corrigir Permissões                                       ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}5.${NC} Limpar Logs Antigos                                                   ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}6.${NC} Otimizar Banco de Dados                                               ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}7.${NC} Análise de Segurança                                                  ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}8.${NC} Reinicialização Programada                                            ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}0.${NC} Voltar ao Menu Principal                                              ${WHITE}│${NC}"
        echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
        
        case $choice in
            1) full_server_optimization ;;
            2) clean_cache_and_temp ;;
            3) update_system_universal ;;
            4) fix_permissions_universal ;;
            5) clean_old_logs ;;
            6) optimize_databases_universal ;;
            7) security_analysis ;;
            8) schedule_reboot ;;
            0) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 2 ;;
        esac
    done
}

# Otimização completa do servidor
full_server_optimization() {
    echo ""
    echo -e "${YELLOW}Iniciando otimização completa do servidor...${NC}"
    echo ""
    
    # 1. Limpar cache
    echo -e "${BLUE}1. Limpando caches...${NC}"
    sync && echo 3 > /proc/sys/vm/drop_caches
    
    # 2. PHP OPcache
    php -r "opcache_reset();" 2>/dev/null && echo "PHP OPcache limpo"
    
    # 3. Redis
    redis-cli FLUSHALL 2>/dev/null && echo "Redis cache limpo"
    
    # 4. Memcached
    echo "flush_all" | nc localhost 11211 2>/dev/null && echo "Memcached limpo"
    
    # 5. Otimizar bancos
    echo -e "${BLUE}2. Otimizando bancos de dados...${NC}"
    optimize_databases_universal_silent
    
    # 6. Limpar logs antigos
    echo -e "${BLUE}3. Limpando logs antigos...${NC}"
    find /var/log -name "*.log.*" -mtime +7 -delete 2>/dev/null
    journalctl --vacuum-time=7d >/dev/null 2>&1
    
    # 7. Limpar arquivos temporários
    echo -e "${BLUE}4. Limpando arquivos temporários...${NC}"
    rm -rf /tmp/* 2>/dev/null
    rm -rf /var/tmp/* 2>/dev/null
    
    # 8. Limpar cache de pacotes
    case $PKG_MANAGER in
        "apt") apt-get clean >/dev/null 2>&1 ;;
        "dnf"|"yum") $PKG_MANAGER clean all >/dev/null 2>&1 ;;
    esac
    
    # 9. Corrigir permissões
    echo -e "${BLUE}5. Corrigindo permissões...${NC}"
    chown -R $WEB_USER:$WEB_GROUP /var/www/html/
    
    # 10. Reiniciar serviços críticos
    echo -e "${BLUE}6. Reiniciando serviços...${NC}"
    systemctl restart $WEB_SERVICE
    systemctl restart $PHP_SERVICE 2>/dev/null
    
    echo -e "${GREEN}Otimização completa finalizada!${NC}"
    
    # Mostrar estatísticas
    echo ""
    echo -e "${CYAN}Estatísticas após otimização:${NC}"
    echo "Memória disponível: $(free -h | grep Mem | awk '{print $7}')"
    echo "Espaço livre: $(df -h / | tail -1 | awk '{print $4}')"
    
    log_action "Otimização completa executada"
    read -p "Pressione Enter para continuar..."
}

# Função silenciosa para otimizar bancos
optimize_databases_universal_silent() {
    databases=$(mysql -e "SHOW DATABASES;" 2>/dev/null | grep -v "Database\|information_schema\|performance_schema\|mysql\|sys")
    
    for db in $databases; do
        tables=$(mysql -e "USE $db; SHOW TABLES;" 2>/dev/null | grep -v "Tables_in")
        
        for table in $tables; do
            mysql -e "USE $db; OPTIMIZE TABLE $table;" 2>/dev/null >/dev/null
        done
    done
}

# Limpar cache e arquivos temporários
clean_cache_and_temp() {
    echo ""
    echo -e "${YELLOW}Limpando cache e arquivos temporários...${NC}"
    
    before_free=$(df / | tail -1 | awk '{print $4}')
    
    # System cache
    sync && echo 3 > /proc/sys/vm/drop_caches
    
    # PHP
    php -r "opcache_reset();" 2>/dev/null
    find /var/lib/php/sessions/ -type f -mtime +1 -delete 2>/dev/null
    
    # Web server logs rotação
    logrotate -f /etc/logrotate.conf 2>/dev/null
    
    # Temp files
    find /tmp -type f -mtime +1 -delete 2>/dev/null
    find /var/tmp -type f -mtime +1 -delete 2>/dev/null
    
    # Package cache
    case $PKG_MANAGER in
        "apt") 
            apt-get clean
            apt-get autoremove -y
            ;;
        "dnf"|"yum") 
            $PKG_MANAGER clean all
            ;;
    esac
    
    # User cache
    rm -rf /root/.cache/* 2>/dev/null
    
    after_free=$(df / | tail -1 | awk '{print $4}')
    freed=$((after_free - before_free))
    
    echo -e "${GREEN}Limpeza concluída!${NC}"
    echo -e "${BLUE}Espaço liberado: $(echo $freed | awk '{printf "%.1f MB", $1/1024}')${NC}"
    
    log_action "Cache e arquivos temporários limpos"
    read -p "Pressione Enter para continuar..."
}

# Limpar logs antigos
clean_old_logs() {
    echo ""
    read -p "$(echo -e ${CYAN}"Quantos dias de logs manter? (padrão: 7): "${NC})" days
    days=${days:-7}
    
    echo -e "${YELLOW}Limpando logs com mais de $days dias...${NC}"
    
    # Logs do Apache
    case $OS in
        "oracle"|"rhel")
            find /var/log/httpd -name "*.log*" -mtime +$days -delete 2>/dev/null
            ;;
        "ubuntu"|"debian")
            find /var/log/apache2 -name "*.log*" -mtime +$days -delete 2>/dev/null
            ;;
    esac
    
    # Logs do sistema
    find /var/log -name "*.log.*" -mtime +$days -delete 2>/dev/null
    journalctl --vacuum-time=${days}d >/dev/null 2>&1
    
    # Logs personalizados
    find /var/log -name "*.gz" -mtime +$days -delete 2>/dev/null
    
    echo -e "${GREEN}Logs antigos removidos!${NC}"
    log_action "Logs antigos limpos (>$days dias)"
    read -p "Pressione Enter para continuar..."
}

# Análise de segurança
security_analysis() {
    echo ""
    echo -e "${CYAN}═══ ANÁLISE DE SEGURANÇA ═══${NC}"
    echo ""
    
    # Verificar permissões críticas
    echo -e "${BLUE}Verificando permissões críticas...${NC}"
    
    critical_files=(
        "/etc/passwd"
        "/etc/shadow" 
        "/etc/ssh/sshd_config"
    )
    
    for file in "${critical_files[@]}"; do
        if [[ -f "$file" ]]; then
            perm=$(stat -c "%a" "$file")
            case "$file" in
                "/etc/shadow")
                    [[ "$perm" == "640" ]] && echo -e "${GREEN}✅ $file${NC}" || echo -e "${YELLOW}⚠️  $file ($perm)${NC}"
                    ;;
                *)
                    [[ "$perm" == "644" ]] && echo -e "${GREEN}✅ $file${NC}" || echo -e "${YELLOW}⚠️  $file ($perm)${NC}"
                    ;;
            esac
        fi
    done
    
    # Verificar usuários com UID 0
    echo ""
    echo -e "${BLUE}Verificando usuários privilegiados...${NC}"
    awk -F: '$3==0 {print $1}' /etc/passwd | while read user; do
        if [[ "$user" == "root" ]]; then
            echo -e "${GREEN}✅ $user (normal)${NC}"
        else
            echo -e "${RED}⚠️  $user (UID 0 suspeito)${NC}"
        fi
    done
    
    # Verificar portas abertas
    echo ""
    echo -e "${BLUE}Portas abertas:${NC}"
    netstat -tlnp 2>/dev/null | grep LISTEN | head -10
    
    # Verificar falhas de login
    echo ""
    echo -e "${BLUE}Últimas tentativas de login falhadas:${NC}"
    lastb | head -5 2>/dev/null || echo "Log de falhas não disponível"
    
    # Verificar processos suspeitos
    
    # Continuação - Análise de segurança e funcionalidades finais

    # Verificar processos suspeitos
    echo ""
    echo -e "${BLUE}Verificando processos com alto uso de CPU:${NC}"
    ps aux --sort=-%cpu | head -6 | tail -5
    
    # Verificar arquivos com permissões 777
    echo ""
    echo -e "${BLUE}Arquivos com permissões 777 (potencial risco):${NC}"
    find /var/www/html -type f -perm 777 2>/dev/null | head -5 || echo "Nenhum arquivo encontrado"
    
    # Verificar atualizações de segurança
    echo ""
    echo -e "${BLUE}Verificando atualizações de segurança disponíveis...${NC}"
    case $PKG_MANAGER in
        "apt")
            apt list --upgradable 2>/dev/null | grep -i security | wc -l | xargs echo "Atualizações de segurança disponíveis:"
            ;;
        "dnf"|"yum")
            $PKG_MANAGER check-update --security 2>/dev/null | grep -c "updates" || echo "0 atualizações de segurança"
            ;;
    esac
    
    echo ""
    log_action "Análise de segurança executada"
    read -p "Pressione Enter para continuar..."
}

# Agendar reinicialização
schedule_reboot() {
    echo ""
    echo -e "${CYAN}═══ REINICIALIZAÇÃO PROGRAMADA ═══${NC}"
    echo ""
    echo "1. Reiniciar em 10 minutos"
    echo "2. Reiniciar em 1 hora"
    echo "3. Reiniciar à meia-noite"
    echo "4. Personalizado"
    echo "5. Cancelar reinicialização programada"
    echo ""
    
    read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
    
    case $choice in
        1)
            shutdown -r +10 "Servidor será reiniciado em 10 minutos para manutenção"
            echo -e "${GREEN}Reinicialização agendada para 10 minutos!${NC}"
            ;;
        2)
            shutdown -r +60 "Servidor será reiniciado em 1 hora para manutenção"
            echo -e "${GREEN}Reinicialização agendada para 1 hora!${NC}"
            ;;
        3)
            shutdown -r 00:00 "Servidor será reiniciado à meia-noite para manutenção"
            echo -e "${GREEN}Reinicialização agendada para meia-noite!${NC}"
            ;;
        4)
            echo ""
            read -p "$(echo -e ${CYAN}"Digite o horário (HH:MM) ou minutos (+MM): "${NC})" time
            if [[ -n "$time" ]]; then
                shutdown -r "$time" "Servidor será reiniciado conforme programado"
                echo -e "${GREEN}Reinicialização agendada para $time!${NC}"
            fi
            ;;
        5)
            shutdown -c 2>/dev/null
            echo -e "${YELLOW}Reinicialização programada cancelada!${NC}"
            ;;
        *)
            echo -e "${RED}Opção inválida!${NC}"
            ;;
    esac
    
    log_action "Reinicialização programada configurada"
    read -p "Pressione Enter para continuar..."
}

# Documentação do sistema
show_documentation() {
    clear
    show_header
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                            📖 DOCUMENTAÇÃO DO SISTEMA                           ${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    echo -e "${WHITE}INFORMAÇÕES DO SERVIDOR:${NC}"
    echo "  Sistema Operacional: $OS $OS_VERSION"
    echo "  Gerenciador de Pacotes: $PKG_MANAGER"
    echo "  Servidor Web: $WEB_SERVICE"
    echo "  PHP: $PHP_SERVICE"
    echo "  Banco de Dados: $MYSQL_SERVICE"
    echo "  Firewall: $FIREWALL_SERVICE"
    echo ""
    
    echo -e "${WHITE}ESTRUTURA DE DIRETÓRIOS:${NC}"
    echo "  Sites: /var/www/html/sites/"
    echo "  Logs Web: /var/log/$WEB_SERVICE/"
    echo "  Backups: /var/backups/"
    echo "  Log do Script: $LOG_FILE"
    echo ""
    
    case $OS in
        "oracle"|"rhel")
            echo -e "${WHITE}CONFIGURAÇÕES APACHE (Oracle Linux/RHEL):${NC}"
            echo "  Configuração principal: /etc/httpd/conf/httpd.conf"
            echo "  Sites disponíveis: /etc/httpd/sites-available/"
            echo "  Sites habilitados: /etc/httpd/sites-enabled/"
            echo "  Módulos: /etc/httpd/conf.modules.d/"
            ;;
        "ubuntu"|"debian")
            echo -e "${WHITE}CONFIGURAÇÕES APACHE (Ubuntu/Debian):${NC}"
            echo "  Configuração principal: /etc/apache2/apache2.conf"
            echo "  Sites disponíveis: /etc/apache2/sites-available/"
            echo "  Sites habilitados: /etc/apache2/sites-enabled/"
            echo "  Módulos: /etc/apache2/mods-available/"
            ;;
    esac
    
    echo ""
    echo -e "${WHITE}COMANDOS ÚTEIS:${NC}"
    echo "  Reiniciar Apache: systemctl restart $WEB_SERVICE"
    echo "  Ver logs em tempo real: tail -f /var/log/$WEB_SERVICE/access.log"
    echo "  Testar config Apache: $WEB_SERVICE -t"
    echo "  Status dos serviços: systemctl status $WEB_SERVICE"
    echo ""
    
    echo -e "${WHITE}PORTAS PADRÃO:${NC}"
    echo "  HTTP: 80"
    echo "  HTTPS: 443"
    echo "  SSH: 22"
    echo "  MySQL/MariaDB: 3306"
    echo "  Redis: 6379"
    echo "  Memcached: 11211"
    echo ""
    
    echo -e "${WHITE}BACKUP E SEGURANÇA:${NC}"
    echo "  - Backups automáticos configuráveis via cron"
    echo "  - SSL gratuito com Let's Encrypt"
    echo "  - Firewall configurado automaticamente"
    echo "  - Logs de auditoria em $LOG_FILE"
    echo ""
    
    echo -e "${WHITE}SUPORTE A FRAMEWORKS:${NC}"
    echo "  - Laravel (com Composer)"
    echo "  - WordPress"
    echo "  - PHP genérico"
    echo "  - Sites estáticos"
    echo ""
    
    echo -e "${YELLOW}Para mais informações, consulte os logs do sistema em $LOG_FILE${NC}"
    echo ""
    
    read -p "Pressione Enter para continuar..."
}

# Menu de cache (Redis/Memcached)
manage_cache() {
    while true; do
        clear
        show_header
        echo -e "${WHITE}┌─ GERENCIAR CACHE (Redis/Memcached) ──────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}1.${NC} Status dos Serviços de Cache                                          ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}2.${NC} Limpar Cache Redis                                                    ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}3.${NC} Limpar Cache Memcached                                                ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}4.${NC} Estatísticas Redis                                                    ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}5.${NC} Estatísticas Memcached                                                ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}6.${NC} Configurar Redis                                                      ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}7.${NC} Configurar Memcached                                                  ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}0.${NC} Voltar ao Menu Principal                                              ${WHITE}│${NC}"
        echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
        
        case $choice in
            1) cache_status ;;
            2) clear_redis_cache ;;
            3) clear_memcached_cache ;;
            4) redis_stats ;;
            5) memcached_stats ;;
            6) configure_redis ;;
            7) configure_memcached ;;
            0) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 2 ;;
        esac
    done
}

# Status dos serviços de cache
cache_status() {
    echo ""
    echo -e "${CYAN}═══ STATUS DOS SERVIÇOS DE CACHE ═══${NC}"
    echo ""
    
    # Redis
    case $OS in
        "oracle"|"rhel") redis_service="redis" ;;
        "ubuntu"|"debian") redis_service="redis-server" ;;
    esac
    
    if systemctl is-active "$redis_service" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Redis: ATIVO${NC}"
        if command -v redis-cli >/dev/null 2>&1; then
            redis_info=$(redis-cli info server | grep redis_version | cut -d: -f2)
            echo "   Versão: $redis_info"
        fi
    else
        echo -e "${RED}❌ Redis: INATIVO${NC}"
    fi
    
    # Memcached
    if systemctl is-active memcached >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Memcached: ATIVO${NC}"
    else
        echo -e "${RED}❌ Memcached: INATIVO${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}Portas de cache em uso:${NC}"
    netstat -tlnp 2>/dev/null | grep -E ':6379|:11211'
    
    read -p "Pressione Enter para continuar..."
}

# Limpar cache Redis
clear_redis_cache() {
    echo ""
    if command -v redis-cli >/dev/null 2>&1; then
        echo -e "${YELLOW}Limpando cache Redis...${NC}"
        redis-cli FLUSHALL
        echo -e "${GREEN}Cache Redis limpo!${NC}"
        log_action "Cache Redis limpo"
    else
        echo -e "${RED}Redis não está instalado ou não está funcionando${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Limpar cache Memcached
clear_memcached_cache() {
    echo ""
    if systemctl is-active memcached >/dev/null 2>&1; then
        echo -e "${YELLOW}Limpando cache Memcached...${NC}"
        echo "flush_all" | nc localhost 11211
        echo -e "${GREEN}Cache Memcached limpo!${NC}"
        log_action "Cache Memcached limpo"
    else
        echo -e "${RED}Memcached não está instalado ou não está funcionando${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Estatísticas Redis
redis_stats() {
    echo ""
    if command -v redis-cli >/dev/null 2>&1; then
        echo -e "${CYAN}═══ ESTATÍSTICAS REDIS ═══${NC}"
        redis-cli info stats
    else
        echo -e "${RED}Redis não disponível${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Estatísticas Memcached
memcached_stats() {
    echo ""
    if systemctl is-active memcached >/dev/null 2>&1; then
        echo -e "${CYAN}═══ ESTATÍSTICAS MEMCACHED ═══${NC}"
        echo "stats" | nc localhost 11211
    else
        echo -e "${RED}Memcached não disponível${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Configurar Redis
configure_redis() {
    echo ""
    echo -e "${YELLOW}Configurando Redis...${NC}"
    
    redis_conf="/etc/redis/redis.conf"
    [[ ! -f "$redis_conf" ]] && redis_conf="/etc/redis.conf"
    
    if [[ -f "$redis_conf" ]]; then
        echo "Editando $redis_conf"
        nano "$redis_conf"
        
        systemctl restart redis 2>/dev/null || systemctl restart redis-server 2>/dev/null
        echo -e "${GREEN}Redis reiniciado!${NC}"
    else
        echo -e "${RED}Arquivo de configuração do Redis não encontrado${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Configurar Memcached
configure_memcached() {
    echo ""
    echo -e "${YELLOW}Configurando Memcached...${NC}"
    
    memcached_conf="/etc/memcached.conf"
    [[ ! -f "$memcached_conf" ]] && memcached_conf="/etc/sysconfig/memcached"
    
    if [[ -f "$memcached_conf" ]]; then
        echo "Editando $memcached_conf"
        nano "$memcached_conf"
        
        systemctl restart memcached
        echo -e "${GREEN}Memcached reiniciado!${NC}"
    else
        echo -e "${RED}Arquivo de configuração do Memcached não encontrado${NC}"
    fi
    
    read -p "Pressione Enter para continuar..."
}

# Ferramentas do sistema
system_tools_menu() {
    while true; do
        clear
        show_header
        echo -e "${WHITE}┌─ FERRAMENTAS DO SISTEMA ─────────────────────────────────────────────────────┐${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}1.${NC} Monitor de Recursos (htop)                                            ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}2.${NC} Análise de Disco (ncdu)                                               ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}3.${NC} Monitor de Rede (nethogs)                                             ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}4.${NC} Monitor de I/O (iotop)                                                ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}5.${NC} Informações do Hardware                                               ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}6.${NC} Teste de Conectividade                                                ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}7.${NC} Editor de Arquivos (nano)                                             ${WHITE}│${NC}"
        echo -e "${WHITE}│${NC}  ${GREEN}0.${NC} Voltar ao Menu Principal                                              ${WHITE}│${NC}"
        echo -e "${WHITE}└──────────────────────────────────────────────────────────────────────────────┘${NC}"
        echo ""
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção: "${NC})" choice
        
        case $choice in
            1) 
                command -v htop >/dev/null 2>&1 && htop || echo "htop não instalado. Use: install_package htop"
                ;;
            2) 
                command -v ncdu >/dev/null 2>&1 && ncdu / || echo "ncdu não instalado. Use: install_package ncdu"
                ;;
            3) 
                command -v nethogs >/dev/null 2>&1 && nethogs || echo "nethogs não instalado. Use: install_package nethogs"
                ;;
            4) 
                command -v iotop >/dev/null 2>&1 && iotop || echo "iotop não instalado. Use: install_package iotop"
                ;;
            5) show_hardware_info ;;
            6) connectivity_test ;;
            7) 
                echo "Qual arquivo deseja editar?"
                read -p "Caminho completo: " file_path
                [[ -n "$file_path" ]] && nano "$file_path"
                ;;
            0) break ;;
            *) echo -e "${RED}Opção inválida!${NC}"; sleep 2 ;;
        esac
    done
}

# Informações do hardware
show_hardware_info() {
    echo ""
    echo -e "${CYAN}═══ INFORMAÇÕES DO HARDWARE ═══${NC}"
    echo ""
    
    echo -e "${WHITE}CPU:${NC}"
    lscpu | grep -E "Model name|CPU\(s\)|Thread|Core"
    echo ""
    
    echo -e "${WHITE}Memória:${NC}"
    free -h
    echo ""
    
    echo -e "${WHITE}Disco:${NC}"
    df -h
    echo ""
    
    echo -e "${WHITE}Rede:${NC}"
    ip addr show | grep -E "^[0-9]|inet " | head -6
    
    read -p "Pressione Enter para continuar..."
}

# Teste de conectividade
connectivity_test() {
    echo ""
    echo -e "${CYAN}═══ TESTE DE CONECTIVIDADE ═══${NC}"
    echo ""
    
    # Teste interno
    echo -e "${BLUE}Testando conectividade local...${NC}"
    curl -s localhost >/dev/null && echo -e "${GREEN}✅ Localhost OK${NC}" || echo -e "${RED}❌ Localhost ERRO${NC}"
    
    # Teste externo
    echo -e "${BLUE}Testando conectividade externa...${NC}"
    ping -c 2 8.8.8.8 >/dev/null 2>&1 && echo -e "${GREEN}✅ Internet OK${NC}" || echo -e "${RED}❌ Internet ERRO${NC}"
    
    # Teste DNS
    echo -e "${BLUE}Testando resolução DNS...${NC}"
    nslookup google.com >/dev/null 2>&1 && echo -e "${GREEN}✅ DNS OK${NC}" || echo -e "${RED}❌ DNS ERRO${NC}"
    
    # Portas do servidor
    echo ""
    echo -e "${BLUE}Portas abertas no servidor:${NC}"
    netstat -tlnp 2>/dev/null | grep LISTEN | head -5
    
    read -p "Pressione Enter para continuar..."
}

# Menu principal
main_menu() {
    while true; do
        show_header
        show_status
        show_main_menu
        
        read -p "$(echo -e ${YELLOW}"Escolha uma opção (0-19): "${NC})" choice
        
        case $choice in
            1) manage_domains ;;
            2) manage_projects ;;
            3) manage_php ;;
            4) manage_mysql ;;
            5) manage_services ;;
            6) manage_backup ;;
            7) manage_maintenance ;;
            8) install_software_menu ;;
            9) manage_cache ;;
            10) system_tools_menu ;;
            11) show_web_stats ;;
            12) system_monitor ;;
            13) 
                echo "Funcionalidade SSL integrada no gerenciamento de domínios (opção 1 -> 5)"
                sleep 2
                ;;
            14) 
                echo "Funcionalidade de segurança integrada na manutenção (opção 7 -> 7)"
                sleep 2
                ;;
            15)
                echo "Logs disponíveis no gerenciamento de serviços (opção 5 -> 7)"
                sleep 2
                ;;
            16)
                echo "Configurações disponíveis nos menus específicos de cada serviço"
                sleep 2
                ;;
            17)
                echo "Monitor de temperatura não implementado para Oracle Cloud"
                sleep 2
                ;;
            18)
                echo -e "${YELLOW}Executando atualização do sistema...${NC}"
                update_system_universal
                read -p "Pressione Enter para continuar..."
                ;;
            19) show_documentation ;;
            88) 
                echo -e "${YELLOW}Executando configuração inicial...${NC}"
                initial_setup
                read -p "Pressione Enter para continuar..."
                ;;
            99)
                echo ""
                echo -e "${CYAN}═══ INFORMAÇÕES DO SISTEMA ═══${NC}"
                echo "OS: $OS"
                echo "Versão: $OS_VERSION" 
                echo "Gerenciador de Pacotes: $PKG_MANAGER"
                echo "Usuário Web: $WEB_USER"
                echo "Serviço Web: $WEB_SERVICE"
                echo "Serviço PHP: $PHP_SERVICE"
                echo "Serviço MySQL: $MYSQL_SERVICE"
                echo "Firewall: $FIREWALL_SERVICE"
                echo "Script Version: $SCRIPT_VERSION"
                echo ""
                read -p "Pressione Enter para continuar..."
                ;;
            0) 
                echo -e "${GREEN}Saindo do Web Admin...${NC}"
                log_action "Sistema admin finalizado"
                exit 0
                ;;
            *)
                echo -e "${RED}Opção inválida! Tente novamente.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Verificar se está sendo executado como root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Este script deve ser executado como root (use sudo)${NC}"
   echo "Exemplo: sudo bash $0"
   exit 1
fi

# Verificar conectividade básica
if ! curl -s --connect-timeout 5 ifconfig.me >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Aviso: Sem conectividade com a internet. Algumas funcionalidades podem ser limitadas.${NC}"
    sleep 2
fi

# Inicialização
echo -e "${CYAN}🔍 Detectando sistema operacional Oracle Cloud...${NC}"
detect_os

# Criar arquivo de log se não existir
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
log_action "Sistema admin iniciado - $OS $OS_VERSION"

# Verificar primeira execução
first_run_check

echo -e "${GREEN}✅ Sistema Web Admin $SCRIPT_VERSION iniciado com sucesso!${NC}"
sleep 2

# Executar menu principal
main_menu