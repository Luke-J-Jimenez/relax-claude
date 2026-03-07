#!/usr/bin/env bash

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
# Resolve symlinks to the real script path (portable: works on macOS + Linux)
while [ -L "$SCRIPT_PATH" ]; do
  dir="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
  SCRIPT_PATH="$(readlink "$SCRIPT_PATH")"
  [[ "$SCRIPT_PATH" != /* ]] && SCRIPT_PATH="$dir/$SCRIPT_PATH"
done
SCRIPT_PATH="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)/$(basename "$SCRIPT_PATH")"
INSTALL_DIR="$HOME/.local/bin"
INSTALL_LINK="$INSTALL_DIR/relax-claude"
INSTALL_LINK_SHORT="$INSTALL_DIR/r-claude"
CONFIG_FILE="$HOME/.relax-claude-config"
KEYCHAIN_SERVICE="relax-claude"
VERSION="0.1.0"
CONTAINER_NODE_VERSION="22"
CONTAINER_CACHE_PREFIX="relax-claude-cache"

# --- Colors (respects NO_COLOR convention) ---
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]]; then
  CYAN='\e[36m'
  GREEN='\e[32m'
  YELLOW='\e[33m'
  RED='\e[31m'
  BOLD='\e[1m'
  DIM='\e[2m'
  RST='\e[0m'
else
  CYAN='' GREEN='' YELLOW='' RED='' BOLD='' DIM='' RST=''
fi

# --- Unicode capability detection ---
USE_UNICODE=false
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) USE_UNICODE=true ;;
  esac
  # Known-good terminals that support Unicode even without locale vars
  if ! $USE_UNICODE; then
    case "${TERM_PROGRAM:-}" in
      iTerm*|Apple_Terminal|vscode|WezTerm|Hyper) USE_UNICODE=true ;;
    esac
  fi
fi

if $USE_UNICODE; then
  BOX_TL='╔' BOX_TR='╗' BOX_BL='╚' BOX_BR='╝' BOX_H='═' BOX_V='║'
  ICON_OK='✓' ICON_ERR='✗' ICON_WARN='⚠' ICON_INFO='●' ICON_PROMPT='▸' ICON_DOT='·'
  PICK_PTR='▸' PICK_SEL='●' PICK_DOT='○'
  SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
else
  BOX_TL='+' BOX_TR='+' BOX_BL='+' BOX_BR='+' BOX_H='=' BOX_V='|'
  ICON_OK='*' ICON_ERR='x' ICON_WARN='!' ICON_INFO='*' ICON_PROMPT='>' ICON_DOT='-'
  PICK_PTR='>' PICK_SEL='*' PICK_DOT='.'
  SPINNER_FRAMES=('/' '-' '\' '|')
fi

# --- TUI helpers ---
_repeat_char() { local c="$1" n="$2"; local s=''; for ((i=0; i<n; i++)); do s+="$c"; done; printf '%s' "$s"; }

print_header() {
  local title="$1" inner=42
  local pad=$((inner - ${#title} - 2))
  (( pad < 0 )) && pad=0
  echo ""
  printf "  ${CYAN}%s%s%s${RST}\n" "$BOX_TL" "$(_repeat_char "$BOX_H" $inner)" "$BOX_TR"
  printf "  ${CYAN}%s${RST}  ${BOLD}%s${RST}%*s${CYAN}%s${RST}\n" "$BOX_V" "$title" "$pad" '' "$BOX_V"
  printf "  ${CYAN}%s%s%s${RST}\n" "$BOX_BL" "$(_repeat_char "$BOX_H" $inner)" "$BOX_BR"
  echo ""
}

print_welcome() {
  local inner=42
  local title="Welcome to Relax Claude v${VERSION}"
  local subtitle="Claude Code through Relax AI"
  local tpad=$((inner - ${#title} - 2))
  local spad=$((inner - ${#subtitle} - 2))
  echo ""
  printf "  ${CYAN}%s%s%s${RST}\n" "$BOX_TL" "$(_repeat_char "$BOX_H" $inner)" "$BOX_TR"
  printf "  ${CYAN}%s${RST}%*s${CYAN}%s${RST}\n" "$BOX_V" "$inner" '' "$BOX_V"
  printf "  ${CYAN}%s${RST}  ${BOLD}%s${RST}%*s${CYAN}%s${RST}\n" "$BOX_V" "$title" "$tpad" '' "$BOX_V"
  printf "  ${CYAN}%s${RST}  %s%*s${CYAN}%s${RST}\n" "$BOX_V" "$subtitle" "$spad" '' "$BOX_V"
  printf "  ${CYAN}%s${RST}%*s${CYAN}%s${RST}\n" "$BOX_V" "$inner" '' "$BOX_V"
  printf "  ${CYAN}%s%s%s${RST}\n" "$BOX_BL" "$(_repeat_char "$BOX_H" $inner)" "$BOX_BR"
  echo ""
}

msg_ok()   { printf "  ${GREEN}${ICON_OK} %s${RST}\n" "$1"; }
msg_err()  { printf "  ${RED}${ICON_ERR} %s${RST}\n" "$1"; }
msg_warn() { printf "  ${YELLOW}${ICON_WARN} %s${RST}\n" "$1"; }
msg_info() { printf "  ${CYAN}${ICON_INFO} %s${RST}\n" "$1"; }

prompt_input() { printf "  ${CYAN}${ICON_PROMPT}${RST} ${BOLD}%s${RST} " "$1"; }

print_step() {
  local current="$1" total="$2" label="$3"
  printf "  ${DIM}Step %d/%d${RST} %s ${BOLD}%s${RST}\n" "$current" "$total" "$ICON_DOT" "$label"
}

SPINNER_PID=""
SPIN_TMP=""
spin_while() {
  local msg="$1"; shift
  local frames=("${SPINNER_FRAMES[@]}")
  local count=${#frames[@]}
  local i=0

  SPIN_TMP=$(mktemp)
  CURSOR_HIDDEN=true
  printf '\e[?25l'

  # Run command in background, capture exit code
  "$@" > "$SPIN_TMP" 2>&1 &
  SPINNER_PID=$!

  while kill -0 "$SPINNER_PID" 2>/dev/null; do
    printf '\r  %b %s' "${CYAN}${frames[$((i % count))]}${RST}" "$msg"
    i=$((i + 1))
    sleep 0.1
  done

  local rc=0
  wait "$SPINNER_PID" 2>/dev/null || rc=$?

  SPIN_OUTPUT=$(cat "$SPIN_TMP" 2>/dev/null)
  rm -f "$SPIN_TMP"
  SPIN_TMP=""
  SPINNER_PID=""

  printf '\r\e[2K'
  CURSOR_HIDDEN=false
  printf '\e[?25h'
  return "$rc"
}

# Restore cursor / kill spinner on exit
CURSOR_HIDDEN=false
trap '[ -n "${SPINNER_PID:-}" ] && kill "$SPINNER_PID" 2>/dev/null; [ -n "${SPIN_TMP:-}" ] && rm -f "$SPIN_TMP"; [ "$CURSOR_HIDDEN" = true ] && printf "\e[?25h"' EXIT INT TERM

# --- Step 0: Check prerequisites ---
if ! command -v curl &>/dev/null; then
  msg_err "curl is required but not installed."
  echo "  Install it with your package manager (e.g. 'brew install curl' on macOS)."
  exit 1
fi

# --- Helper: get/set API key ---
get_api_key() {
  if [[ "$(uname)" == "Darwin" ]]; then
    security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null
  else
    cat "$HOME/.relax-claude-key" 2>/dev/null
  fi
}

set_api_key() {
  local key="$1"
  if [[ "$(uname)" == "Darwin" ]]; then
    security delete-generic-password -s "$KEYCHAIN_SERVICE" 2>/dev/null
    security add-generic-password -s "$KEYCHAIN_SERVICE" -a "$USER" -w "$key"
  else
    echo "$key" > "$HOME/.relax-claude-key"
    chmod 600 "$HOME/.relax-claude-key"
  fi
}

# Export model env vars from config file
load_model_config() {
  [ -f "$CONFIG_FILE" ] || return 0
  while IFS='=' read -r alias model; do
    [[ -z "$alias" || "$alias" == \#* ]] && continue
    case "$alias" in
      opus)   export ANTHROPIC_DEFAULT_OPUS_MODEL="$model" ;;
      sonnet) export ANTHROPIC_DEFAULT_SONNET_MODEL="$model" ;;
      haiku)  export ANTHROPIC_DEFAULT_HAIKU_MODEL="$model" ;;
    esac
  done < "$CONFIG_FILE"
}

# --- Handle flags ---
REMAINING_ARGS=()
META_FLAG=""
CONTAINER_MODE=false
CONTAINER_IMAGE=""
CONSUME_NEXT=""
for arg in "$@"; do
  # Handle arguments that consume the next value (e.g. --container <image>)
  if [[ -n "$CONSUME_NEXT" ]]; then
    if [[ "$arg" != -* ]]; then
      # Only treat as Docker image if it looks like one (no spaces, matches image pattern)
      if [[ "$arg" != *" "* ]] && [[ "$arg" == *:* || "$arg" == */* || "$arg" =~ ^[a-z0-9._-]+$ ]]; then
        CONTAINER_IMAGE="$arg"
        CONSUME_NEXT=""
        continue
      fi
      # Does not look like a Docker image — treat as a regular argument
      CONSUME_NEXT=""
      REMAINING_ARGS+=("$arg")
      continue
    fi
    CONSUME_NEXT=""
  fi
  case "$arg" in
    --help|-h)
      echo ""
      printf "  ${BOLD}relax-claude${RST} v${VERSION}\n"
      printf "  Claude Code through ${CYAN}Relax AI${RST}\n"
      echo ""
      printf "  ${BOLD}USAGE${RST}\n"
      printf "    relax-claude [options] [claude args...]\n"
      echo ""
      printf "  ${BOLD}SETUP${RST}\n"
      printf "    ${GREEN}--models, -m${RST}          Choose which models to use for opus, sonnet, and haiku\n"
      printf "    ${GREEN}--config, -c${RST}          Show current configuration\n"
      printf "    ${GREEN}--reset${RST}               Clear API key and model config (prompts first)\n"
      echo ""
      printf "  ${BOLD}RUNTIME${RST}\n"
      printf "    ${GREEN}--container, -C${RST} [img] Run Claude Code inside a Docker container\n"
      echo ""
      printf "  ${BOLD}INFO${RST}\n"
      printf "    ${GREEN}--version, -v${RST}         Show version\n"
      printf "    ${GREEN}--help, -h${RST}            Show this help message\n"
      echo ""
      printf "  All other arguments are passed directly to claude.\n"
      exit 0
      ;;
    --version|-v)
      echo "relax-claude $VERSION"
      exit 0
      ;;
    --config|-c)
      print_header "Configuration"
      local_key="$(get_api_key)"
      if [ -n "$local_key" ]; then
        masked="${local_key:0:4}...${local_key: -4}"
        printf "  ${BOLD}API key:${RST}  ${GREEN}%s${RST}\n" "$masked"
      else
        printf "  ${BOLD}API key:${RST}  ${RED}not set${RST}\n"
      fi
      if [ -f "$CONFIG_FILE" ] && grep -q '=' "$CONFIG_FILE" 2>/dev/null; then
        printf "  ${BOLD}Models:${RST}\n"
        while IFS='=' read -r alias model; do
          [[ -z "$alias" || "$alias" == \#* ]] && continue
          printf "    ${CYAN}%-7s${RST} -> %s\n" "$alias" "$model"
        done < "$CONFIG_FILE"
      else
        printf "  ${BOLD}Models:${RST}   ${YELLOW}not configured${RST} (run with --models or -m)\n"
      fi
      printf "  ${BOLD}Install:${RST}  %s\n" "$INSTALL_LINK"
      if command -v docker &>/dev/null; then
        printf "  ${BOLD}Docker:${RST}   ${GREEN}available${RST}\n"
      else
        printf "  ${BOLD}Docker:${RST}   ${DIM}not installed${RST}\n"
      fi
      echo ""
      exit 0
      ;;
    --models|-m)
      META_FLAG="models"
      ;;
    --reset)
      msg_warn "This will delete your API key and model config."
      prompt_input "Continue? [y/N]"
      read -r confirm
      case "$confirm" in
        [yY]) ;;
        *)
          echo "  Cancelled."
          exit 0
          ;;
      esac
      rm -f "$CONFIG_FILE"
      if [[ "$(uname)" == "Darwin" ]]; then
        security delete-generic-password -s "$KEYCHAIN_SERVICE" 2>/dev/null
      else
        rm -f "$HOME/.relax-claude-key"
      fi
      msg_ok "Configuration cleared. Run relax-claude to set up again."
      exit 0
      ;;
    --container|-C)
      CONTAINER_MODE=true
      CONSUME_NEXT=container
      ;;
    *)
      REMAINING_ARGS+=("$arg")
      ;;
  esac
