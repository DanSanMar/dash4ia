#!/usr/bin/env bash
###############################################################################
# dash4ia — Monitor de recursos para cargas de IA en local
#
# Muestra: CPU total, RAM, GPU (NVIDIA/AMD/Intel), VRAM, temperatura,
# carga del sistema y los 3 procesos principales (destacando los de IA).
#
# Diseñado para no parpadear ni montar líneas entre actualizaciones.
###############################################################################
set -u

# ---------------------------------------------------------------------------
# Configuración por defecto (sobrescribible por variables de entorno)
# ---------------------------------------------------------------------------
INTERVAL="${DASH4IA_INTERVAL:-2}"
MODE="${DASH4IA_MODE:-full}"   # full | simple
ONCE=0
HOSTNAME_VAL="$(hostname 2>/dev/null || echo 'localhost')"

# ---------------------------------------------------------------------------
# Parseo de argumentos
# ---------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        -i|--interval)
            INTERVAL="$2"; shift 2 ;;
        -s|--simple)
            MODE="simple"; shift ;;
        -1|--once)
            ONCE=1; shift ;;
        -h|--help)
            echo "dash4ia - Monitor de recursos para IA local"
            echo "Uso: $0 [-i SEG] [-s|--simple] [-1|--once] [-h|--help]"
            exit 0 ;;
        *)
            echo "Opción desconocida: $1" >&2
            exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Colores base (estilo dash4me)
# ---------------------------------------------------------------------------
RESET=$'\033[0m'
NEGRITA=$'\033[1m'
VERDE_BRILLANTE=$'\033[92m'
VERDE=$'\033[32m'
AMARILLO=$'\033[33m'
AMARILLO_BRILLANTE=$'\033[93m'
AZUL=$'\033[34m'
AZUL_BRILLANTE=$'\033[94m'
AZUL_CLARO=$'\033[38;5;117m'
CIAN=$'\033[36m'
CIAN_BRILLANTE=$'\033[96m'
ROJO=$'\033[31m'
ROJO_BRILLANTE=$'\033[91m'
BLANCO=$'\033[97m'
GRIS_CLARO=$'\033[0;90m'

# Alias en inglés (el resto del script usa RED, GREEN, BLUE, etc.)
RED="$ROJO"
GREEN="$VERDE"
YELLOW="$AMARILLO"
BLUE="$AZUL"
CYAN="$CIAN"
WHITE="$BLANCO"
MAGENTA="$AMARILLO_BRILLANTE"

# Colores para GPU y térmicos
VERDE_GPU=$'\033[38;5;47m'
AMARILLO_GPU=$'\033[38;5;226m'
ROJO_GPU=$'\033[38;5;209m'
CIAN_GPU=$'\033[38;5;94m'
AZUL_GRISACEO=$'\033[38;5;244m'

# Colores tput (para bordes y barras) - inicializar vacías por set -u
BOLD='' DIM='' TPUT_RESET='' TPUT_RED='' TPUT_GREEN='' TPUT_YELLOW='' TPUT_BLUE='' TPUT_MAGENTA='' TPUT_CYAN='' TPUT_WHITE=''
CIVIS='' CNORM=''

if command -v tput >/dev/null 2>&1 && [ -t 1 ] && [ "$MODE" != "simple" ]; then
    BOLD=$(tput bold)
    DIM=$(tput dim)
    TPUT_RESET=$(tput sgr0)
    TPUT_RED=$(tput setaf 1)
    TPUT_GREEN=$(tput setaf 2)
    TPUT_YELLOW=$(tput setaf 3)
    TPUT_BLUE=$(tput setaf 4)
    TPUT_MAGENTA=$(tput setaf 5)
    TPUT_CYAN=$(tput setaf 6)
    TPUT_WHITE=$(tput setaf 7)
    CIVIS=$(tput civis 2>/dev/null)
    CNORM=$(tput cnorm 2>/dev/null)
fi

