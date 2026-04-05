#!/bin/bash
set -euo pipefail

AC_PROFILE="performance"
BAT_PROFILE="quiet"

LOG_FILE="/tmp/hypr-power-manager.log"

NVIDIA_PCI_DEV="0000:01:00.0"
NVIDIA_POWER_CONTROL="/sys/bus/pci/devices/${NVIDIA_PCI_DEV}/power/control"
NVIDIA_RUNTIME_STATUS="/sys/bus/pci/devices/${NVIDIA_PCI_DEV}/power/runtime_status"

# Never kill these automatically
PROTECTED_NAMES_REGEX='^(Hyprland|Niri|Xorg|Xwayland|sddm|sddm-helper|systemd|systemd-logind|dbus-daemon|pipewire|wireplumber)$'

# If true, battery mode will also stop nvidia-powerd (can help suspend)
KILL_NVIDIA_POWERD_ON_BATTERY=true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

get_hyprland_env() {
  local hypr_pid
  hypr_pid="$(pgrep -x Hyprland | head -1 || true)"
  if [[ -z "${hypr_pid}" ]]; then
    return 1
  fi
  # shellcheck disable=SC2046
  export $(tr '\0' '\n' <"/proc/$hypr_pid/environ" | grep -E '^(XDG_RUNTIME_DIR|HYPRLAND_INSTANCE_SIGNATURE|WAYLAND_DISPLAY|DISPLAY)=' || true)
  export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
  return 0
}

get_monitor_info() {
  hyprctl monitors -j 2>/dev/null | jq -r '.[0]'
}

get_power_status() {
  cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1 || true
}

get_nvidia_user_pids() {
  sudo fuser -a /dev/nvidia* /dev/nvidiactl 2>/dev/null | tr ' ' '\n' | sed '/^$/d' | sort -u || true
}

pid_to_comm() {
  ps -p "$1" -o comm= 2>/dev/null | tr -d '[:space:]' || true
}

is_hyprland_on_nvidia() {
  if command -v nvidia-smi &>/dev/null; then
    local hypr_pid
    hypr_pid="$(pgrep -x Hyprland | head -1 || true)"
    [[ -z "$hypr_pid" ]] && return 1
    nvidia-smi --query-compute-apps=pid --format=csv,noheader 2>/dev/null | grep -qx "$hypr_pid"
  else
    return 1
  fi
}

set_asus_profile() {
  local profile="$1"

  if ! command -v asusctl &>/dev/null; then
    return 0
  fi

  log "Setting ASUS profile to $profile..."

  if asusctl profile set "$profile" >/dev/null 2>&1; then
    asusctl profile set "$profile" 2>&1 | tee -a "$LOG_FILE"
    return 0
  fi

  if asusctl profile -P "$profile" >/dev/null 2>&1; then
    asusctl profile -P "$profile" 2>&1 | tee -a "$LOG_FILE"
    return 0
  fi

  log "WARN: Could not set asusctl profile (CLI mismatch). Run: asusctl profile --help"
  return 0
}

set_power_profile_fallback() {
  local mode="$1" # power-saver / performance
  if command -v powerprofilesctl &>/dev/null; then
    log "Setting power-profiles-daemon to $mode..."
    powerprofilesctl set "$mode" 2>&1 | tee -a "$LOG_FILE" || true
  fi
}

lock_igpu_freq() {
  log "Locking iGPU frequency (optional)..."
  # Find the correct card (might be card1 on some systems)
  for card in /sys/class/drm/card*/gt_min_freq_mhz; do
    if [[ -f "$card" ]]; then
      local card_path="${card%/*}"
      log "Setting iGPU freq on $card_path"
      echo 500 | sudo tee "$card_path/gt_min_freq_mhz" >/dev/null 2>&1 || true
      echo 1000 | sudo tee "$card_path/gt_max_freq_mhz" >/dev/null 2>&1 || true
    fi
  done
}

unlock_igpu_freq() {
  log "Unlocking iGPU frequency..."
  for card in /sys/class/drm/card*/gt_min_freq_mhz; do
    if [[ -f "$card" ]]; then
      local card_path="${card%/*}"
      echo 0 | sudo tee "$card_path/gt_min_freq_mhz" >/dev/null 2>&1 || true
      echo 0 | sudo tee "$card_path/gt_max_freq_mhz" >/dev/null 2>&1 || true
    fi
  done
}

