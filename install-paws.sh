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
  if has_tty; then
    read -r -p "$msg [$def]: " val < /dev/tty || true
  fi
  echo "${val:-$def}"
}

prompt_secret(){
  local msg="$1" val=""
  if has_tty; then
    read -r -s -p "$msg: " val < /dev/tty || true
    echo > /dev/tty
  fi
  echo "$val"
}

require_root(){
  [ "${EUID:-$(id -u)}" -eq 0 ] || fail "Pokreni kao root ili sudo."
}

detect_os(){
  if [ -f /etc/os-release ]; then
    . /etc/os-release
  else
    fail "Nepoznat OS."
  fi
}

install_docker(){
  detect_os
  case "${ID:-}" in
    ubuntu|debian)
      log "Docker nije pronađen. Instaliram Docker i Docker Compose plugin..."
      apt-get update
      apt-get install -y ca-certificates curl gnupg

      install -m 0755 -d /etc/apt/keyrings
      if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        curl -fsSL "https://download.docker.com/linux/$ID/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg
      fi

      echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$ID ${VERSION_CODENAME} stable" \
      > /etc/apt/sources.list.d/docker.list

      apt-get update
      apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
      systemctl enable docker
      systemctl start docker
      ;;
    *)
      fail "Automatska instalacija Docker-a podržana je samo za Ubuntu/Debian."
      ;;
  esac
}

ensure_docker(){
  command -v docker >/dev/null 2>&1 || install_docker
  docker compose version >/dev/null 2>&1 || fail "Docker Compose plugin nije dostupan."
}

validate_port(){
  local port="$1"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

validate_ip(){
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

choose_auth_type(){
  local choice

  if has_tty; then
    echo "" > /dev/tty
    echo "Odaberite AuthType:" > /dev/tty
    echo "  1) atNone  - bez autentikacije" > /dev/tty
    echo "  2) atToken - token autentikacija" > /dev/tty
    echo "  3) atUser  - user autentikacija" > /dev/tty
    echo "Preporuka: ako niste sigurni, odaberite 2 (atToken)" > /dev/tty
  fi

  read -r -p "Odabir [2]: " choice < /dev/tty || true
  choice="${choice:-2}"

  case "$choice" in
    1) echo "atNone" ;;
    2) echo "atToken" ;;
    3) echo "atUser" ;;
    *) echo "atToken" ;;
  esac
}

write_compose(){
  local app_dir="$1"
  local image="$2"
  local bind_ip="$3"
  local port="$4"

  cat > "$app_dir/docker-compose.yml" <<EOF_COMPOSE
services:
  paws-api:
    image: $image
    container_name: $APP_NAME
    restart: unless-stopped
    ports:
      - "$bind_ip:$port:8080"
    environment:
      ASPNETCORE_ENVIRONMENT: Production
    volumes:
      - ./appsettings.json:/app/appsettings.json:ro
      - ./keys:/root/.aspnet/DataProtection-Keys
EOF_COMPOSE
}

write_single_db_json(){
  local file="$1"
  local data_source="$2"
  local db_name="$3"
  local pantheon_user="$4"
  local pantheon_pass="$5"
  local auth_type="$6"

  local padb="Data Source=${data_source};Initial Catalog=${db_name};User ID=${pantheon_user};Password=${pantheon_pass};MultipleActiveResultSets=True;App=EntityFramework;TrustServerCertificate=True;Encrypt=False;"

  cat > "$file" <<EOF_JSON
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
    "PADBContext": "$padb",
    "HostsConnection": ""
  },
  "AppSettings": {
    "Secret": "y3j4ryu68ki7%rOIJt61&h3df1ghw6/keiw983nd9a2o4j2n5b6769vbd54cujhJF_+FYDfg)hshfku65i7bhf",
    "ProtectEnthropy": "12345678901234567890123456789012",
    "AuthType": "$auth_type",
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
}

write_host_mode_json(){
  local file="$1"
  local data_source="$2"
  local client_db="$3"
  local pantheon_user="$4"
  local pantheon_pass="$5"
  local sql_user="$6"
  local sql_pass="$7"
  local auth_type="$8"

  local padb="Data Source=${data_source};Initial Catalog=${client_db};User ID=${pantheon_user};Password=${pantheon_pass};MultipleActiveResultSets=True;App=EntityFramework;TrustServerCertificate=True;Encrypt=False;"
  local hosts="Data Source=${data_source};Initial Catalog=PAW_Master;User ID=${sql_user};Password=${sql_pass};TrustServerCertificate=True;Encrypt=False;"

  cat > "$file" <<EOF_JSON
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
    "PADBContext": "$padb",
    "HostsConnection": "$hosts"
  },
  "AppSettings": {
    "Secret": "y3j4ryu68ki7%rOIJt61&h3df1ghw6/keiw983nd9a2o4j2n5b6769vbd54cujhJF_+FYDfg)hshfku65i7bhf",
    "ProtectEnthropy": "12345678901234567890123456789012",
    "AuthType": "$auth_type",
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
}

validate_json() {
  local file="$1"

  if command -v python3 >/dev/null 2>&1; then
    log "Validiram appsettings.json"
    if ! python3 -m json.tool "$file" >/dev/null 2>&1; then
      fail "appsettings.json nije validan JSON. Instalacija prekinuta."
    fi
  else
    log "Upozorenje: python3 nije pronađen, JSON validacija je preskočena."
  fi
}