done
set -- "${REMAINING_ARGS[@]}"

# Check claude CLI (not needed in container mode — installed inside the container)
if ! $CONTAINER_MODE && ! command -v claude &>/dev/null; then
  msg_err "'claude' CLI is not installed."
  echo ""
  echo "  Install it first:"
  echo "    npm install -g @anthropic-ai/claude-code"
  echo ""
  echo "  Then run this script again."
  exit 1
fi

# --- Helper: arrow-key picker ---
# Usage: pick_option "Prompt text" options_array
# Returns selected index via PICK_RESULT (-1 if skipped)
pick_option() {
  local prompt="$1"
  shift
  local options=("(skip)" "$@")
  local count=${#options[@]}
  local selected=1  # default to first real option, not skip

  # Hide cursor
  CURSOR_HIDDEN=true
  printf '\e[?25l'

  # Print prompt
  printf '%b\n' "$prompt"
  if [ "$count" -gt 10 ]; then
    printf "  ${DIM}Use arrows to move, Enter to select (1-9 for quick pick)${RST}\n"
  else
    printf "  ${DIM}Use arrows to move, Enter to select, or press a number${RST}\n"
  fi
  echo ""

  # Render function for a single row
  _pick_render_row() {
    local idx="$1" sel="$2"
    printf '\e[2K'
    if [ "$idx" -eq "$sel" ]; then
      if [ "$idx" -eq 0 ]; then
        printf "  ${CYAN}${PICK_SEL} [0] %s${RST}\n" "${options[$idx]}"
      elif [ "$idx" -lt 10 ]; then
        printf "  ${CYAN}${PICK_SEL} [%d] %s${RST}\n" "$idx" "${options[$idx]}"
      else
        printf "  ${CYAN}${PICK_SEL}     %s${RST}\n" "${options[$idx]}"
      fi
    else
      if [ "$idx" -eq 0 ]; then
        printf "  ${DIM}${PICK_DOT} [0] %s${RST}\n" "${options[$idx]}"
      elif [ "$idx" -lt 10 ]; then
        printf "  ${PICK_DOT} [%d] %s\n" "$idx" "${options[$idx]}"
      else
        printf "  ${PICK_DOT}     %s\n" "${options[$idx]}"
      fi
    fi
  }

  # Draw initial list
  for ((i=0; i<count; i++)); do
    _pick_render_row "$i" "$selected"
  done

  # Read input loop
  while true; do
    IFS= read -rsn1 key
    if [[ "$key" == $'\e' ]]; then
      read -rsn2 -t 0.1 key
      case "$key" in
        '[A'|'OA') # Up
          ((selected > 0)) && ((selected--))
          ;;
        '[B'|'OB') # Down
          ((selected < count - 1)) && ((selected++))
          ;;
      esac
    elif [[ "$key" == "" ]]; then
      # Enter pressed
      break
    elif [[ "$key" =~ ^[0-9]$ ]]; then
      if (( key < count )); then
        selected=$key
      fi
    fi

    # Redraw list (move cursor up)
    printf '\e[%dA' "$count"
    for ((i=0; i<count; i++)); do
      _pick_render_row "$i" "$selected"
    done
  done

  # Show cursor
  CURSOR_HIDDEN=false
  printf '\e[?25h'

  if [ $selected -eq 0 ]; then
    PICK_RESULT=-1
  else
    PICK_RESULT=$((selected - 1))
  fi
}

