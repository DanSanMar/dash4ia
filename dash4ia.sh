#!/usr/bin/env bash
###############################################################################
# dash4ia — Monitor de recursos para cargas de IA en local
#
# Muestra: CPU total, RAM, GPU (NVIDIA/AMD/Intel), VRAM, temperatura,
# carga del sistema y los 3 procesos principales (destacando los de IA).
#
# Diseñado para no parpadear ni montar líneas entre actualizaciones.
#
# Copyright (C) 2026 DanSanMar
#
# Este programa es software libre: puedes redistribuirlo y/o modificarlo bajo
# los términos de la GNU General Public License tal como la publica la Free
# Software Foundation, ya sea la versión 3 de la Licencia o (a tu elección)
# cualquier versión posterior.
#
# Se distribuye con la esperanza de que sea útil, pero SIN NINGUNA GARANTÍA;
# ni siquiera la garantía implícita de COMERCIABILIDAD o IDONEIDAD PARA UN
# PROPÓSITO PARTICULAR. Consulta la GNU General Public License para más
# detalles. Deberías haber recibido una copia junto con este programa; si no,
# consulta <https://www.gnu.org/licenses/>.
###############################################################################
set -u

# ---------------------------------------------------------------------------
# Configuración por defecto (sobrescribible por variables de entorno)
# ---------------------------------------------------------------------------
VERSION="1.3"
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
        -V|--version)
            echo "dash4ia v${VERSION}"; exit 0 ;;
        -h|--help)
            echo "dash4ia v${VERSION} - Monitor de recursos para IA local"
            echo "Uso: $0 [-i SEG] [-s|--simple] [-1|--once] [-V|--version] [-h|--help]"
            echo ""
            echo "  -i, --interval SEG   Segundos entre refrescos (por defecto ${INTERVAL})"
            echo "  -s, --simple        Modo compacto en texto plano: una línea por métrica"
            echo "  -1, --once          Un solo frame y sale (no entra en bucle)"
            exit 0 ;;
        *)
            echo "Opción desconocida: $1" >&2
            exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Colores y estilos (ANSI: se ven igual en cualquier terminal)
# ---------------------------------------------------------------------------
RESET=$'\033[0m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
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

# Alias en inglés (el resto del script usa RED, GREEN, BLUE, etc.)
RED="$ROJO"
GREEN="$VERDE"
YELLOW="$AMARILLO"
BLUE="$AZUL"
CYAN="$CIAN"
MAGENTA="$AMARILLO_BRILLANTE"

# tput solo se usa para restaurar el cursor al salir (solo en modo full;
# en modo simple no se toca la terminal para no ensuciar tuberías)
CNORM=''
[ "$MODE" = "full" ] && command -v tput >/dev/null 2>&1 && CNORM=$(tput cnorm 2>/dev/null)