# Para compatibilidad con el resto del script que usa $RESET, $RED, etc.
if [ "$MODE" != "simple" ] && command -v tput >/dev/null 2>&1 && [ -t 1 ]; then
    RESET="$TPUT_RESET"
    RED="$TPUT_RED"
    GREEN="$TPUT_GREEN"
    YELLOW="$TPUT_YELLOW"
    BLUE="$TPUT_BLUE"
    MAGENTA="$TPUT_MAGENTA"
    CYAN="$TPUT_CYAN"
    WHITE="$TPUT_WHITE"
fi

cleanup() {
    [ -n "$CNORM" ] && tput cnorm 2>/dev/null
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Colores rotativos estilo dash4me (según segundos)
# ---------------------------------------------------------------------------
colores_rotativos() {
    local segundos="$1"
    local ultimo_digito="${segundos: -1}"
    case "$ultimo_digito" in
        1) COLOR_LOGO="$AZUL_BRILLANTE" ;;
        2) COLOR_LOGO="$VERDE_BRILLANTE" ;;
        3) COLOR_LOGO="$AMARILLO_BRILLANTE" ;;
        4) COLOR_LOGO="$CIAN_BRILLANTE" ;;
        5) COLOR_LOGO="$ROJO_BRILLANTE" ;;
        6) COLOR_LOGO="$AZUL_CLARO" ;;
        7) COLOR_LOGO="$VERDE" ;;
        8) COLOR_LOGO="$AMARILLO" ;;
        9) COLOR_LOGO="$CIAN" ;;
        0) COLOR_LOGO="$ROJO" ;;
        *) COLOR_LOGO="$BLANCO" ;;
    esac

    local digito_ver=$(( (10#$segundos + 5) % 10 ))
    case "$digito_ver" in
        1) COLOR_VER="$ROJO_BRILLANTE" ;;
        2) COLOR_VER="$CIAN" ;;
        3) COLOR_VER="$VERDE" ;;
        4) COLOR_VER="$AMARILLO" ;;
        5) COLOR_VER="$AZUL_BRILLANTE" ;;
        6) COLOR_VER="$VERDE_BRILLANTE" ;;
        7) COLOR_VER="$AMARILLO_BRILLANTE" ;;
        8) COLOR_VER="$CIAN_BRILLANTE" ;;
        9) COLOR_VER="$AZUL_CLARO" ;;
        0) COLOR_VER="$BLANCO" ;;
        *) COLOR_VER="$CIAN" ;;
    esac

    local digito_dash=$(( (10#$segundos + 2) % 10 ))
    case "$digito_dash" in
        1) COLOR_DASH="$VERDE_BRILLANTE" ;;
        2) COLOR_DASH="$AMARILLO_BRILLANTE" ;;
        3) COLOR_DASH="$CIAN_BRILLANTE" ;;
        4) COLOR_DASH="$ROJO_BRILLANTE" ;;
        5) COLOR_DASH="$AZUL_CLARO" ;;
        6) COLOR_DASH="$VERDE" ;;
        7) COLOR_DASH="$AMARILLO" ;;
        8) COLOR_DASH="$CIAN" ;;
        9) COLOR_DASH="$ROJO" ;;
        0) COLOR_DASH="$BLANCO" ;;
        *) COLOR_DASH="$GRIS_CLARO" ;;
    esac
}

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# draw_bar <porcentaje> <ancho>
draw_bar() {
    local pct="$1" width="$2" filled empty i
    pct=$(awk -v p="$pct" 'BEGIN{ if (p<0) p=0; if (p>100) p=100; printf "%d", p }')
    filled=$(( pct * width / 100 ))
    empty=$(( width - filled ))
    local bar=""
    if [ "$MODE" = "simple" ]; then
        for ((i=0; i<filled; i++)); do bar+="#"; done
        for ((i=0; i<empty; i++)); do bar+="-"; done
    else
        for ((i=0; i<filled; i++)); do bar+="█"; done
        for ((i=0; i<empty; i++)); do bar+="░"; done
    fi
    printf '%s' "$bar"
}