# --- Helper: model selection ---
select_models() {
  spin_while "Fetching available models..." \
    curl -s --connect-timeout 10 --max-time 30 -H "Authorization: Bearer $API_KEY" https://api.relax.ai/v1/models
  MODELS_JSON="$SPIN_OUTPUT"

  if command -v jq &>/dev/null; then
    MODEL_IDS="$(echo "$MODELS_JSON" | jq -r '.data[]?.id // empty' 2>/dev/null)"
  fi
  if [ -z "$MODEL_IDS" ]; then
    MODEL_IDS="$(echo "$MODELS_JSON" | grep -o '"id": *"[^"]*"' | sed 's/"id": *"//;s/"//')"
  fi

  if [ -z "$MODEL_IDS" ]; then
    msg_warn "Could not fetch models (check API key and network connection). Skipping model config."
    msg_info "You can re-run setup with: relax-claude --models (or -m)"
    return
  fi

  declare -a models
  while IFS= read -r model; do
    [[ -n "$model" ]] && models+=("$model")
  done <<< "$MODEL_IDS"

  if [ ${#models[@]} -eq 0 ]; then
    msg_warn "No models available. Skipping model config."
    msg_info "You can re-run setup with: relax-claude --models (or -m)"
    return
  fi

  print_header "Model Setup"

  local tmp_config
  tmp_config="$(mktemp "${CONFIG_FILE}.XXXXXX")"
  trap 'rm -f "$tmp_config"' RETURN

  for alias in opus sonnet haiku; do
    case "$alias" in
      opus)   desc="most capable, best for complex tasks" ;;
      sonnet) desc="good balance of quality and speed (recommended)" ;;
      haiku)  desc="fastest responses, best for simple tasks" ;;
    esac
    pick_option "Select model for '${alias}' ${DIM}(${desc})${RST}:" "${models[@]}"
    if [ $PICK_RESULT -ge 0 ]; then
      echo "${alias}=${models[$PICK_RESULT]}" >> "$tmp_config"
      msg_ok "${alias} -> ${models[$PICK_RESULT]}"
      echo ""
    else
      msg_warn "${alias} skipped"
      echo ""
    fi
  done

  if [ -s "$tmp_config" ]; then
    mv "$tmp_config" "$CONFIG_FILE"
    msg_ok "Model mappings saved. Re-run with --models (or -m) to change."
  else
    rm -f "$tmp_config"
    msg_warn "No models selected. Run with --models (or -m) to configure."
  fi
  echo ""
}