kill_nvidia_apps() {
  log "Scanning for processes using NVIDIA device nodes..."

  if is_hyprland_on_nvidia; then
    log "ERROR: Hyprland is on NVIDIA. Refusing to kill NVIDIA users (would kill session)."
    return 1
  fi

  local pids
  pids="$(get_nvidia_user_pids)"
  if [[ -z "$pids" ]]; then
    log "No processes currently holding /dev/nvidia*"
    return 0
  fi

  for pid in $pids; do
    local comm
    comm="$(pid_to_comm "$pid")"
    [[ -z "$comm" ]] && continue

    if echo "$comm" | grep -Eq "$PROTECTED_NAMES_REGEX"; then
      log "Skipping protected: $comm (PID $pid)"
      continue
    fi

    if [[ "$comm" == "nvidia-powerd" && "$KILL_NVIDIA_POWERD_ON_BATTERY" != "true" ]]; then
      log "Skipping nvidia-powerd (PID $pid) due to config"
      continue
    fi

    log "Killing NVIDIA-using process: $comm (PID $pid)"
    sudo kill -TERM "$pid" 2>/dev/null || true
  done

  sleep 2

  # SIGKILL any remaining non-protected
  local remaining
  remaining="$(get_nvidia_user_pids)"
  if [[ -n "$remaining" ]]; then
    for pid in $remaining; do
      local comm
      comm="$(pid_to_comm "$pid")"
      [[ -z "$comm" ]] && continue
      if echo "$comm" | grep -Eq "$PROTECTED_NAMES_REGEX"; then
        continue
      fi
      if [[ "$comm" == "nvidia-powerd" && "$KILL_NVIDIA_POWERD_ON_BATTERY" != "true" ]]; then
        continue
      fi
      log "SIGKILL remaining NVIDIA-using process: $comm (PID $pid)"
      sudo kill -KILL "$pid" 2>/dev/null || true
    done
  fi

  log "Remaining NVIDIA holders after kill attempt:"
  sudo fuser -v /dev/nvidia* /dev/nvidiactl 2>/dev/null | tee -a "$LOG_FILE" || true
}

set_dgpu_pm() {
  local mode="$1" # auto|on
  if [[ ! -e "$NVIDIA_POWER_CONTROL" ]]; then
    log "WARN: $NVIDIA_POWER_CONTROL does not exist"
    return 0
  fi
  log "Setting NVIDIA runtime PM to '$mode'..."
  echo "$mode" | sudo tee "$NVIDIA_POWER_CONTROL" >/dev/null || true
  if [[ -r "$NVIDIA_RUNTIME_STATUS" ]]; then
    log "NVIDIA runtime_status: $(cat "$NVIDIA_RUNTIME_STATUS" 2>/dev/null || true)"
  fi
}