# human_bytes <bytes>
human_bytes() {
    local b="${1:-0}"
    awk -v b="$b" 'BEGIN{
        split("B KB MB GB TB PB", u, " ");
        s=1; v=b+0;
        while (v>=1024 && s<7) { v/=1024; s++ }
        printf "%.2f %s", v, u[s]
    }'
}

# color_por_umbral <valor> <alto> <medio>
color_por_umbral() {
    local val="$1" alto="$2" medio="$3"
    local ival
    ival=$(awk -v v="$val" 'BEGIN{ printf "%d", v+0.5 }')
    if [ "$ival" -ge "$alto" ]; then echo "$RED"
    elif [ "$ival" -ge "$medio" ]; then echo "$YELLOW"
    else echo "$GREEN"; fi
}

# ---------------------------------------------------------------------------
# Lecturas de hardware
# ---------------------------------------------------------------------------

# --- CPU total (dos muestras de /proc/stat para calcular %) ---
read_cpu_total() {
    local s1 s2 t1_idle t1_total t2_idle t2_total dt di
    s1=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat)
    sleep 0.3
    s2=$(awk '/^cpu /{print $2+$3+$4+$5+$6+$7+$8, $5+$6}' /proc/stat)
    t1_total=$(echo "$s1" | awk '{print $1}')
    t1_idle=$(echo "$s1" | awk '{print $2}')
    t2_total=$(echo "$s2" | awk '{print $1}')
    t2_idle=$(echo "$s2" | awk '{print $2}')
    dt=$(( t2_total - t1_total ))
    di=$(( t2_idle - t1_idle ))
    if [ "$dt" -gt 0 ]; then
        awk -v dt="$dt" -v di="$di" 'BEGIN{ pct=(1-di/dt)*100; if(pct<0)pct=0; if(pct>100)pct=100; printf "%d", pct }'
    else
        echo 0
    fi
}

# --- RAM ---
read_ram() {
    local mem_total mem_available mem_used mem_pct
    mem_total=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    mem_available=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
    mem_total=${mem_total:-0}
    mem_available=${mem_available:-0}
    if [ "$mem_available" -gt 0 ]; then
        mem_used=$(( mem_total - mem_available ))
    else
        local mem_free buffers cached
        mem_free=$(awk '/^MemFree:/{print $2}' /proc/meminfo)
        buffers=$(awk '/^Buffers:/{print $2}' /proc/meminfo)
        cached=$(awk '/^Cached:/{print $2}' /proc/meminfo)
        mem_used=$(( mem_total - mem_free - buffers - cached ))
    fi
    [ "$mem_used" -lt 0 ] && mem_used=0
    if [ "$mem_total" -gt 0 ]; then
        mem_pct=$(awk -v u="$mem_used" -v t="$mem_total" 'BEGIN{ printf "%d", (u/t)*100 }')
    else
        mem_pct=0
    fi
    echo "${mem_total} ${mem_available} ${mem_used} ${mem_pct}"
}

# --- Carga del sistema ---
read_load() {
    local load cpus
    load=$(awk '{printf "%s %s %s", $1, $2, $3}' /proc/loadavg)
    cpus=$(nproc 2>/dev/null || echo '?')
    echo "${load} ${cpus}"
}

# --- Temperatura CPU (sysfs + sensors) ---
obtener_temp_cpu() {
    local temp=0 zone type raw
    for zone in /sys/class/thermal/thermal_zone*; do
        [ -f "$zone/type" ] && [ -f "$zone/temp" ] || continue
        type=$(cat "$zone/type" 2>/dev/null)
        if [[ "$type" =~ x86_pkg_temp|cpu-thermal|cpu_thermal|k10temp|coretemp ]]; then
            raw=$(cat "$zone/temp" 2>/dev/null)
            [ -n "$raw" ] && [ "$raw" -gt 0 ] && { temp=$(( raw / 1000 )); break; }
        fi
    done
    [ "$temp" -eq 0 ] && [ -f /sys/class/thermal/thermal_zone0/temp ] && {
        raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
        [ -n "$raw" ] && [ "$raw" -gt 0 ] && temp=$(( raw / 1000 ))
    }
    [ "$temp" -eq 0 ] && have sensors && {
        local s_temp
        s_temp=$(sensors 2>/dev/null | grep -m1 -E 'Package id 0:|CPU:|Core 0:' | awk '{print $3}' | tr -dc '0-9.')
        [ -n "$s_temp" ] && temp=$(printf "%.0f" "$s_temp" 2>/dev/null)
    }
    echo "${temp:-0}"
}