# --- Helper: container image selection ---
select_container_image() {
  local images=(
    "ubuntu:latest"
    "node:22"
    "python:3.12"
    "golang:latest"
    "rust:latest"
  )
  local labels=(
    "Ubuntu [ubuntu:latest]"
    "Node.js [node:22]"
    "Python [python:3.12]"
    "Go [golang:latest]"
    "Rust [rust:latest]"
    "Custom image..."
  )

  print_header "Container Setup"

  pick_option "Select a container image:" "${labels[@]}"

  if [ $PICK_RESULT -eq -1 ]; then
    echo "  Container mode cancelled."
    exit 0
  elif [ $PICK_RESULT -eq $(( ${#labels[@]} - 1 )) ]; then
    # Custom image
    prompt_input "Enter Docker image name (e.g. debian:bookworm):"
    read -r CONTAINER_IMAGE
    if [ -z "$CONTAINER_IMAGE" ]; then
      msg_err "No image specified. Aborting."
      exit 1
    fi
  else
    CONTAINER_IMAGE="${images[$PICK_RESULT]}"
  fi

  msg_ok "Using container image: ${CONTAINER_IMAGE}"
}

# --- Helper: container settings ---
configure_container_settings() {
  CONTAINER_RESOURCE_FLAGS=()
  CONTAINER_NETWORK_FLAGS=()
  CONTAINER_SECURITY_FLAGS=()

  print_header "Container Settings"

  # --- Resource Limits ---
  local resource_labels=(
    "Light    [2 GB RAM, 1 CPU]"
    "Standard [4 GB RAM, 2 CPUs]"
    "Heavy    [8 GB RAM, 4 CPUs]"
    "Unlimited [no limits, uses all host resources]"
  )
  pick_option "Resource limits:" "${resource_labels[@]}"
  case $PICK_RESULT in
    0)  CONTAINER_RESOURCE_FLAGS=(--memory 2g --cpus 1)
        msg_ok "Light (2 GB / 1 CPU)"; echo "" ;;
    1)  CONTAINER_RESOURCE_FLAGS=(--memory 4g --cpus 2)
        msg_ok "Standard (4 GB / 2 CPUs)"; echo "" ;;
    2)  CONTAINER_RESOURCE_FLAGS=(--memory 8g --cpus 4)
        msg_ok "Heavy (8 GB / 4 CPUs)"; echo "" ;;
    3)  CONTAINER_RESOURCE_FLAGS=()
        msg_ok "Unlimited"; echo "" ;;
    *)  CONTAINER_RESOURCE_FLAGS=(--memory 4g --cpus 2)
        msg_info "Standard (default)"; echo "" ;;
  esac

  # --- Networking ---
  local network_labels=(
    "Full access    [normal networking]"
    "Port forwarding [expose specific ports]"
    "API only       [blocks all except api.relax.ai]"
  )
  pick_option "Networking:" "${network_labels[@]}"
  case $PICK_RESULT in
    0)  CONTAINER_NETWORK_FLAGS=()
        msg_ok "Full access"; echo "" ;;
    1)  prompt_input "Enter ports to forward (comma-separated, e.g. 3000,8080):"
        read -r port_input
        CONTAINER_NETWORK_FLAGS=()
        if [ -n "$port_input" ]; then
          IFS=',' read -ra ports <<< "$port_input"
          for port in "${ports[@]}"; do
            port="$(echo "$port" | tr -d ' ')"
            [ -z "$port" ] && continue
            if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
              msg_warn "Skipping invalid port: ${port}"
              continue
            fi
            CONTAINER_NETWORK_FLAGS+=(-p "${port}:${port}")
          done
        fi
        msg_ok "Port forwarding: ${port_input:-none}"; echo "" ;;
    2)  # Resolve api.relax.ai and lock DNS so only it is reachable
        local api_ip
        api_ip="$(getent hosts api.relax.ai 2>/dev/null | awk '{print $1; exit}')"
        if [ -z "$api_ip" ]; then
          api_ip="$(dig +short api.relax.ai 2>/dev/null | head -1)"
        fi
        if [ -z "$api_ip" ]; then
          api_ip="$(host api.relax.ai 2>/dev/null | awk '/has address/{print $4; exit}')"
        fi
        if [ -n "$api_ip" ]; then
          CONTAINER_NETWORK_FLAGS=(--dns 127.0.0.1 --add-host "api.relax.ai:${api_ip}")
          msg_ok "API only (api.relax.ai -> ${api_ip})"; echo ""
        else
          msg_warn "Could not resolve api.relax.ai — falling back to full access"; echo ""
          CONTAINER_NETWORK_FLAGS=()
        fi
        ;;
    *)  CONTAINER_NETWORK_FLAGS=()
        msg_info "Full access (default)"; echo "" ;;
  esac

  # --- Security ---
  local security_labels=(
    "Standard  [recommended for most users]"
    "Hardened  [reduced permissions, more isolated]"
    "Maximum   [strictest isolation, read-only container]"
  )
  pick_option "Security hardening:" "${security_labels[@]}"
  case $PICK_RESULT in
    0)  CONTAINER_SECURITY_FLAGS=(--init)
        msg_ok "Standard"; echo "" ;;
    1)  CONTAINER_SECURITY_FLAGS=(--init --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add DAC_OVERRIDE --cap-add FOWNER --cap-add NET_BIND_SERVICE --security-opt no-new-privileges)
        msg_ok "Hardened"; echo "" ;;
    2)  CONTAINER_SECURITY_FLAGS=(--init --cap-drop ALL --cap-add CHOWN --cap-add SETUID --cap-add SETGID --cap-add DAC_OVERRIDE --cap-add FOWNER --cap-add NET_BIND_SERVICE --security-opt no-new-privileges --read-only --tmpfs /tmp:rw,size=1g --tmpfs /home/claude:rw,size=512m)
        msg_ok "Maximum isolation"; echo "" ;;
    *)  CONTAINER_SECURITY_FLAGS=(--init)
        msg_info "Standard (default)"; echo "" ;;
  esac
}