cleanup() {
    [ -n "$CNORM" ] && tput cnorm 2>/dev/null
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Colores aleatorios estilo dash4me (mezcla de paletas)
# ---------------------------------------------------------------------------
# Paletas disponibles; se mezclan para elegir cada parte del logo al azar
PALETA_BRILLANTE=("$AZUL_BRILLANTE" "$VERDE_BRILLANTE" "$AMARILLO_BRILLANTE" "$CIAN_BRILLANTE" "$ROJO_BRILLANTE" "$AZUL_CLARO")
PALETA_ESTANDAR=("$VERDE" "$AMARILLO" "$AZUL" "$CIAN" "$ROJO" "$MAGENTA")
PALETA_LOGO=("${PALETA_BRILLANTE[@]}" "${PALETA_ESTANDAR[@]}")

# color_aleatorio -> devuelve un color al azar de la paleta completa
color_aleatorio() {
    local n=${#PALETA_LOGO[@]}
    printf '%s' "${PALETA_LOGO[$((RANDOM % n))]}"
}

# Asigna un color aleatorio e independiente a cada parte del logo:
#   COLOR_LOGO -> "dash4ia"
#   COLOR_FULL -> "full dashboard"
#   COLOR_VER  -> versión (v 1.1)
#   COLOR_RAYO -> "⚡"
#   COLOR_DASH -> líneas y separadores
colores_aleatorios() {
    COLOR_LOGO=$(color_aleatorio)
    COLOR_FULL=$(color_aleatorio)
    COLOR_VER=$(color_aleatorio)
    COLOR_RAYO=$(color_aleatorio)
    COLOR_DASH=$(color_aleatorio)
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

# round_num <texto> -> primer número del texto redondeado a entero, o vacío
# (sirve para valores tipo "143.45" o "N/A" de nvidia-smi)
round_num() {
    awk -v s="$1" 'BEGIN{
        if (match(s, /[0-9]+(\.[0-9]+)?/)) printf "%d", substr(s, RSTART, RLENGTH)+0
    }'
}

# ---------------------------------------------------------------------------
# Lecturas de hardware
# ---------------------------------------------------------------------------

# --- CPU: uso total y por núcleo en una sola ventana de muestreo ---
# Salida: 1ª línea = % total; siguientes = % de cada núcleo (en orden)
read_cpu() {
    local s1 s2
    s1=$(awk '/^cpu[0-9]* /{ print $2+$3+$4+$5+$6+$7+$8, $5+$6 }' /proc/stat)
    sleep 0.3
    s2=$(awk '/^cpu[0-9]* /{ print $2+$3+$4+$5+$6+$7+$8, $5+$6 }' /proc/stat)
    paste <(printf '%s\n' "$s1") <(printf '%s\n' "$s2") | awk '
        {
            dt=$3-$1; di=$4-$2
            if (dt>0) { p=(1-di/dt)*100; if(p<0)p=0; if(p>100)p=100 } else p=0
            printf "%d\n", p+0.5
        }'
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

# --- Swap (KiB): total, usada, % ---
read_swap() {
    local total free used pct
    total=$(awk '/^SwapTotal:/{print $2}' /proc/meminfo)
    free=$(awk '/^SwapFree:/{print $2}' /proc/meminfo)
    total=${total:-0}
    free=${free:-0}
    used=$(( total - free ))
    [ "$used" -lt 0 ] && used=0
    if [ "$total" -gt 0 ]; then
        pct=$(( used * 100 / total ))
    else
        pct=0
    fi
    echo "${total} ${used} ${pct}"
}

# --- Carga del sistema ---
read_load() {
    local load cpus
    load=$(awk '{printf "%s %s %s", $1, $2, $3}' /proc/loadavg)
    cpus=$(nproc 2>/dev/null || echo '?')
    echo "${cpus} ${load}"
}

# --- Uptime en texto corto: "3d 4h", "4h 12m" o "12m" ---
read_uptime() {
    local up d h m
    up=$(awk '{printf "%d", $1}' /proc/uptime)
    up=${up:-0}
    d=$(( up / 86400 ))
    h=$(( (up % 86400) / 3600 ))
    m=$(( (up % 3600) / 60 ))
    if [ "$d" -gt 0 ]; then printf '%dd %dh' "$d" "$h"
    elif [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
    else printf '%dm' "$m"; fi
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
    GPU_FAN_STR=""
    GPU_FAN_PCT=""
    GPU_MEM_USED_MB=0
    GPU_MEM_TOTAL_MB=0
    GPU_UTIL=0
    GPU_POWER_W=""
    GPU_POWER_MAX_W=""
    GPU_FREQ_MHZ=""
    GPU_FREQ_MAX_MHZ=""

    # 1. NVIDIA
    if have nvidia-smi; then
        local n_out rc=0
        n_out=$(nvidia-smi --query-gpu=name,temperature.gpu,fan.speed,memory.used,memory.total,utilization.gpu,power.draw,power.limit,clocks.sm,clocks.max.sm \
            --format=csv,noheader,nounits 2>&1) || rc=$?
        if [ $rc -eq 0 ] && [ -n "$n_out" ] && ! echo "$n_out" | grep -qiE 'failed|could not|unable|not found|error'; then
            IFS=',' read -r g_model g_temp g_fan g_used g_tot g_util g_pow g_powmax g_clock g_clockmax <<< "$n_out"
            GPU_TYPE="NVIDIA"
            GPU_MODEL=$(echo "$g_model" | xargs)
            GPU_TEMP=$(echo "$g_temp" | tr -dc '0-9')
            GPU_FAN_STR="$(echo "$g_fan" | tr -dc '0-9')%"
            GPU_FAN_PCT=$(echo "$g_fan" | tr -dc '0-9')
            GPU_MEM_USED_MB=$(echo "$g_used" | tr -dc '0-9')
            GPU_MEM_TOTAL_MB=$(echo "$g_tot" | tr -dc '0-9')
            GPU_UTIL=$(echo "$g_util" | tr -dc '0-9')
            GPU_POWER_W=$(round_num "$g_pow")
            GPU_POWER_MAX_W=$(round_num "$g_powmax")
            GPU_FREQ_MHZ=$(round_num "$g_clock")
            GPU_FREQ_MAX_MHZ=$(round_num "$g_clockmax")
            : "${GPU_TEMP:=0}" "${GPU_MEM_USED_MB:=0}" "${GPU_MEM_TOTAL_MB:=0}" "${GPU_UTIL:=0}"
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
                # Filtrar por clase real (vga/3d/display): el primer dispositivo AMD suele ser un PCI bridge
                GPU_MODEL=$(lspci -d 1002: 2>/dev/null | grep -iE 'vga|3d|display' | head -n1 \
                    | sed -E 's/^[0-9a-f:.]+ [^:]*: //; s/^Advanced Micro Devices, Inc\. \[AMD\/ATI\] //; s/^AMD\/ATI //; s/ *\(rev .*\)$//' \
                    | xargs)
            fi
            [ -z "$GPU_MODEL" ] && GPU_MODEL="AMD Radeon Graphics"
            if [ -f "$card/device/mem_info_vram_used" ] && [ -f "$card/device/mem_info_vram_total" ]; then
                GPU_MEM_USED_MB=$(( $(cat "$card/device/mem_info_vram_used" 2>/dev/null) / 1024 / 1024 ))
                GPU_MEM_TOTAL_MB=$(( $(cat "$card/device/mem_info_vram_total" 2>/dev/null) / 1024 / 1024 ))
            fi
            [ -f "$card/device/gpu_busy_percent" ] && GPU_UTIL=$(cat "$card/device/gpu_busy_percent" 2>/dev/null | tr -dc '0-9')
            if [ -d "$card/device/hwmon" ]; then
                local hwmon_dir fan_rpm fan_max pwm pwm_max
                hwmon_dir=$(ls -d "$card/device/hwmon/hwmon"* 2>/dev/null | head -n 1)
                if [ -n "$hwmon_dir" ]; then
                    [ -f "$hwmon_dir/temp1_input" ] && GPU_TEMP=$(( $(cat "$hwmon_dir/temp1_input" 2>/dev/null) / 1000 ))
                    # Fan: RPM si el driver lo expone y, si hay fan1_max, se deduce
                    # el % de giro de las RPM (más fiable que pwm1 en modo auto)
                    if [ -f "$hwmon_dir/fan1_input" ]; then
                        fan_rpm=$(cat "$hwmon_dir/fan1_input" 2>/dev/null | tr -dc '0-9')
                        [ -n "$fan_rpm" ] && GPU_FAN_STR="${fan_rpm} RPM"
                    fi
                    [ -f "$hwmon_dir/fan1_max" ] && fan_max=$(cat "$hwmon_dir/fan1_max" 2>/dev/null | tr -dc '0-9')
                    if [ -n "$fan_rpm" ] && [ "${fan_max:-0}" -gt 0 ] 2>/dev/null; then
                        GPU_FAN_PCT=$(( fan_rpm * 100 / fan_max ))
                    fi
                    # Sin RPM: se usa el ciclo de trabajo (pwm1)
                    if [ -z "$GPU_FAN_PCT" ] && [ -f "$hwmon_dir/pwm1" ]; then
                        pwm=$(cat "$hwmon_dir/pwm1" 2>/dev/null | tr -dc '0-9')
                        pwm_max=$(cat "$hwmon_dir/pwm1_max" 2>/dev/null | tr -dc '0-9')
                        : "${pwm_max:=255}"
                        if [ -n "$pwm" ] && [ "${pwm_max:-0}" -gt 0 ]; then
                            GPU_FAN_PCT=$(( pwm * 100 / pwm_max ))
                            [ -z "$GPU_FAN_STR" ] && GPU_FAN_STR="${GPU_FAN_PCT}%"
                        fi
                    fi
                    # Potencia en µW -> W (best-effort)
                    if [ -f "$hwmon_dir/power1_average" ]; then
                        local pow_uw
                        pow_uw=$(cat "$hwmon_dir/power1_average" 2>/dev/null | tr -dc '0-9')
                        [ -n "$pow_uw" ] && GPU_POWER_W=$(( pow_uw / 1000000 ))
                    fi
                    if [ -f "$hwmon_dir/power1_cap" ]; then
                        local cap_uw
                        cap_uw=$(cat "$hwmon_dir/power1_cap" 2>/dev/null | tr -dc '0-9')
                        [ -n "$cap_uw" ] && GPU_POWER_MAX_W=$(( cap_uw / 1000000 ))
                    fi
                fi
            fi
            # Frecuencia actual y máxima (MHz) vía pp_dpm_sclk (la actual va con '*')
            if [ -f "$card/device/pp_dpm_sclk" ]; then
                GPU_FREQ_MHZ=$(grep '\*' "$card/device/pp_dpm_sclk" 2>/dev/null | grep -oE '[0-9]+[Mm]hz' | head -n1 | tr -dc '0-9')
                GPU_FREQ_MAX_MHZ=$(grep -oE '[0-9]+[Mm]hz' "$card/device/pp_dpm_sclk" 2>/dev/null | tr -dc '0-9\n' | sort -n | tail -n1)
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
                GPU_FREQ_MHZ=$act
                GPU_FREQ_MAX_MHZ=$max
            fi
            return
        fi
    done
}

# --- Procesos (top 3 por CPU) ---
read_top_processes() {
    # comm = nombre corto del ejecutable (para mostrar); cmd = línea completa (para detectar IA)
    ps -eo pid,user,pcpu,pmem,etime,comm,cmd --sort=-pcpu 2>/dev/null | head -n 4
}

IA_PATTERNS='ollama|llama|vllm|text-generation|tgi|comfy|stable-diffusion|whisper|transformers|diffusers|exllama|ktransformers|autocg|janus|python|python3'

# Patrón más estricto para el resumen: sin el "python" genérico, que contaría
# cualquier app de escritorio escrita en Python (blueman, etc.). Las
# herramientas de IA en Python siguen detectándose por su propio módulo/paquete
# (p. ej. "python -m vllm..." -> coincide por "vllm").
IA_SUMMARY_PATTERNS='ollama|llama|vllm|text-generation|tgi|comfy|stable-diffusion|whisper|transformers|diffusers|exllama|ktransformers|autocg|janus'

# --- Resumen de procesos de IA: "<nº> <cpu_total%> <rss_total_kb>" ---
# Se excluyen los propios procesos del pipeline (ps/awk/grep...) para que el
# patrón no se detecte a sí mismo en su línea de comandos.
read_ia_summary() {
    ps -eo pcpu,rss,cmd 2>/dev/null | awk -v pat="$IA_SUMMARY_PATTERNS" '
        NR > 1 {
            if ($3 ~ /^(awk|ps|grep|tail|head|pgrep|sed)$/) next
            cmd=$3; for (i=4; i<=NF; i++) cmd=cmd " " $i
            if (cmd ~ pat) { n++; cpu+=$1; rss+=$2 }
        }
        END { printf "%d %.1f %d\n", n+0, cpu+0, rss+0 }
    '
}

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

# Ancho de barra del modo full: igual para TODAS las métricas del frame.
# Prefijo compacto (indent 2 + etiqueta 7 + valor 5) y hueco para la columna
# de datos al final. Se encoge en terminales estrechas para no partir líneas.
bar_width() {
    local w bw
    w=${WIDTH:-$(term_width)}
    bw=$(( w - 40 ))
    [ "$bw" -lt 10 ] && bw=10
    [ "$bw" -gt 48 ] && bw=48
    printf '%s' "$bw"
}

# draw_metric <color> <etiqueta> <valor(5)> <pct> [detalle]
# Formato uniforme de barra: etiqueta, valor, barra (ancho fijo) y detalle
# numérico alineado al final. El detalle se recorta si no cabe (terminales
# estrechas) para no partir la línea.
draw_metric() {
    local col="$1" label="$2" val="$3" pct="$4" detail="${5:-}"
    local w avail
    w=${WIDTH:-$(term_width)}
    avail=$(( w - BAR_W - 19 ))
    [ "$avail" -lt 0 ] && avail=0
    [ "${#detail}" -gt "$avail" ] && detail="${detail:0:$avail}"
    printf '  %s%-7s%s %s %s%s%s  %s%s%s\n' \
        "$col" "$label" "$RESET" "$val" \
        "$col" "$(draw_bar "$pct" "$BAR_W")" "$RESET" \
        "$DIM" "$detail" "$RESET"
}

# Línea de separación entre secciones (solo modo simple, texto plano)
draw_rule() {
    local w
    w=$(term_width)
    [ "$w" -lt 40 ] && w=40
    printf '%s\n' "$(printf -- '-%.0s' $(seq 1 "$w"))"
}

draw_header() {
    local now w up
    now=$(date '+%H:%M:%S')
    w=$(term_width)
    up=$(read_uptime)

    # Colores aleatorios para cada parte del logo
    colores_aleatorios

    if [ "$MODE" = "simple" ]; then
        echo "=== dash4ia v${VERSION} | $now | host: $HOSTNAME_VAL | intervalo ${INTERVAL}s ==="
        return
    fi

    # Línea superior estilo dash4me
    printf '%s%s%s\n' "$COLOR_DASH" "─$(printf '─%.0s' $(seq 1 $((w/2))))" "$RESET"
    printf '%s %s%sDASH4IA%s %s| %sMONITORIA ^_^%s %s| %sV %s%s %s: %s%s%s %s| %sup %s%s %s⚡%s\n' \
        "$COLOR_DASH" "$COLOR_LOGO" "$BOLD" "$RESET" "$COLOR_DASH" "$COLOR_FULL" "$RESET" "$COLOR_DASH" "$COLOR_VER" "$VERSION" "$RESET" "$COLOR_DASH" "$BLANCO" "$now" "$RESET" "$COLOR_DASH" "$DIM" "$up" "$RESET" "$COLOR_RAYO" "$RESET"
    printf '%s%s%s\n' "$COLOR_DASH" "─$(printf '─%.0s' $(seq 1 $((w/2))))" "$RESET"

    printf '%s   %sAUTO-REFRESCO:%s %s s%s  |  %sCTRL+C:%s Salir%s\n' \
        "$COLOR_DASH" "$RESET" "$CIAN" "$INTERVAL" "$RESET" "$CIAN" "$RESET" "$RESET"
}

draw_cpu() {
    local cpu_data cpu_pct cpu_temp col tcol
    cpu_data=$(read_cpu)
    cpu_pct="${cpu_data%%$'\n'*}"
    cpu_pct=$(printf '%s' "${cpu_pct:-0}" | tr -dc '0-9')
    [ -z "$cpu_pct" ] && cpu_pct=0
    col=$(color_por_umbral "$cpu_pct" 85 60)
    cpu_temp=$(obtener_temp_cpu)
    tcol=$(color_por_umbral "$cpu_temp" 80 65)

    if [ "$MODE" = "simple" ]; then
        local w bar_w
        w=$(term_width)
        bar_w=$(( w - 22 ))
        [ "$bar_w" -lt 10 ] && bar_w=10
        [ "$bar_w" -gt 40 ] && bar_w=40
        # Compacto: una sola línea con uso y temperatura
        printf 'CPU  %3d%% [%s]  %3d°C\n' "$cpu_pct" "$(draw_bar "$cpu_pct" "$bar_w")" "$cpu_temp"
        return
    fi

    local cpus l1 l5 l15 load_pct lcol v
    read -r cpus l1 l5 l15 <<< "$(read_load)"

    printf '%s%s%s\n' "$BOLD$BLUE" "┌─ CPU (${cpus} hilos)" "$RESET"
    # Carga (primera): barra uniforme con las medias crudas como dato al final
    if [ "${cpus:-0}" -gt 0 ] 2>/dev/null; then
        load_pct=$(awk -v l="$l1" -v c="$cpus" 'BEGIN{ printf "%d", (l/c)*100 }')
        [ "$load_pct" -gt 100 ] && load_pct=100
        lcol=$(color_por_umbral "$load_pct" 90 70)
        printf -v v '%4d%%' "$load_pct"
        draw_metric "$lcol" "Carga:" "$v" "$load_pct" "$l1 / $l5 / $l15"
    else
        printf '  %s%-7s%s %s / %s / %s\n' "$DIM" "Carga:" "$RESET" "$l1" "$l5" "$l15"
    fi
    printf -v v '%4d%%' "$cpu_pct"
    draw_metric "$col" "Uso:" "$v" "$cpu_pct"
    printf -v v '%3d°C' "$cpu_temp"
    draw_metric "$tcol" "Temp:" "$v" "$cpu_temp"
    # Núcleos: rejilla de porcentajes con la media como primer valor destacado
    local cores
    cores=$(printf '%s\n' "$cpu_data" | tail -n +2)
    [ -n "$cores" ] && draw_cores "$cores"
    printf '%s%s%s\n' "$BOLD$BLUE" "└─────────────────────────────" "$RESET"
}

# draw_cores <porcentajes por núcleo, uno por línea>
# Rejilla de porcentajes por núcleo (color por umbral), repartida en filas
# que caben en el ancho del terminal.
draw_cores() {
    local pcts=() p
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        pcts+=("$p")
    done <<< "$1"

    local total=${#pcts[@]}
    [ "$total" -eq 0 ] && return

    # Media de uso de los núcleos (alineada con los valores de Carga/Uso/Temp)
    local sum=0 i
    for (( i=0; i<total; i++ )); do sum=$(( sum + pcts[i] )); done
    local mean=$(( sum / total ))

    local prefix=15 cell=4 sep=4   # prefijo "  Hilos: 100% " + hueco "  |  "
    local w avail max_per_row per_row rows
    w=${WIDTH:-$(term_width)}
    avail=$(( w - prefix - sep ))
    max_per_row=$(( avail / (cell + 1) ))
    [ "$max_per_row" -lt 1 ] && max_per_row=1
    if [ "$total" -le "$max_per_row" ]; then
        per_row=$total
    else
        # Reparto equilibrado en varias filas (evita una última fila casi vacía)
        rows=$(( (total + max_per_row - 1) / max_per_row ))
        per_row=$(( (total + rows - 1) / rows ))
    fi

    local col
    for (( i=0; i<total; i++ )); do
        if [ $(( i % per_row )) -eq 0 ]; then
            if [ "$i" -eq 0 ]; then
                printf '  %s%-7s%s %4d%%  %s|%s ' \
                    "$DIM" "Hilos:" "$RESET" "$mean" "$DIM" "$RESET"
            else
                printf '%19s' ''
            fi
        fi
        col=$(color_por_umbral "${pcts[$i]}" 85 60)
        printf '%s%3d%%%s ' "$col" "${pcts[$i]}" "$RESET"
        if [ $(( (i + 1) % per_row )) -eq 0 ] || [ "$i" -eq $(( total - 1 )) ]; then
            printf '\n'
        fi
    done
}

draw_ram() {
    local total available used pct col v
    local swap_total swap_used swap_pct scol
    read -r total available used pct <<< "$(read_ram)"
    read -r swap_total swap_used swap_pct <<< "$(read_swap)"

    col=$(color_por_umbral "$pct" 85 65)
    if [ "$MODE" = "simple" ]; then
        local w bar_w
        w=$(term_width)
        bar_w=$(( w - 22 ))
        [ "$bar_w" -lt 10 ] && bar_w=10
        [ "$bar_w" -gt 40 ] && bar_w=40
        # Compacto: uso y total en una sola línea, sin línea de "disponible"
        printf 'RAM  %3d%% [%s]  %s / %s\n' "$pct" "$(draw_bar "$pct" "$bar_w")" \
            "$(human_bytes "$((used*1024))")" "$(human_bytes "$((total*1024))")"
        return
    fi

    printf '%s%s%s\n' "$BOLD$MAGENTA" "┌─ Memoria" "$RESET"
    printf -v v '%4d%%' "$pct"
    draw_metric "$col" "RAM:" "$v" "$pct" \
        "$(human_bytes "$((used*1024))") / $(human_bytes "$((total*1024))")"
    if [ "${swap_total:-0}" -gt 0 ] 2>/dev/null; then
        scol=$(color_por_umbral "$swap_pct" 85 60)
        printf -v v '%4d%%' "$swap_pct"
        draw_metric "$scol" "Swap:" "$v" "$swap_pct" \
            "$(human_bytes "$((swap_used*1024))") / $(human_bytes "$((swap_total*1024))")"
    fi
    printf '%s%s%s\n' "$BOLD$MAGENTA" "└─────────────────────────────" "$RESET"
}

draw_gpu() {
    local vram_pct vram_avail g_col v_col t_col v

    obtener_datos_gpu

    vram_pct=0
    vram_avail=0
    if [ "$GPU_MEM_TOTAL_MB" -gt 0 ] 2>/dev/null; then
        vram_pct=$(awk -v u="$GPU_MEM_USED_MB" -v t="$GPU_MEM_TOTAL_MB" 'BEGIN{ printf "%d", (u/t)*100 }')
        vram_avail=$(( GPU_MEM_TOTAL_MB - GPU_MEM_USED_MB ))
        [ "$vram_avail" -lt 0 ] && vram_avail=0
    fi

    # --- Modo simple: una línea por métrica (uso, VRAM, temp y fan) ---
    if [ "$MODE" = "simple" ]; then
        local w bar_w
        w=$(term_width)
        bar_w=$(( w - 22 ))
        [ "$bar_w" -lt 10 ] && bar_w=10
        [ "$bar_w" -gt 40 ] && bar_w=40
        if [ "$GPU_TYPE" = "NONE" ]; then
            echo "GPU  No se detectó GPU dedicada (NVIDIA/AMD/Intel)."
            return
        fi
        printf 'GPU  %3d%% [%s]\n' "${GPU_UTIL:-0}" "$(draw_bar "${GPU_UTIL:-0}" "$bar_w")"
        if [ "$GPU_MEM_TOTAL_MB" -gt 0 ] 2>/dev/null; then
            printf 'VRAM %3d%% [%s]  %s/%s MiB\n' "$vram_pct" "$(draw_bar "$vram_pct" "$bar_w")" \
                "$GPU_MEM_USED_MB" "$GPU_MEM_TOTAL_MB"
        fi
        if [ "${GPU_TEMP:-0}" -gt 0 ] 2>/dev/null; then
            printf 'TEMP %3d°C [%s]\n' "$GPU_TEMP" "$(draw_bar "$GPU_TEMP" "$bar_w")"
        fi
        if [ -n "$GPU_FAN_STR" ]; then
            if [ -n "$GPU_FAN_PCT" ]; then
                printf 'FAN  %3d%% [%s]  %s\n' "$GPU_FAN_PCT" "$(draw_bar "$GPU_FAN_PCT" "$bar_w")" "$GPU_FAN_STR"
            else
                echo "FAN  ${GPU_FAN_STR}"
            fi
        fi
        return
    fi

    printf '%s%s%s\n' "$BOLD$YELLOW" "┌─ GPU / VRAM" "$RESET"
    if [ "$GPU_TYPE" = "NONE" ]; then
        printf '  %sNo se detectó GPU dedicada o faltan controladores.%s\n' "$DIM" "$RESET"
    else
        g_col=$(color_por_umbral "$GPU_UTIL" 85 60)
        v_col=$(color_por_umbral "$vram_pct" 90 70)
        t_col=$(color_por_umbral "$GPU_TEMP" 80 65)

        printf '  %s%-7s%s %s\n' "$DIM" "Tipo:" "$RESET" "$GPU_TYPE"
        printf '  %s%-7s%s %s\n' "$DIM" "Modelo:" "$RESET" "$GPU_MODEL"

        local p_col f_col fan_col pow_pct freq_pct fan_detail=""

        # Potencia (primera), uso, VRAM, frecuencia, temperatura y ventilador:
        # mismo formato; "n/d" si el driver no expone el dato
        if [ -n "$GPU_POWER_W" ] && [ -n "$GPU_POWER_MAX_W" ] && [ "$GPU_POWER_MAX_W" -gt 0 ] 2>/dev/null; then
            pow_pct=$(( GPU_POWER_W * 100 / GPU_POWER_MAX_W ))
            [ "$pow_pct" -gt 100 ] && pow_pct=100
            p_col=$(color_por_umbral "$pow_pct" 90 70)
            printf -v v '%4d%%' "$pow_pct"
            draw_metric "$p_col" "PWR:" "$v" "$pow_pct" "$GPU_POWER_W / $GPU_POWER_MAX_W W"
        elif [ -n "$GPU_POWER_W" ]; then
            printf '  %s%-7s%s %s W\n' "$DIM" "PWR:" "$RESET" "$GPU_POWER_W"
        else
            printf '  %s%-7s%s %s\n' "$DIM" "PWR:" "$RESET" "n/d"
        fi
        printf -v v '%4d%%' "$GPU_UTIL"
        draw_metric "$g_col" "GPU:" "$v" "$GPU_UTIL"
        if [ "$GPU_MEM_TOTAL_MB" -gt 0 ] 2>/dev/null; then
            printf -v v '%4d%%' "$vram_pct"
            draw_metric "$v_col" "VRAM:" "$v" "$vram_pct" \
                "$GPU_MEM_USED_MB / $GPU_MEM_TOTAL_MB MiB"
        fi
        if [ -n "$GPU_FREQ_MHZ" ] && [ -n "$GPU_FREQ_MAX_MHZ" ] && [ "$GPU_FREQ_MAX_MHZ" -gt 0 ] 2>/dev/null; then
            freq_pct=$(( GPU_FREQ_MHZ * 100 / GPU_FREQ_MAX_MHZ ))
            [ "$freq_pct" -gt 100 ] && freq_pct=100
            f_col=$(color_por_umbral "$freq_pct" 90 70)
            printf -v v '%4d%%' "$freq_pct"
            draw_metric "$f_col" "Frec:" "$v" "$freq_pct" "$GPU_FREQ_MHZ / $GPU_FREQ_MAX_MHZ MHz"
        elif [ -n "$GPU_FREQ_MHZ" ]; then
            printf '  %s%-7s%s %s MHz\n' "$DIM" "Frec:" "$RESET" "$GPU_FREQ_MHZ"
        else
            printf '  %s%-7s%s %s\n' "$DIM" "Frec:" "$RESET" "n/d"
        fi
        if [ "$GPU_TEMP" -gt 0 ] 2>/dev/null; then
            printf -v v '%3d°C' "$GPU_TEMP"
            draw_metric "$t_col" "Temp:" "$v" "$GPU_TEMP"
        fi
        # Ventilador: barra con el % de giro; las RPM como dato
        case "$GPU_FAN_STR" in
            *RPM*) fan_detail="$GPU_FAN_STR" ;;
        esac
        if [ -n "$GPU_FAN_PCT" ]; then
            fan_col=$(color_por_umbral "$GPU_FAN_PCT" 85 65)
            printf -v v '%4d%%' "$GPU_FAN_PCT"
            draw_metric "$fan_col" "Fan:" "$v" "$GPU_FAN_PCT" "$fan_detail"
        elif [ -n "$GPU_FAN_STR" ]; then
            printf '  %s%-7s%s %s\n' "$DIM" "Fan:" "$RESET" "$GPU_FAN_STR"
        else
            printf '  %s%-7s%s %s\n' "$DIM" "Fan:" "$RESET" "n/d"
        fi
    fi

    printf '%s%s%s\n' "$BOLD$YELLOW" "└─────────────────────────────" "$RESET"
}

draw_load() {
    # Solo modo simple: en full la carga va integrada en la sección CPU
    local cpus l1 l5 l15 w bar_w l_pct
    read -r cpus l1 l5 l15 <<< "$(read_load)"
    w=$(term_width)
    bar_w=$(( w - 22 ))
    [ "$bar_w" -lt 10 ] && bar_w=10
    [ "$bar_w" -gt 40 ] && bar_w=40
    # Barra relativa al número de CPUs (media de 1 min frente a núcleos)
    if [ "${cpus:-0}" -gt 0 ] 2>/dev/null; then
        l_pct=$(awk -v l="$l1" -v c="$cpus" 'BEGIN{ printf "%d", (l/c)*100 }')
        printf 'LOAD %3d%% [%s]  %s %s %s  (CPUs: %s)\n' \
            "$l_pct" "$(draw_bar "$l_pct" "$bar_w")" "$l1" "$l5" "$l15" "$cpus"
    else
        printf 'LOAD %s %s %s  (CPUs: %s)\n' "$l1" "$l5" "$l15" "$cpus"
    fi
}

draw_processes() {
    local ps_out line pid user pcpu pmem etime name cmd is_ia pc_col pm_col

    if [ "$MODE" = "simple" ]; then
        printf 'PROC %-6s %-9s %-5s %-5s %-8s %s\n' "PID" "USER" "%CPU" "%MEM" "ETIME" "PROCESO"
    else
        printf '%s%s%s\n' "$BOLD$CYAN" "┌─ Procesos (top 3 por CPU)" "$RESET"
        printf '  %s%-6s %-9s %-5s %-5s %-8s %s%s\n' "$DIM" "PID" "USER" "%CPU" "%MEM" "ETIME" "PROCESO" "$RESET"
    fi

    ps_out=$(read_top_processes)
    local first=1 count=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [ $first -eq 1 ] && { first=0; continue; }
        [ $count -ge 3 ] && break

        read -r pid user pcpu pmem etime name cmd <<< "$line"

        is_ia=0
        echo "$cmd" | grep -qiE "$IA_PATTERNS" && is_ia=1

        pc_col=$(color_por_umbral "$pcpu" 50 20)
        pm_col=$(color_por_umbral "$pmem" 70 40)

        if [ $is_ia -eq 1 ]; then
            if [ "$MODE" = "simple" ]; then
                printf "     %-6s %-9s %-5s %-5s %-8s %s [IA]\n" "$pid" "$user" "$pcpu" "$pmem" "$etime" "$name"
            else
                printf '  %s%-6s %-9s %s%-5s%s %s%-5s%s %s%-8s%s %s%s%s [IA]\n' \
                    "$DIM" "$pid" "$user" "$pc_col" "$pcpu" "$RESET" \
                    "$pm_col" "$pmem" "$RESET" "$DIM" "$etime" "$RESET" \
                    "$BOLD$RED" "$name" "$RESET"
            fi
        else
            if [ "$MODE" = "simple" ]; then
                printf "     %-6s %-9s %-5s %-5s %-8s %s\n" "$pid" "$user" "$pcpu" "$pmem" "$etime" "$name"
            else
                printf '  %s%-6s %-9s %s%-5s%s %s%-5s%s %s%-8s%s %s\n' \
                    "$DIM" "$pid" "$user" "$pc_col" "$pcpu" "$RESET" \
                    "$pm_col" "$pmem" "$RESET" "$DIM" "$etime" "$RESET" "$name"
            fi
        fi
        count=$(( count + 1 ))
    done <<< "$ps_out"

    if [ "$MODE" != "simple" ]; then
        local ia_n ia_cpu ia_rss
        read -r ia_n ia_cpu ia_rss <<< "$(read_ia_summary)"
        if [ "${ia_n:-0}" -gt 0 ] 2>/dev/null; then
            printf '  %s%-7s%s %s%d activos%s  %sCPU %s%%%s  %sRAM %s%s\n' \
                "$DIM" "IA:" "$RESET" "$BOLD$RED" "$ia_n" "$RESET" \
                "$DIM" "$ia_cpu" "$RESET" "$DIM" "$(human_bytes "$((ia_rss*1024))")" "$RESET"
        else
            printf '  %s%-7s%s %ssin procesos de IA activos%s\n' "$DIM" "IA:" "$RESET" "$DIM" "$RESET"
        fi
        printf '%s%s%s\n' "$BOLD$CYAN" "└─────────────────────────────" "$RESET"
    fi
}

draw_footer() {
    local w info
    if [ "$MODE" = "simple" ]; then
        echo "=== fin ==="
        return
    fi
    w=$(term_width)
    info=" Ctrl+C para salir  |  dash4ia v${VERSION} — monitor de IA local"
    printf '%s%s%s\n' "$DIM" "$info" "$RESET"
    printf '%s%s%s\n' "$COLOR_DASH" "─$(printf '─%.0s' $(seq 1 $((w/2))))" "$RESET"
}

# ---------------------------------------------------------------------------
# Renderizado de un frame completo (una sola impresión, sin parpadeo)
# ---------------------------------------------------------------------------
render_frame() {
    local frame clear=''

    if [ "$MODE" = "simple" ]; then
        frame=$({
            draw_header
            draw_rule
            draw_cpu
            draw_ram
            draw_gpu
            draw_load
            draw_rule
            draw_processes
            draw_footer
        })
        # En modo simple sin TTY no se emiten códigos de cursor: salida limpia
        if [ -t 1 ]; then clear=$'\033[H\033[J'; fi
    else
        # Ancho de barra calculado una sola vez por frame (16..100)
        WIDTH=$(term_width)
        BAR_W=$(bar_width)
        frame=$({
            draw_header
            draw_gpu
            draw_ram
            draw_cpu
            draw_processes
            draw_footer
        })
        # $'...' para que sean bytes ESC de verdad (con '%s' printf no interpreta \\033)
        clear=$'\033[H\033[J'
    fi

    printf '%s%s' "$clear" "$frame"
}

# ---------------------------------------------------------------------------
# Bucle principal
# ---------------------------------------------------------------------------
run_once() {
    render_frame
}

run_loop() {
    # Pantalla alternativa: guarda el terminal y lo restaura al salir.
    # Solo en modo full; el modo simple es un flujo de texto plano.
    if [ "$MODE" != "simple" ] && command -v tput >/dev/null 2>&1; then
        tput smcup 2>/dev/null
        tput civis 2>/dev/null
        trap 'tput rmcup 2>/dev/null; tput cnorm 2>/dev/null; exit 0' SIGINT SIGTERM
    else
        trap 'exit 0' SIGINT SIGTERM
    fi

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