# --- GPU multi-vendor (NVIDIA / AMD / Intel) ---
obtener_datos_gpu() {
    GPU_TYPE="NONE"
    GPU_MODEL="No detectada"
    GPU_TEMP=0
    GPU_FAN=0
    GPU_MEM_USED_MB=0
    GPU_MEM_TOTAL_MB=0
    GPU_UTIL=0

    # 1. NVIDIA
    if have nvidia-smi; then
        local n_out rc=0
        n_out=$(nvidia-smi --query-gpu=name,temperature.gpu,fan.speed,memory.used,memory.total,utilization.gpu \
            --format=csv,noheader,nounits 2>&1) || rc=$?
        if [ $rc -eq 0 ] && [ -n "$n_out" ] && ! echo "$n_out" | grep -qiE 'failed|could not|unable|not found|error'; then
            IFS=',' read -r g_model g_temp g_fan g_used g_tot g_util <<< "$n_out"
            GPU_TYPE="NVIDIA"
            GPU_MODEL=$(echo "$g_model" | xargs)
            GPU_TEMP=$(echo "$g_temp" | tr -dc '0-9')
            GPU_FAN=$(echo "$g_fan" | tr -dc '0-9')
            GPU_MEM_USED_MB=$(echo "$g_used" | tr -dc '0-9')
            GPU_MEM_TOTAL_MB=$(echo "$g_tot" | tr -dc '0-9')
            GPU_UTIL=$(echo "$g_util" | tr -dc '0-9')
            : "${GPU_TEMP:=0}" "${GPU_FAN:=0}" "${GPU_MEM_USED_MB:=0}" "${GPU_MEM_TOTAL_MB:=0}" "${GPU_UTIL:=0}"
            return
        fi
    fi

    # 2. AMD (sysfs)
    for card in /sys/class/drm/card[0-9]*; do
        [ -f "$card/device/vendor" ] || continue
        local vendor
        vendor=$(cat "$card/device/vendor" 2>/dev/null)
        if [ "$vendor" = "0x1002" ]; then
            GPU_TYPE="AMD"
            if have lspci; then
                GPU_MODEL=$(lspci -d 1002: 2>/dev/null | head -n1 \
                    | sed -E 's/.*VGA compatible controller: AMD\/ATI //; s/.*Display controller: AMD\/ATI //' \
                    | cut -d'(' -f1 | xargs)
            fi
            [ -z "$GPU_MODEL" ] && GPU_MODEL="AMD Radeon Graphics"
            if [ -f "$card/device/mem_info_vram_used" ] && [ -f "$card/device/mem_info_vram_total" ]; then
                GPU_MEM_USED_MB=$(( $(cat "$card/device/mem_info_vram_used" 2>/dev/null) / 1024 / 1024 ))
                GPU_MEM_TOTAL_MB=$(( $(cat "$card/device/mem_info_vram_total" 2>/dev/null) / 1024 / 1024 ))
            fi
            [ -f "$card/device/gpu_busy_percent" ] && GPU_UTIL=$(cat "$card/device/gpu_busy_percent" 2>/dev/null | tr -dc '0-9')
            if [ -d "$card/device/hwmon" ]; then
                local hwmon_dir
                hwmon_dir=$(ls -d "$card/device/hwmon/hwmon"* 2>/dev/null | head -n 1)
                [ -n "$hwmon_dir" ] && [ -f "$hwmon_dir/temp1_input" ] && GPU_TEMP=$(( $(cat "$hwmon_dir/temp1_input" 2>/dev/null) / 1000 ))
            fi
            return
        fi
    done

    # 3. Intel (sysfs)
    for card in /sys/class/drm/card[0-9]*; do
        [ -f "$card/device/vendor" ] || continue
        local vendor
        vendor=$(cat "$card/device/vendor" 2>/dev/null)
        if [ "$vendor" = "0x8086" ]; then
            GPU_TYPE="INTEL"
            if have lspci; then
                GPU_MODEL=$(lspci -d 8086: 2>/dev/null | grep -iE 'vga|3d|display' | head -n1 \
                    | sed -E 's/.*: Intel Corporation //' | cut -d'(' -f1 | xargs)
            fi
            [ -z "$GPU_MODEL" ] && GPU_MODEL="Intel HD/Iris/Arc Graphics"
            if [ -f "$card/gt/gt0/rps_act_freq_mhz" ] && [ -f "$card/gt/gt0/rps_max_freq_mhz" ]; then
                local act max
                act=$(cat "$card/gt/gt0/rps_act_freq_mhz" 2>/dev/null)
                max=$(cat "$card/gt/gt0/rps_max_freq_mhz" 2>/dev/null)
                [ "${max:-0}" -gt 0 ] && GPU_UTIL=$(( act * 100 / max ))
            fi
            return
        fi
    done
}