# --- Helper: launch container ---
launch_container() {
  # Check Docker is installed
  if ! command -v docker &>/dev/null; then
    msg_err "Docker is required for container mode but is not installed."
    echo ""
    echo "  Install Docker Desktop: https://www.docker.com/products/docker-desktop/"
    echo "  Then run this command again."
    exit 1
  fi

  # Check Docker daemon is running
  if ! docker info &>/dev/null; then
    msg_err "Docker daemon is not running."
    echo "  Start Docker Desktop and try again."
    exit 1
  fi

  # If no image specified, show picker
  if [ -z "$CONTAINER_IMAGE" ]; then
    select_container_image
  fi

  # Configure container settings (resources, networking, security)
  configure_container_settings

  # Build env var flags for the container
  local env_flags=(
    -e "ANTHROPIC_BASE_URL=https://api.relax.ai"
    -e "ANTHROPIC_AUTH_TOKEN=$API_KEY"
    -e "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1"
    -e "HOME=/tmp"
  )

  if [ -f "$CONFIG_FILE" ]; then
    while IFS='=' read -r alias model; do
      [[ -z "$alias" || "$alias" == \#* ]] && continue
      case "$alias" in
        opus)   env_flags+=(-e "ANTHROPIC_DEFAULT_OPUS_MODEL=$model") ;;
        sonnet) env_flags+=(-e "ANTHROPIC_DEFAULT_SONNET_MODEL=$model") ;;
        haiku)  env_flags+=(-e "ANTHROPIC_DEFAULT_HAIKU_MODEL=$model") ;;
      esac
    done < "$CONFIG_FILE"
  fi

  # Check for cached image
  local cache_tag
  cache_tag="${CONTAINER_CACHE_PREFIX}/$(echo "$CONTAINER_IMAGE" | tr '[:upper:]' '[:lower:]' | tr ':/' '-')"

  if docker image inspect "$cache_tag" &>/dev/null; then
    msg_ok "Using cached container image: ${cache_tag}"
    msg_info "Container runs with --dangerously-skip-permissions (safe inside the sandbox)."
    exec docker run --rm -it \
      --user "$(id -u):$(id -g)" \
      "${env_flags[@]}" \
      "${CONTAINER_RESOURCE_FLAGS[@]}" \
      "${CONTAINER_NETWORK_FLAGS[@]}" \
      "${CONTAINER_SECURITY_FLAGS[@]}" \
      -v "$PWD:/workspace" \
      -w /workspace \
      "$cache_tag" \
      claude --dangerously-skip-permissions "$@"
  fi

  # First run — setup + cache
  msg_info "Setting up container (first run, will be cached for next time)..."

  # Host-expanded vars: $CONTAINER_NODE_VERSION, $(id -u)
  # Container-expanded vars are escaped with backslash (\$ARCH, etc.)
  local setup_script
  setup_script=$(cat << SETUP_EOF
set -e

# Install Node.js if not present
if ! command -v node >/dev/null 2>&1; then
  echo "[1/3] Installing Node.js..."
  export DEBIAN_FRONTEND=noninteractive

  if command -v apt-get >/dev/null 2>&1; then
    echo "       Updating package lists..."
    apt-get update -qq >/dev/null 2>&1
    echo "       Installing dependencies..."
    apt-get install -y -qq curl ca-certificates xz-utils >/dev/null 2>&1
  elif command -v apk >/dev/null 2>&1; then
    echo "       Installing via apk..."
    apk add --no-cache curl nodejs npm xz >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    echo "       Installing via dnf..."
    dnf install -y curl >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    echo "       Installing via yum..."
    yum install -y curl >/dev/null 2>&1
  fi

  # If node still not available, install via official binary (glibc only)
  if ! command -v node >/dev/null 2>&1 && ! ldd --version 2>&1 | grep -qi musl; then
    ARCH=\$(uname -m)
    case "\$ARCH" in
      x86_64)  ARCH="x64" ;;
      aarch64|arm64) ARCH="arm64" ;;
    esac
    # Resolve latest v${CONTAINER_NODE_VERSION} from nodejs.org
    NODE_FULL=\$(curl -fsSL "https://nodejs.org/dist/index.json" 2>/dev/null \
      | grep -o "\"v${CONTAINER_NODE_VERSION}\.[0-9]*\.[0-9]*\"" \
      | head -1 | tr -d "\"")
    if [ -z "\$NODE_FULL" ]; then
      NODE_FULL="v${CONTAINER_NODE_VERSION}.0.0"
    fi
    echo "       Downloading Node.js \${NODE_FULL}..."
    curl -fsSL "https://nodejs.org/dist/\${NODE_FULL}/node-\${NODE_FULL}-linux-\${ARCH}.tar.xz" \
      | tar -xJ --strip-components=1 -C /usr/local/
  fi
  if ! command -v node >/dev/null 2>&1; then
    echo "ERROR: Could not install Node.js. Ensure your base image includes nodejs or uses glibc."
    exit 1
  fi
  echo "       Node.js \$(node --version) installed."