apply_battery_mode() {
  log "=========================================="
  log "Applying BATTERY mode..."
  log "=========================================="

  # Stop notifications temporarily
  pkill -USR1 -x swaync 2>/dev/null || true

  # Set power profile FIRST (before compositor-specific changes)
  if command -v asusctl &>/dev/null; then
    set_asus_profile "$BAT_PROFILE"
  else
    set_power_profile_fallback power-saver
  fi

  # Lock iGPU frequency to prevent spikes
  lock_igpu_freq

  if get_hyprland_env; then
    monitor_info=$(get_monitor_info)
    monitor_name=$(echo "$monitor_info" | jq -r '.name')
    monitor_scale=$(echo "$monitor_info" | jq -r '.scale')
    current_width=$(echo "$monitor_info" | jq -r '.width')
    current_height=$(echo "$monitor_info" | jq -r '.height')

    log "Monitor: $monitor_name, Current: ${current_width}x${current_height}@?, Scale: $monitor_scale"

    # === CRITICAL TRANSPARENCY/OVERLAY FIXES FOR BATTERY ===
    
    # 1. FORCE ALL WINDOWS TO BE 100% OPAQUE - NO TRANSPARENCY
    hyprctl keyword decoration:active_opacity 1.0 2>&1 | tee -a "$LOG_FILE" || true
    hyprctl keyword decoration:inactive_opacity 1.0 2>&1 | tee -a "$LOG_FILE" || true
    hyprctl keyword decoration:fullscreen_opacity 1.0 2>&1 | tee -a "$LOG_FILE" || true
    
    # 2. DISABLE BLUR COMPLETELY (already in your script but ensure all sub-settings)
    hyprctl keyword decoration:blur:enabled false 2>&1 | tee -a "$LOG_FILE" || true
    hyprctl keyword decoration:blur:size 0 2>&1 | tee -a "$LOG_FILE" || true
    hyprctl keyword decoration:blur:passes 0 2>&1 | tee -a "$LOG_FILE" || true
    hyprctl keyword decoration:blur:ignore_opacity false 2>&1 | tee -a "$LOG_FILE" || true
    hyprctl keyword decoration:blur:new_optimizations true 2>&1 | tee -a "$LOG_FILE" || true  # Use if available
    hyprctl keyword decoration:blur:xray false 2>&1 | tee -a "$LOG_FILE" || true  # Disable xray
    
    # 3. DISABLE DIMMING (can cause transparency calculations)
    hyprctl keyword decoration:dim_inactive false 2>&1 | tee -a "$LOG_FILE" || true
    hyprctl keyword decoration:dim_strength 0.0 2>&1 | tee -a "$LOG_FILE" || true
    
    # 4. DISABLE GROUP BAR (if you use grouped windows - they have transparency)
    hyprctl keyword group:groupbar:enabled false 2>&1 | tee -a "$LOG_FILE" || true
    
    # 5. DISABLE LAYER SHELL BLUR (waybar, notifications, etc)
    # This prevents blur on transparent panels/menus
    hyprctl keyword layerrule "blur off,.*" 2>&1 | tee -a "$LOG_FILE" || true
    hyprctl keyword layerrule "xray off,.*" 2>&1 | tee -a "$LOG_FILE" || true
    
    # 6. FORCE RGBX FORMAT (ignore alpha channel completely)
    # This makes windows actually fully opaque at the compositor level
    hyprctl keyword general:allow_tearing false 2>&1 | tee -a "$LOG_FILE" || true
    
    # === REST OF YOUR EXISTING BATTERY SETTINGS ===
    
    # ENABLE VFR - This is the most important setting for battery!
    hyprctl keyword misc:vfr true 2>&1 | tee -a "$LOG_FILE" || true
    
    # Disable VRR (Variable Refresh Rate) - can cause issues on Intel iGPU
    hyprctl keyword misc:vrr 0 2>&1 | tee -a "$LOG_FILE" || true
    
    # Disable ALL expensive visual effects
    hyprctl keyword animations:enabled false 2>&1 | tee -a "$LOG_FILE" || true
    
    # Disable shadows
    hyprctl keyword decoration:shadow:enabled false 2>&1 | tee -a "$LOG_FILE" || true
    
    # Disable rounding (causes extra rendering)
    hyprctl keyword decoration:rounding 0 2>&1 | tee -a "$LOG_FILE" || true
    
    # Disable border angle animation (MAJOR battery drain)
    hyprctl keyword general:border_size 1 2>&1 | tee -a "$LOG_FILE" || true
    
    # Use software cursors on battery (saves GPU power)
    hyprctl keyword cursor:no_hardware_cursors true 2>&1 | tee -a "$LOG_FILE" || true
    
    # Lower refresh rate to 60Hz (if currently higher)
    if [[ -n "$monitor_name" && "$monitor_name" != "null" ]]; then
      current_rate=$(echo "$monitor_info" | jq -r '.refreshRate' | cut -d. -f1)
      log "Current refresh rate: ${current_rate}Hz"
      
      if [[ "$current_rate" -gt 60 ]]; then
        hyprctl keyword monitor "$monitor_name,preferred@60,auto,$monitor_scale" 2>&1 | tee -a "$LOG_FILE" || true
        log "Set $monitor_name to 60Hz"
      fi
    fi
    
    # Disable auto-reload to save battery
    hyprctl keyword misc:disable_autoreload true 2>&1 | tee -a "$LOG_FILE" || true
    
    # Reduce unfocused FPS to save power when not looking at window
    hyprctl keyword misc:render_unfocused_fps 15 2>&1 | tee -a "$LOG_FILE" || true
    
    # === WINDOW RULES FOR ALL EXISTING WINDOWS ===
    # Force opaque on all existing windows immediately
    log "Forcing opaque on all existing windows..."
    hyprctl clients -j 2>/dev/null | jq -r '.[].address' | while read -r addr; do
      if [[ -n "$addr" && "$addr" != "null" ]]; then
        hyprctl setprop "address:$addr" opaque true 2>/dev/null || true
        hyprctl setprop "address:$addr" forcergbx true 2>/dev/null || true  # Force ignore alpha
        hyprctl setprop "address:$addr" noblur true 2>/dev/null || true
        hyprctl setprop "address:$addr" noshadow true 2>/dev/null || true
      fi
    done
  fi

  # Kill NVIDIA apps and power down dGPU
  kill_nvidia_apps || true
  set_dgpu_pm auto
  
  # Wait for dGPU to actually suspend
  sleep 1
  if [[ -r "$NVIDIA_RUNTIME_STATUS" ]]; then
    local dgpu_status
    dgpu_status=$(cat "$NVIDIA_RUNTIME_STATUS" 2>/dev/null || echo "unknown")
    log "dGPU status after power management: $dgpu_status"
    if [[ "$dgpu_status" != "suspended" ]]; then
      log "WARNING: dGPU did not suspend! Check what is keeping it awake."
    fi
  fi

  # Resume notifications
  pkill -USR2 -x swaync 2>/dev/null || true

  notify-send "Power Mode" "🔋 Battery mode active. Transparency disabled." -u low 2>/dev/null || true
  
  log "Battery mode applied successfully"
}