# --- Procesos (top 3 por CPU) ---
read_top_processes() {
    ps -eo pid,user,pcpu,pmem,etime,cmd --sort=-pcpu 2>/dev/null | head -n 4
}

IA_PATTERNS='ollama|llama|vllm|text-generation|tgi|comfy|stable-diffusion|whisper|transformers|diffusers|exllama|ktransformers|autocg|janus|python|python3'

# ---------------------------------------------------------------------------
# Funciones de dibujo
# ---------------------------------------------------------------------------

term_width() {
    if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
        tput cols 2>/dev/null || echo 80
    else
        echo 80
    fi
}

draw_header() {
    local now w segundos
    now=$(date '+%d/%m/%Y %H:%M:%S')
    segundos=$(date +"%S")
    w=$(term_width)

    # Calcular colores rotativos estilo dash4me
    colores_rotativos "$segundos"

    if [ "$MODE" = "simple" ]; then
        echo "=== dash4ia | $now | host: $HOSTNAME_VAL | interval: ${INTERVAL}s ==="
        return
    fi

    # Línea superior estilo dash4me
    printf '%s%s%s\n' "$COLOR_DASH" "─$(printf '─%.0s' $(seq 1 $((w-2))))" "$RESET"
    printf '%s %s%sDASH4IA%s %s| %sFULL DASHBOARD%s %s| %sV 1.0%s %s: %s%s%s %s⚡%s\n' \
        "$COLOR_DASH" "$COLOR_LOGO" "$NEGRITA" "$RESET" "$COLOR_DASH" "$COLOR_VER" "$RESET" "$COLOR_DASH" "$COLOR_VER" "$RESET" "$COLOR_DASH" "$BLANCO" "$now" "$RESET" "$COLOR_DASH" "$RESET"
    printf '%s%s%s\n' "$COLOR_DASH" "─$(printf '─%.0s' $(seq 1 $((w-2))))" "$RESET"

    printf '%s   %sAUTO-REFRESCO:%s %s s%s | %sENTER:%s Actualizar%s | %sCTRL+C:%s Salir%s\n' \
        "$COLOR_DASH" "$RESET" "$CIAN" "$INTERVAL" "$RESET" "$CIAN" "$RESET" "$CIAN" "$RESET" "$CIAN" "$RESET"
}