else
  echo "[1/3] Node.js already available (\$(node --version))."
fi

echo "[2/3] Installing Claude Code..."
npm install -g @anthropic-ai/claude-code 2>&1 | tail -1

# Create non-root user (claude --dangerously-skip-permissions refuses to run as root)
echo "[3/3] Setting up user environment..."
HOST_UID=$(id -u)
if ! id claude >/dev/null 2>&1; then
  if command -v useradd >/dev/null 2>&1; then
    useradd -m -u "\$HOST_UID" -s /bin/bash claude
  elif command -v adduser >/dev/null 2>&1; then
    adduser -D -u "\$HOST_UID" -s /bin/bash claude 2>/dev/null || adduser --disabled-password --gecos "" --uid "\$HOST_UID" claude
  fi
fi

echo "Setup complete."
SETUP_EOF
)

  local container_name="relax-claude-setup-$$"

  # Clean up setup container on interrupt or failure
  _cleanup_setup_container() { docker rm "$container_name" &>/dev/null; }
  trap '_cleanup_setup_container; [ -n "${SPINNER_PID:-}" ] && kill "$SPINNER_PID" 2>/dev/null; [ -n "${SPIN_TMP:-}" ] && rm -f "$SPIN_TMP"; [ "$CURSOR_HIDDEN" = true ] && printf "\e[?25h"' EXIT INT TERM

  # Run setup (non-interactive)
  if ! docker run --name "$container_name" "$CONTAINER_IMAGE" sh -c "$setup_script"; then
    msg_err "Container setup failed."
    _cleanup_setup_container
    exit 1
  fi

  # Cache the image
  if ! spin_while "Caching container image as ${cache_tag}..." \
    docker commit "$container_name" "$cache_tag"; then
    msg_err "Failed to cache container image."
    _cleanup_setup_container
    exit 1
  fi
  _cleanup_setup_container

  msg_ok "Container ready."
  msg_info "Container runs with --dangerously-skip-permissions (safe inside the sandbox)."
  echo ""

  # Launch from cached image
  exec docker run --rm -it \
    --user "$(id -u):$(id -g)" \
    "${env_flags[@]}" \
    "${CONTAINER_RESOURCE_FLAGS[@]}" \
    "${CONTAINER_NETWORK_FLAGS[@]}" \
    "${CONTAINER_SECURITY_FLAGS[@]}" \
    -v "$PWD:/workspace" \
    -w /workspace \
    "$cache_tag" \
    claude --dangerously-skip-permissions "$@"
}

