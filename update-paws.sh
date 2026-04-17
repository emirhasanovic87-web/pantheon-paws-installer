#!/usr/bin/env bash
set -euo pipefail

DEFAULT_INSTALL_DIR="/opt/paws-api"
DEFAULT_IMAGE="emirhasanovic/paws-api:10.47.10"

log() { echo "==> $1"; }
warn() { echo "WARN: $1"; }
fail() { echo "ERROR: $1" >&2; exit 1; }

has_tty() { [ -r /dev/tty ]; }

prompt() {
  local msg="$1" def="$2" val=""
  if has_tty; then
    read -r -p "$msg [$def]: " val < /dev/tty || true
  fi
  echo "${val:-$def}"
}

require_root() {
  [ "${EUID:-$(id -u)}" -eq 0 ] || fail "Pokreni kao root ili sudo."
}

ensure_docker() {
  command -v docker >/dev/null 2>&1 || fail "Docker nije instaliran."
  docker compose version >/dev/null 2>&1 || fail "Docker Compose plugin nije dostupan."
}

extract_current_image() {
  local compose_file="$1"
  awk '/image:/ {print $2; exit}' "$compose_file"
}

extract_current_port() {
  local compose_file="$1"
  awk -F: '/published:|ports:/ {found=1} found && /published:/ {gsub(/[" ]/, "", $2); print $2; exit}' "$compose_file" || true
}

update_compose_image() {
  local compose_file="$1"
  local new_image="$2"
  sed -i -E "s|(^[[:space:]]*image:[[:space:]]*).*$|\1${new_image}|" "$compose_file"
}

validate_json() {
  local file="$1"
  if command -v python3 >/dev/null 2>&1; then
    log "Validiram appsettings.json"
    python3 -m json.tool "$file" >/dev/null 2>&1 || fail "appsettings.json nije validan JSON."
  else
    warn "python3 nije pronađen, JSON validacija je preskočena."
  fi
}

sanity_check_json() {
  local file="$1"
  grep -q '"PADBContext": "' "$file" || fail "PADBContext nije pronađen u appsettings.json"
  grep -q '"AuthType": "' "$file" || fail "AuthType nije pronađen u appsettings.json"
  grep -q '"CustomCrypt": 1' "$file" || fail "CustomCrypt nije postavljen na 1"

  if grep -q '"AuthType": "atToken"' "$file"; then
    if grep -q '"HostsConnection": ""' "$file"; then
      fail "AuthType=atToken, ali je HostsConnection prazan. Popravi appsettings.json prije update-a."
    fi
  fi
}

main() {
  require_root
  ensure_docker

  local install_dir compose_file appsettings_file backup_dir backup_ts current_image new_image current_port

  install_dir="$(prompt "Install folder" "$DEFAULT_INSTALL_DIR")"
  compose_file="$install_dir/docker-compose.yml"
  appsettings_file="$install_dir/appsettings.json"

  [ -d "$install_dir" ] || fail "Folder ne postoji: $install_dir"
  [ -f "$compose_file" ] || fail "docker-compose.yml ne postoji u: $install_dir"
  [ -f "$appsettings_file" ] || fail "appsettings.json ne postoji u: $install_dir"

  validate_json "$appsettings_file"
  sanity_check_json "$appsettings_file"

  current_image="$(extract_current_image "$compose_file")"
  current_image="${current_image:-$DEFAULT_IMAGE}"
  current_port="$(extract_current_port "$compose_file")"
  current_port="${current_port:-8090}"

  echo
  echo "Trenutni image: $current_image"
  echo "Trenutni port:  $current_port"

  new_image="$(prompt "Novi image" "$current_image")"

  backup_ts="$(date +%Y%m%d_%H%M%S)"
  backup_dir="$install_dir/backup_$backup_ts"
  mkdir -p "$backup_dir"

  log "Backup postojećih fajlova"
  cp "$compose_file" "$backup_dir/docker-compose.yml.bak"
  cp "$appsettings_file" "$backup_dir/appsettings.json.bak"

  log "Pullam image: $new_image"
  docker pull "$new_image"

  log "Ažuriram docker-compose.yml"
  update_compose_image "$compose_file" "$new_image"

  log "Redeploy PAWS API"
  cd "$install_dir"
  docker compose up -d

  sleep 3

  if ! docker ps --format '{{.Names}}' | grep -qx 'paws-api'; then
    warn "Container nije aktivan nakon update-a. Prikazujem zadnje logove:"
    docker compose logs --tail=100
    fail "Update nije uspješan."
  fi

  echo
  log "Update završen"
  echo "Folder: $install_dir"
  echo "Image:  $new_image"
  echo "Port:   $current_port"
  echo "Backup: $backup_dir"
  echo
  echo "Korisne komande:"
  echo "  cd $install_dir && docker compose logs -f"
  echo "  cd $install_dir && docker compose ps"
  echo "  cd $install_dir && docker compose restart"
  echo "  curl http://127.0.0.1:$current_port/swagger/v1/swagger.json"
}

main "$@"