draw_cpu() {
    local w bar_w pct col
    w=$(term_width)
    bar_w=$(( w - 22 ))
    [ "$bar_w" -lt 10 ] && bar_w=10
    [ "$bar_w" -gt 40 ] && bar_w=40

    pct=$(read_cpu_total)
    col=$(color_por_umbral "$pct" 85 60)

    if [ "$MODE" = "simple" ]; then
        echo "--- CPU ---"
        printf "  CPU total : %3d%%  [%s]\n" "$pct" "$(draw_bar "$pct" "$bar_w")"
    else
        printf '%s%s%s\n' "$BOLD$BLUE" "┌─ CPU" "$RESET"
        printf '  %sCPU total :%s %3d%%  %s%s%s\n' "$col" "$RESET" "$pct" "$col" "$(draw_bar "$pct" "$bar_w")" "$RESET"
        printf '%s%s%s\n' "$BOLD$BLUE" "└─────────────────────────────" "$RESET"
    fi
}

draw_ram() {
    local total available used pct w bar_w col
    read -r total available used pct <<< "$(read_ram)"
    w=$(term_width)
    bar_w=$(( w - 22 ))
    [ "$bar_w" -lt 10 ] && bar_w=10
    [ "$bar_w" -gt 40 ] && bar_w=40

    col=$(color_por_umbral "$pct" 85 65)
    if [ "$MODE" = "simple" ]; then
        echo "--- RAM ---"
        printf "  Usada: %s / %s (%s%%)\n" "$(human_bytes "$((used*1024))")" "$(human_bytes "$((total*1024))")" "$pct"
    else
        printf '%s%s%s\n' "$BOLD$MAGENTA" "┌─ RAM" "$RESET"
        printf '  %sMemoria :%s %3d%%  %s%s%s\n' "$col" "$RESET" "$pct" "$col" "$(draw_bar "$pct" "$bar_w")" "$RESET"
        printf '  %sUsada   :%s %s / %s (disponible %s)\n' "$DIM" "$RESET" \
            "$(human_bytes "$((used*1024))")" "$(human_bytes "$((total*1024))")" "$(human_bytes "$((available*1024))")"
        printf '%s%s%s\n' "$BOLD$MAGENTA" "└─────────────────────────────" "$RESET"
    fi
}

draw_gpu() {
    local w bar_w vram_pct g_col v_col t_col
    w=$(term_width)
    bar_w=$(( w - 22 ))
    [ "$bar_w" -lt 10 ] && bar_w=10
    [ "$bar_w" -gt 40 ] && bar_w=40

    obtener_datos_gpu

    if [ "$MODE" = "simple" ]; then
        echo "--- GPU / VRAM ---"
    else
        printf '%s%s%s\n' "$BOLD$YELLOW" "┌─ GPU / VRAM" "$RESET"
    fi

    if [ "$GPU_TYPE" = "NONE" ]; then
        if [ "$MODE" = "simple" ]; then
            echo "  No se detectó GPU dedicada (NVIDIA/AMD/Intel)."
        else
            printf '  %sNo se detectó GPU dedicada o faltan controladores.%s\n' "$DIM" "$RESET"
        fi
    else
        if [ "$GPU_MEM_TOTAL_MB" -gt 0 ] 2>/dev/null; then
            vram_pct=$(awk -v u="$GPU_MEM_USED_MB" -v t="$GPU_MEM_TOTAL_MB" 'BEGIN{ printf "%d", (u/t)*100 }')
        else
            vram_pct=0
        fi
        g_col=$(color_por_umbral "$GPU_UTIL" 85 60)
        v_col=$(color_por_umbral "$vram_pct" 90 70)
        t_col=$(color_por_umbral "$GPU_TEMP" 80 65)

        if [ "$MODE" = "simple" ]; then
            printf "  %s [%s] : GPU %3s%% | VRAM %s/%s MiB (%3s%%) | %s°C | Fan %s%%\n" \
                "$GPU_TYPE" "$GPU_MODEL" "$GPU_UTIL" "$GPU_MEM_USED_MB" "$GPU_MEM_TOTAL_MB" "$vram_pct" "$GPU_TEMP" "$GPU_FAN"
        else
            printf '  %sTipo    :%s %s\n' "$DIM" "$RESET" "$GPU_TYPE"
            printf '  %sModelo  :%s %s\n' "$DIM" "$RESET" "$GPU_MODEL"
            printf '  %sGPU     :%s %3s%%  %s%s%s\n' "$g_col" "$RESET" "$GPU_UTIL" "$g_col" "$(draw_bar "$GPU_UTIL" "$bar_w")" "$RESET"
            printf '  %sVRAM    :%s %3s%%  %s%s%s (%s MiB / %s MiB)\n' "$v_col" "$RESET" "$vram_pct" "$v_col" "$(draw_bar "$vram_pct" "$bar_w")" "$RESET" "$GPU_MEM_USED_MB" "$GPU_MEM_TOTAL_MB"
            if [ "$GPU_TEMP" -gt 0 ] 2>/dev/null; then
                printf '  %sTemp    :%s %s°C   %sFan:%s %s%%\n' "$t_col" "$RESET" "$GPU_TEMP" "$DIM" "$RESET" "$GPU_FAN"
            fi
        fi
    fi

    if [ "$MODE" != "simple" ]; then
        printf '%s%s%s\n' "$BOLD$YELLOW" "└─────────────────────────────" "$RESET"
    fi
}