# --- Compute setup steps ---
SETUP_STEP=0
TOTAL_STEPS=0
_api_key_cached="$(get_api_key)"
[ -z "$_api_key_cached" ] && ((TOTAL_STEPS++))
if [ ! -f "$CONFIG_FILE" ] || ! grep -q '=' "$CONFIG_FILE" 2>/dev/null; then
  ((TOTAL_STEPS++))
fi
unset _api_key_cached

# --- Step 1: Self-install ---
FIRST_INSTALL=false

if [ ! -e "$INSTALL_LINK" ]; then
  FIRST_INSTALL=true
  mkdir -p "$INSTALL_DIR" || { msg_err "Could not create $INSTALL_DIR"; exit 1; }
  ln -sf "$SCRIPT_PATH" "$INSTALL_LINK"
fi

if [ ! -e "$INSTALL_LINK_SHORT" ]; then
  FIRST_INSTALL=true
  mkdir -p "$INSTALL_DIR" || { msg_err "Could not create $INSTALL_DIR"; exit 1; }
  ln -sf "$SCRIPT_PATH" "$INSTALL_LINK_SHORT"
fi

if $FIRST_INSTALL; then
  case "$(basename "$SHELL")" in
    zsh)  SHELL_RC="$HOME/.zshrc" ;;
    *)    SHELL_RC="$HOME/.bashrc" ;;
  esac

  if ! grep -qF '.local/bin' "$SHELL_RC" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$SHELL_RC"
  fi

  export PATH="$INSTALL_DIR:$PATH"

  print_welcome
  msg_ok "Installed! Run 'relax-claude' or 'r-claude' from anywhere."
  printf "  ${DIM}Run 'source %s' or open a new terminal for PATH changes.${RST}\n" "$SHELL_RC"
  echo ""