apply_ac_mode() {
  log "=========================================="
  log "Applying AC POWER mode..."
  log "=========================================="

  # Wake dGPU FIRST before changing settings that might need it
  set_dgpu_pm on
  sleep 0.5

  # Set power profile
  if command -v asusctl &>/dev/null; then
    set_asus_profile "$AC_PROFILE"
  else
    set_power_profile_fallback performance
  fi

  # Unlock iGPU frequency
  unlock_igpu_freq

  if get_hyprland_env; then
    monitor_info=$(get_monitor_info)
    monitor_name=$(echo "$monitor_info" | jq -r '.name')
    monitor_scale=$(echo "$monitor_info" | jq -r '.scale')

    # Restore performance settings
    
    # 1. VFR can stay enabled even on AC (saves power when idle)
    # But disable it if you want maximum responsiveness
    hyprctl keyword misc:vfr true 2>&1 | tee -a "$LOG_FILE" || true
    
    # 2. Re-enable VRR if your monitor supports it
    hyprctl keyword misc:vrr 2 2>&1 | tee -a "$LOG_FILE" || true
    
    # 3. Re-enable animations
    hyprctl keyword animations:enabled true 2>&1 | tee -a "$LOG_FILE" || true
    
    # 4. Re-enable blur (if you want it)
    hyprctl keyword decoration:blur:enabled true 2>&1 | tee -a "$LOG_FILE" || true
    hyprctl keyword decoration:blur:size 8 2>&1 | tee -a "$LOG_FILE" || true
    hyprctl keyword decoration:blur:passes 1 2>&1 | tee -a "$LOG_FILE" || true
    
    # 5. Re-enable shadows
    hyprctl keyword decoration:shadow:enabled true 2>&1 | tee -a "$LOG_FILE" || true
    
    # 6. Restore rounding
    hyprctl keyword decoration:rounding 10 2>&1 | tee -a "$LOG_FILE" || true
    
    # 7. Restore border
    hyprctl keyword general:border_size 2 2>&1 | tee -a "$LOG_FILE" || true
    
    # 8. Hardware cursors on AC
    hyprctl keyword cursor:no_hardware_cursors false 2>&1 | tee -a "$LOG_FILE" || true
    
    # 9. Restore high refresh rate
    if [[ -n "$monitor_name" && "$monitor_name" != "null" ]]; then
      hyprctl keyword monitor "$monitor_name,preferred@144,auto,$monitor_scale" 2>&1 | tee -a "$LOG_FILE" || true
      log "Set $monitor_name to 144Hz"
    fi
    
    # 10. Re-enable auto-reload
    hyprctl keyword misc:disable_autoreload false 2>&1 | tee -a "$LOG_FILE" || true
    
    # 11. Restore unfocused FPS
    hyprctl keyword misc:render_unfocused_fps 60 2>&1 | tee -a "$LOG_FILE" || true
  fi

  notify-send "Power Mode" "⚡ AC Power mode active" -u low 2>/dev/null || true
  
  log "AC mode applied successfully"
}

main() {
  log "=========================================="
  log "Power Management Script Started"
  log "Arguments: $*"

  case "${1:-auto}" in
    battery|bat) apply_battery_mode ;;
    ac|power) apply_ac_mode ;;
    auto)
      status="$(get_power_status)"
      log "Auto-detected power status: $status"
      if [[ "$status" == "Discharging" ]]; then
        apply_battery_mode
      else
        apply_ac_mode
      fi
      ;;
    *)
      log "Usage: $0 [battery|ac|auto]"
      exit 2
      ;;
  esac

  log "Script completed"
  log "=========================================="
}

trap 'log "Script interrupted"; exit 0' SIGTERM SIGINT
main "$@"