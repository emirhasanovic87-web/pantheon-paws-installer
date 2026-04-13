#!/usr/bin/env bash
set -euo pipefail

APP_NAME="paws-api"
DEFAULT_IMAGE="emirhasanovic/paws-api:10.47.10"
DEFAULT_INSTALL_DIR="/opt/paws-api"

log() {
  echo "==> $1"
}

fail() {
  echo "ERROR: $1" >&2
  exit 1
}

require_root() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    fail "Pokreni skriptu kao root ili sa sudo."
  fi
}

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION_CODENAME="${VERSION_CODENAME:-}"
  else
    OS_ID="unknown"
    OS_VERSION_CODENAME=""
  fi
}

install_docker_debian() {
  log "Docker nije pronađen. Instaliram Docker i Docker Compose plugin..."

  apt-get update
  apt-get install -y ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings

  if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
    curl -fsSL "https://download.docker.com/linux/${OS_ID}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  cat > /etc/apt/sources.list.d/docker.list <<EOF_APT
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS_ID} ${OS_VERSION_CODENAME} stable
EOF_APT

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable docker
  systemctl start docker
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    detect_os
    case "$OS_ID" in
      ubuntu|debian)
        install_docker_debian
        ;;
      *)
        fail "Automatska instalacija Docker-a podržana je samo za Ubuntu/Debian."
        ;;
    esac
  fi

  if ! docker compose version >/dev/null 2>&1; then
    detect_os
    case "$OS_ID" in
      ubuntu|debian)
        log "Docker Compose plugin nije pronađen. Instaliram..."
        apt-get update
        apt-get install -y docker-compose-plugin
        ;;
      *)
        fail "Docker Compose plugin nije instaliran."
        ;;
    esac
  fi
}

prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local value
  read -r -p "$prompt [$default]: " value
  if [ -z "$value" ]; then
    echo "$default"
  else
    echo "$value"
  fi
}

validate_port() {
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

validate_ip() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

write_appsettings_if_missing() {
  local app_dir="$1"
  if [ ! -f "$app_dir/appsettings.json" ]; then
    log "appsettings.json ne postoji. Kreiram template."
    cat > "$app_dir/appsettings.json" <<'EOF_JSON'
{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft": "Warning",
      "Microsoft.Hosting.Lifetime": "Information"
    }
  },
  "AllowedHosts": "*",
  "ConnectionStrings": {
    "PADBContext": "Server=SQL_IP,PORT;Database=DB_NAME;User ID=SQL_USER;Password=SQL_PASSWORD;MultipleActiveResultSets=True;TrustServerCertificate=True;Encrypt=False"
  },
  "AppSettings": {
    "Secret": "CHANGE_ME",
    "ProtectEnthropy": "12345678901234567890123456789012",
    "AuthType": "atNone",
    "TokenExpiresMinutes": 5,
    "CookieExpiresMinutes": 5,
    "ThrowExceptionOnEmptyResultSets": false,
    "CustomCrypt": 1,
    "CompanyDB": "",
    "MoveTransactionTimeoutMinutes": 5,
    "OrderTransactionTimeoutMinutes": 5,
    "TrustServerCertificate": true,
    "AllowDBOnlyFromGeneratedToken": 0
  }
}
EOF_JSON
    log "Template appsettings.json kreiran. Provjeri i unesi stvarne vrijednosti."
  fi
}

write_compose() {
  local app_dir="$1"
  local image_name="$2"
  local bind_ip="$3"
  local host_port="$4"

  cat > "$app_dir/docker-compose.yml" <<EOF_COMPOSE
services:
  paws-api:
    image: $image_name
    container_name: $APP_NAME
    restart: unless-stopped
    ports:
      - "$bind_ip:$host_port:8080"
    environment:
      ASPNETCORE_ENVIRONMENT: Production
    volumes:
      - ./appsettings.json:/app/appsettings.json:ro
      - ./keys:/root/.aspnet/DataProtection-Keys
EOF_COMPOSE
}

main() {
  require_root
  ensure_docker

  local install_dir image_name port bind_choice bind_ip docker_login_choice docker_username

  install_dir="$(prompt_with_default 'Install folder' "$DEFAULT_INSTALL_DIR")"
  image_name="$(prompt_with_default 'Docker image' "$DEFAULT_IMAGE")"

  while true; do
    port="$(prompt_with_default 'Koji port želite koristiti' '8090')"
    if validate_port "$port"; then
      break
    fi
    echo "Unesite validan port 1-65535."
  done

  echo
  echo "Način pristupa:"
  echo "  1) Localhost only (127.0.0.1) - preporučeno za Cloudflare / reverse proxy"
  echo "  2) Private IP adresa - LAN / VPN / Tailscale"
  read -r -p "Odaberite opciju [1]: " bind_choice
  bind_choice="${bind_choice:-1}"

  case "$bind_choice" in
    1)
      bind_ip="127.0.0.1"
      ;;
    2)
      while true; do
        bind_ip="$(prompt_with_default 'Unesite private IP adresu servera' '100.x.x.x')"
        if validate_ip "$bind_ip"; then
          break
        fi
        echo "Unesite validnu IPv4 adresu."
      done
      ;;
    *)
      bind_ip="127.0.0.1"
      ;;
  esac

  read -r -p "Treba li docker login prije pull-a? (y/N): " docker_login_choice
  docker_login_choice="${docker_login_choice:-N}"

  mkdir -p "$install_dir"
  mkdir -p "$install_dir/keys"

  write_appsettings_if_missing "$install_dir"
  write_compose "$install_dir" "$image_name" "$bind_ip" "$port"

  if [[ "$docker_login_choice" =~ ^[Yy]$ ]]; then
    docker_username="$(prompt_with_default 'Docker username' 'emirhasanovic')"
    docker login -u "$docker_username"
  fi

  log "Pullam image: $image_name"
  docker pull "$image_name"

  log "Uklanjam stari container ako postoji"
  docker rm -f "$APP_NAME" >/dev/null 2>&1 || true

  log "Dižem PAWS API"
  cd "$install_dir"
  docker compose up -d

  echo
  log "Instalacija završena"
  echo "Folder: $install_dir"
  echo "Image:  $image_name"
  echo "Bind:   $bind_ip:$port -> 8080"
  echo
  echo "Korisne komande:"
  echo "  cd $install_dir && docker compose logs -f"
  echo "  cd $install_dir && docker compose restart"
  echo "  cd $install_dir && docker compose down"
  echo "  curl http://127.0.0.1:$port/swagger/v1/swagger.json"
  echo
  echo "Napomena: provjeri appsettings.json prije produkcijske upotrebe."
}

main "$@"
