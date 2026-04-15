#!/usr/bin/env bash
set -euo pipefail

APP_NAME="paws-api"
DEFAULT_IMAGE="emirhasanovic/paws-api:10.47.10"
DEFAULT_INSTALL_DIR="/opt/paws-api"

log(){ echo "==> $1"; }
fail(){ echo "ERROR: $1" >&2; exit 1; }

has_tty(){ [ -r /dev/tty ]; }

prompt(){
  local msg="$1" def="$2" val=""
  if has_tty; then read -r -p "$msg [$def]: " val < /dev/tty || true; fi
  echo "${val:-$def}"
}

prompt_secret(){
  local msg="$1" val=""
  if has_tty; then
    read -r -s -p "$msg: " val < /dev/tty || true
    echo
  fi
  echo "$val"
}

require_root(){
  [ "${EUID:-$(id -u)}" -eq 0 ] || fail "Pokreni kao root ili sudo"
}

detect_os(){
  . /etc/os-release
}

install_docker(){
  detect_os
  case "$ID" in
    ubuntu|debian)
      log "Instaliram Docker..."
      apt-get update
      apt-get install -y ca-certificates curl gnupg

      install -m 0755 -d /etc/apt/keyrings
      curl -fsSL https://download.docker.com/linux/$ID/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      chmod a+r /etc/apt/keyrings/docker.gpg

      echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID $VERSION_CODENAME stable" \
> /etc/apt/sources.list.d/docker.list

      apt-get update
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
      systemctl enable docker
      systemctl start docker
    ;;
    *) fail "Podržani su Ubuntu/Debian";;
  esac
}

ensure_docker(){
  command -v docker >/dev/null || install_docker
  docker compose version >/dev/null || apt-get install -y docker-compose-plugin
}

write_compose(){
  cat > "$1/docker-compose.yml" <<EOF_COMPOSE
services:
  paws-api:
    image: $2
    container_name: $APP_NAME
    restart: unless-stopped
    ports:
      - "$3:$4:8080"
    environment:
      ASPNETCORE_ENVIRONMENT: Production
    volumes:
      - ./appsettings.json:/app/appsettings.json:ro
      - ./keys:/root/.aspnet/DataProtection-Keys
EOF_COMPOSE
}

main(){
  require_root
  ensure_docker

  install_dir=$(prompt "Install folder" "$DEFAULT_INSTALL_DIR")
  image=$(prompt "Docker image" "$DEFAULT_IMAGE")

  port=$(prompt "Port" "8090")

  echo
  echo "Način pristupa:"
  echo "1) Localhost (preporučeno za Cloudflare)"
  echo "2) Private IP (LAN/VPN/Tailscale)"
  bind_choice=$(prompt "Odabir" "1")

  if [ "$bind_choice" = "2" ]; then
    bind_ip=$(prompt "Private IP" "192.168.1.10")
  else
    bind_ip="127.0.0.1"
  fi

  echo
  echo "Odaberite način rada baze:"
  echo
  echo "1) Single database (Default catalog)"
  echo "   → jedna baza (najčešći slučaj)"
  echo
  echo "2) Multi-tenant (Host mode)"
  echo "   → centralna baza + više klijenata"
  echo
  echo "Preporuka: ako niste sigurni, odaberite 1"
  db_mode=$(prompt "Odabir" "1")

  sql_host=$(prompt "SQL host" "127.0.0.1")
  sql_port=$(prompt "SQL port" "1433")

  if [ "$db_mode" = "2" ]; then
    db_name=$(prompt "Master DB (PAW_Master)" "PAW_Master")
  else
    db_name=$(prompt "Database (Default catalog)" "BA_UNITIC")
  fi

  sql_user=$(prompt "SQL username" "sa")
  sql_pass=$(prompt_secret "SQL password")

  mkdir -p "$install_dir"
  mkdir -p "$install_dir/keys"

  if [ -f "$install_dir/appsettings.json" ]; then
    overwrite=$(prompt "Postojeći config postoji. Overwrite? (y/N)" "N")
  else
    overwrite="Y"
  fi

  if [[ "$overwrite" =~ ^[Yy]$ ]]; then

    if [ "$db_mode" = "2" ]; then
      conn="Server=$sql_host,$sql_port;Database=$db_name;User ID=$sql_user;Password=$sql_pass;TrustServerCertificate=True;Encrypt=False"
      cat > "$install_dir/appsettings.json" <<EOF_JSON
{
  "ConnectionStrings": {
    "PADBContext": "$conn",
    "HostsConnection": "$conn"
  },
  "AppSettings": {
    "CustomCrypt": 1
  }
}
EOF_JSON
    else
      conn="Server=$sql_host,$sql_port;Database=$db_name;User ID=$sql_user;Password=$sql_pass;TrustServerCertificate=True;Encrypt=False"
      cat > "$install_dir/appsettings.json" <<EOF_JSON
{
  "ConnectionStrings": {
    "PADBContext": "$conn"
  },
  "AppSettings": {
    "CustomCrypt": 1
  }
}
EOF_JSON
    fi

    chmod 600 "$install_dir/appsettings.json"
    log "appsettings.json generisan"
  fi

  write_compose "$install_dir" "$image" "$bind_ip" "$port"

  log "Pull image"
  docker pull "$image"

  docker rm -f $APP_NAME >/dev/null 2>&1 || true

  cd "$install_dir"
  docker compose up -d

  echo
  log "Instalacija završena"
  echo "Bind: $bind_ip:$port"
}

main "$@"
chmod +x /opt/paws-api/dist/install-paws.sh