fi

# --- Step 2: API key setup ---
API_KEY="$(get_api_key)"
if [ -z "$API_KEY" ]; then
  ((SETUP_STEP++))
  print_step "$SETUP_STEP" "$TOTAL_STEPS" "API Key"
  print_header "API Key Setup"

  msg_info "You need a Relax API key to continue."
  msg_info "Get or create one at: https://dashboard.relax.ai/settings/apikey"
  echo ""
  while true; do
    prompt_input "Enter your Relax API key (input is hidden):"
    read -rs API_KEY
    echo ""
    if [ -z "$API_KEY" ]; then
      msg_err "API key cannot be empty. Please try again."
      continue
    fi
    # Validate the key against the API
    if spin_while "Validating key..." \
      curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 --max-time 15 \
        -H "Authorization: Bearer $API_KEY" https://api.relax.ai/v1/models; then
      http_code="$SPIN_OUTPUT"
    else
      http_code="000"
    fi
    if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
      msg_err "Invalid API key. Please check and try again."
      API_KEY=""
      continue
    elif [[ "$http_code" == "000" ]]; then
      msg_warn "Could not reach API to validate (network issue). Saving key anyway."
    else
      msg_ok "Key validated."
    fi
    break
  done
  set_api_key "$API_KEY"
  msg_ok "API key saved."
  echo ""
fi

# --- Step 3: Model selection ---
if [[ "$META_FLAG" == "models" ]] || [ ! -f "$CONFIG_FILE" ] || ! grep -q '=' "$CONFIG_FILE" 2>/dev/null; then
  ((SETUP_STEP++))
  print_step "$SETUP_STEP" "$TOTAL_STEPS" "Model Selection"
  select_models
fi

# Exit after reconfiguration if --models was used (unless also launching a container)
if [[ "$META_FLAG" == "models" ]] && ! $CONTAINER_MODE; then
  msg_ok "Model config updated. Run relax-claude to start a session."
  exit 0
fi

# --- Step 4: Set env vars and launch ---
export ANTHROPIC_BASE_URL="https://api.relax.ai"
export ANTHROPIC_AUTH_TOKEN="$API_KEY"
export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1

load_model_config

if $CONTAINER_MODE; then
  launch_container "$@"
else
  exec claude "$@"
fi