draw_temperatures() {
    local cpu_temp tcol
    cpu_temp=$(obtener_temp_cpu)
    tcol=$(color_por_umbral "$cpu_temp" 80 65)

    if [ "$MODE" = "simple" ]; then
        echo "--- Temperaturas ---"
        echo "  CPU: ${cpu_temp}°C"
    else
        printf '%s%s%s\n' "$BOLD$RED" "┌─ Temperaturas" "$RESET"
        printf '  %sCPU:%s %s%s°C%s\n' "$tcol" "$RESET" "$tcol" "$cpu_temp" "$RESET"
        if [ "$GPU_TYPE" != "NONE" ] && [ "$GPU_TEMP" -gt 0 ] 2>/dev/null; then
            tcol=$(color_por_umbral "$GPU_TEMP" 80 65)
            printf '  %sGPU %s:%s %s%s°C%s\n' "$tcol" "$RESET" "$tcol" "$GPU_TEMP" "$RESET" "$GPU_TYPE"
        fi
        printf '%s%s%s\n' "$BOLD$RED" "└─────────────────────────────" "$RESET"
    fi
}

draw_load() {
    local load_str cpus w
    read -r load_str cpus <<< "$(read_load)"
    w=$(term_width)
    if [ "$MODE" = "simple" ]; then
        echo "--- Carga (load avg 1/5/15 min, CPUs) ---"
        echo "  $load_str  (CPUs: $cpus)"
    else
        printf '%s%s%s\n' "$BOLD$GREEN" "┌─ Carga del sistema" "$RESET"
        printf '  %sLoad avg :%s %s  (CPUs: %s)\n' "$DIM" "$RESET" "$load_str" "$cpus"
        printf '%s%s%s\n' "$BOLD$GREEN" "└─────────────────────────────" "$RESET"
    fi
}

