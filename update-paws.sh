#!/usr/bin/env bash
set -euo pipefail

DEFAULT_INSTALL_DIR="/opt/paws-api"
DEFAULT_IMAGE="emirhasanovic/paws-api:10.47.10"

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

has_tty() {
  [ -r /dev/tty ]
}

prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local value=""

  if has_tty; then
    read -r -p "$prompt [$default]: " value < /dev/tty || true
  fi

  if [ -z "$value" ]; then
    echo "$default"
  else
    echo "$value"
  fi
}

prompt_yes_no() {
  local prompt="$1"
  local default="$2"
  local value=""

  if has_tty; then
    read -r -p "$prompt [$default]: " value < /dev/tty || true
  fi

  if [ -z "$value" ]; then
    echo "$default"
  else
    echo "$value"
  fi
}

ensure_docker() {
  command -v docker >/dev/null 2>&1 || fail "Docker nije instaliran."
  docker compose version >/dev/null 2>&1 || fail "Docker Compose plugin nije instaliran."
}

extract_current_image() {
  local compose_file="$1"
  awk '/image:/ {print $2; exit}' "$compose_file"
}

extract_current_port() {
  local compose_file="$1"
  awk -F: '/ports:/ {found=1; next} found && /- / {gsub(/[" ]/, "", $0); print $(NF-1); exit}' "$compose_file"
}

update_compose_image() {
  local compose_file="$1"
  local new_image="$2"
  sed -i -E "s|(^[[:space:]]*image:[[:space:]]*).*$|\1${new_image}|" "$compose_file"
}

main() {
  require_root
  ensure_docker

  local install_dir compose_file current_image new_image docker_login_choice docker_username current_port

  install_dir="$(prompt_with_default 'Install folder' "$DEFAULT_INSTALL_DIR")"
  compose_file="$install_dir/docker-compose.yml"

  [ -d "$install_dir" ] || fail "Folder ne postoji: $install_dir"
  [ -f "$compose_file" ] || fail "docker-compose.yml ne postoji u: $install_dir"

  current_image="$(extract_current_image "$compose_file")"
  current_image="${current_image:-$DEFAULT_IMAGE}"
  current_port="$(extract_current_port "$compose_file")"
  current_port="${current_port:-8090}"

  echo
  echo "Trenutni image: $current_image"
  echo "Trenutni port:  $current_port"

  new_image="$(prompt_with_default 'Novi image' "$current_image")"
  docker_login_choice="$(prompt_yes_no 'Treba li docker login prije pull-a? (y/N)' 'N')"

  if [[ "$docker_login_choice" =~ ^[Yy]$ ]]; then
    docker_username="$(prompt_with_default 'Docker username' 'emirhasanovic')"
    docker login -u "$docker_username"
  fi

  log "Pullam image: $new_image"
  docker pull "$new_image"

  log "Ažuriram docker-compose.yml"
  update_compose_image "$compose_file" "$new_image"

  log "Redeploy PAWS API"
  cd "$install_dir"
  docker compose up -d

  echo
  log "Update završen"
  echo "Folder: $install_dir"
  echo "Image:  $new_image"
  echo "Port:   $current_port"
  echo
  echo "Korisne komande:"
  echo "  cd $install_dir && docker compose logs -f"
  echo "  cd $install_dir && docker compose ps"
  echo "  cd $install_dir && docker compose restart"
  echo "  curl http://127.0.0.1:$current_port/swagger/v1/swagger.json"
}

main "$@"

chmod +x /opt/paws-api/dist/update-paws.sh