sanity_check_json() {
  local file="$1"

  grep -q '"PADBContext": "' "$file" || fail "PADBContext nije pronađen u appsettings.json"
  grep -q '"AuthType": "' "$file" || fail "AuthType nije pronađen u appsettings.json"
  grep -q '"CustomCrypt": 1' "$file" || fail "CustomCrypt nije postavljen na 1"
}

main(){
  require_root
  ensure_docker

  local install_dir image port bind_choice bind_ip
  local db_mode auth_type sql_host sql_port data_source
  local client_db pantheon_user pantheon_pass sql_user sql_pass
  local overwrite

  install_dir="$(prompt "Install folder" "$DEFAULT_INSTALL_DIR")"
  image="$(prompt "Docker image" "$DEFAULT_IMAGE")"

  while true; do
    port="$(prompt "Port" "8090")"
    if validate_port "$port"; then break; fi
    echo "Unesite validan port 1-65535."
  done

  echo
  echo "Način pristupa:"
  echo "  1) Localhost only (127.0.0.1) - preporučeno za Cloudflare / reverse proxy"
  echo "  2) Private IP adresa - LAN / VPN / Tailscale"
  bind_choice="$(prompt "Odaberite opciju" "1")"

  case "$bind_choice" in
    2)
      while true; do
        bind_ip="$(prompt "Unesite private IP adresu servera" "192.168.1.10")"
        if validate_ip "$bind_ip"; then break; fi
        echo "Unesite validnu IPv4 adresu."
      done
      ;;
    *)
      bind_ip="127.0.0.1"
      ;;
  esac

  echo
  echo "Odaberite način rada baze:"
  echo
  echo "  1) Single database (Default catalog)"
  echo "     Koristite ovu opciju ako API radi samo sa jednom bazom."
  echo "     Primjer: jedan klijent, jedna baza."
  echo
  echo "  2) Multi-tenant (Host mode)"
  echo "     Koristite ovu opciju ako postoji centralni PAW_Master i više klijenata/baza."
  echo "     Potreban je SQL user za HostsConnection i Pantheon user za PADBContext."
  echo "     Pantheon user se mora barem jednom prijaviti u Pantheon prije korištenja API-a."
  echo
  echo "Preporuka: ako niste sigurni, odaberite 1."
  db_mode="$(prompt "Odaberite opciju" "1")"

  auth_type="$(choose_auth_type)"

  while true; do
    sql_host="$(prompt "SQL host/IP" "127.0.0.1")"
    [ -n "$sql_host" ] && break
  done

  while true; do
    sql_port="$(prompt "SQL port" "1433")"
    if validate_port "$sql_port"; then break; fi
    echo "Unesite validan port 1-65535."
  done

  data_source="${sql_host},${sql_port}"

  mkdir -p "$install_dir"
  mkdir -p "$install_dir/keys"

  if [ -f "$install_dir/appsettings.json" ]; then
    overwrite="$(prompt "Postojeći appsettings.json postoji. Overwrite? (y/N)" "N")"
  else
    overwrite="Y"
  fi

  if [[ "$overwrite" =~ ^[Yy]$ ]]; then
    if [ "$db_mode" = "2" ]; then
      client_db="$(prompt "Klijentska baza (PADBContext Initial Catalog)" "BA_UNITIC")"
      pantheon_user="$(prompt "Pantheon user (za PADBContext)" "PAWS")"
      pantheon_pass="$(prompt_secret "Pantheon password")"
      sql_user="$(prompt "SQL user (za HostsConnection / PAW_Master)" "sa")"
      sql_pass="$(prompt_secret "SQL password")"

      write_host_mode_json \
        "$install_dir/appsettings.json" \
        "$data_source" \
        "$client_db" \
        "$pantheon_user" \
        "$pantheon_pass" \
        "$sql_user" \
        "$sql_pass" \
        "$auth_type"
    else
      client_db="$(prompt "Database / Default catalog" "BA_UNITIC")"
      pantheon_user="$(prompt "Pantheon user" "PAWS")"
      pantheon_pass="$(prompt_secret "Pantheon password")"

      write_single_db_json \
        "$install_dir/appsettings.json" \
        "$data_source" \
        "$client_db" \
        "$pantheon_user" \
        "$pantheon_pass" \
        "$auth_type"
    fi

    chmod 600 "$install_dir/appsettings.json"
    log "appsettings.json generisan"
  else
    log "Postojeći appsettings.json je zadržan"
  fi

  write_compose "$install_dir" "$image" "$bind_ip" "$port"

  log "Pull image"
  docker pull "$image"

  log "Uklanjam stari container ako postoji"
  docker rm -f "$APP_NAME" >/dev/null 2>&1 || true

  log "Dižem PAWS API"
  cd "$install_dir"
  docker compose up -d

  echo
  log "Instalacija završena"
  echo "Folder: $install_dir"
  echo "Image:  $image"
  echo "Bind:   $bind_ip:$port -> 8080"
  echo "Data Source: $data_source"
  echo "AuthType: $auth_type"
  echo
  echo "Korisne komande:"
  echo "  cd $install_dir && docker compose logs -f"
  echo "  cd $install_dir && docker compose restart"
  echo "  cd $install_dir && docker compose down"
  echo "  curl http://127.0.0.1:$port/swagger/v1/swagger.json"
}

main "$@"


chmod +x /opt/paws-api/dist/install-paws.sh