draw_processes() {
    local w ps_out line pid user pcpu pmem etime cmd is_ia pc_col pm_col cmd_max
    w=$(term_width)
    cmd_max=$(( w - 26 ))
    [ "$cmd_max" -lt 15 ] && cmd_max=15

    if [ "$MODE" = "simple" ]; then
        echo "--- Procesos principales (por CPU) ---"
        echo "  PID   USER     %CPU %MEM ETIME   CMD"
    else
        printf '%s%s%s\n' "$BOLD$CYAN" "┌─ Procesos (top 3 por CPU)" "$RESET"
        printf '  %s%-6s %-9s %-5s %-5s %-8s %s%s\n' "$DIM" "PID" "USER" "%CPU" "%MEM" "ETIME" "CMD" "$RESET"
    fi

    ps_out=$(read_top_processes)
    local first=1 count=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [ $first -eq 1 ] && { first=0; continue; }
        [ $count -ge 3 ] && break

        read -r pid user pcpu pmem etime _ <<< "$line"
        cmd=$(echo "$line" | awk '{ $1=$2=$3=$4=$5=$6=""; sub(/^ +/,""); print }')
        [ ${#cmd} -gt "$cmd_max" ] && cmd="${cmd:0:$((cmd_max-3))}..."

        is_ia=0
        echo "$cmd" | grep -qiE "$IA_PATTERNS" && is_ia=1

        pc_col=$(color_por_umbral "$pcpu" 50 20)
        pm_col=$(color_por_umbral "$pmem" 70 40)

        if [ $is_ia -eq 1 ]; then
            if [ "$MODE" = "simple" ]; then
                printf "  %-6s %-9s %-5s %-5s %-8s %s [IA]\n" "$pid" "$user" "$pcpu" "$pmem" "$etime" "$cmd"
            else
                printf '  %s%-6s %-9s %s%-5s%s %s%-5s%s %s%-8s%s %s%s%s[IA]%s\n' \
                    "$DIM" "$pid" "$user" "$pc_col" "$pcpu" "$RESET" \
                    "$pm_col" "$pmem" "$RESET" "$DIM" "$etime" "$RESET" \
                    "$BOLD$RED" "$cmd" "$RESET"
            fi
        else
            if [ "$MODE" = "simple" ]; then
                printf "  %-6s %-9s %-5s %-5s %-8s %s\n" "$pid" "$user" "$pcpu" "$pmem" "$etime" "$cmd"
            else
                printf '  %s%-6s %-9s %s%-5s%s %s%-5s%s %s%-8s%s %s\n' \
                    "$DIM" "$pid" "$user" "$pc_col" "$pcpu" "$RESET" \
                    "$pm_col" "$pmem" "$RESET" "$DIM" "$etime" "$RESET" "$cmd"
            fi
        fi
        count=$(( count + 1 ))
    done <<< "$ps_out"

    if [ "$MODE" != "simple" ]; then
        printf '%s%s%s\n' "$BOLD$CYAN" "└─────────────────────────────" "$RESET"
    fi
}

draw_footer() {
    local w pad info
    if [ "$MODE" = "simple" ]; then
        echo "=== fin de muestra ==="
        return
    fi
    w=$(term_width)
    info=" Ctrl+C para salir  |  dash4ia — monitor de IA local "
    pad_len=$(( w - 4 - ${#info} ))
    [ "$pad_len" -lt 0 ] && pad_len=0
    pad=$(printf ' %.0s' $(seq 1 $pad_len))
    printf '%s║%s%s%s%s%s%s\n' \
        "$BOLD$CYAN" "$DIM" "$info" "$RESET" "$pad" "$BOLD$CYAN" "$RESET"
    printf '%s%s%s\n' "$BOLD$CYAN" "╚$(printf '═%.0s' $(seq 1 $((w-2))))╝" "$RESET"
}

# ---------------------------------------------------------------------------
# Renderizado de un frame completo (una sola impresión, sin parpadeo)
# ---------------------------------------------------------------------------
render_frame() {
    local frame
    frame=$({
        draw_header
        draw_cpu
        draw_ram
        draw_gpu
        draw_temperatures
        draw_load
        draw_processes
        draw_footer
    })
    # Mover cursor al inicio y limpiar hasta el final de la pantalla
    # (solo al principio del frame; el parpadeo es imperceptible)
    printf '\033[H\033[J%s' "$frame"
}

# ---------------------------------------------------------------------------
# Bucle principal
# ---------------------------------------------------------------------------
run_once() {
    render_frame
}

run_loop() {
    # Pantalla alternativa: guarda el terminal y lo restaura al salir
    if [ "$MODE" != "simple" ] && command -v tput >/dev/null 2>&1; then
        tput smcup 2>/dev/null
        tput civis 2>/dev/null
    fi
    trap 'tput rmcup 2>/dev/null; tput cnorm 2>/dev/null; exit 0' SIGINT SIGTERM

    while :; do
        render_frame
        sleep "$INTERVAL"
    done
}

# ---------------------------------------------------------------------------
# Punto de entrada
# ---------------------------------------------------------------------------
if [ "$ONCE" -eq 1 ]; then
    run_once
else
    run_loop
fi
