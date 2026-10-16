#!/data/data/com.termux/files/usr/bin/bash
# Termux:X11 + Debian PRoot (glibc) + K11MCH1 Turnip 25.1.0-R2.
# TEST_MODE=1 simula a instalação. SELFTEST_WCP=/path/file.wcp valida um artefato local.
set -Eeuo pipefail

readonly RELEASE_TAG='winlator_v25.1_r2'
readonly WCP_URL='https://github.com/K11MCH1/WinlatorTurnipDrivers/releases/download/winlator_v25.1_r2/turnip-v25.1.0-R2.wcp'
readonly WCP_SHA256='daa18f4d1dfcc79bb6cf71580f37a3c7b0bbb054895bff1007b6dd45b82a79f4'
readonly DEBIAN='debian'
readonly WORK_DIR="${HOME}/.cache/k11-turnip-v25.1.0-r2"
readonly LOG_FILE="${LOG_FILE:-$HOME/termux-linux-setup.log}"
readonly TEST_MODE="${TEST_MODE:-0}"
DESKTOP_CHOICE="${DESKTOP_CHOICE:-}"
DESKTOP_NAME=''
DESKTOP_COMMAND=''

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"; }
fatal() { log "ERRO: $*"; exit 1; }
run() {
    if [[ "$TEST_MODE" == 1 ]]; then
        log "SIMULAÇÃO: $*"
        return 0
    fi
    log "EXECUTANDO: $*"
    local rc=0
    "$@" 2>&1 | tee -a "$LOG_FILE" || rc=${PIPESTATUS[0]}
    if (( rc != 0 )); then
        log "FALHA (código $rc): $*"
        return "$rc"
    fi
}

check_environment() {
    : > "$LOG_FILE" || fatal "Não foi possível gravar o log: $LOG_FILE"
    if [[ "$TEST_MODE" != 1 ]]; then
        [[ -n "${TERMUX_VERSION:-}" && "${PREFIX:-}" == /data/data/com.termux/files/usr ]] || \
            fatal 'Execute no Termux oficial; nenhuma instalação foi iniciada.'
        [[ "$(uname -m)" == aarch64 || "$(uname -m)" == arm64 ]] || fatal 'Este driver é somente AArch64.'
        command -v pkg >/dev/null 2>&1 || fatal 'pkg não foi encontrado.'
        command -v getprop >/dev/null 2>&1 || fatal 'getprop não foi encontrado; não consigo confirmar a GPU Android.'
        local gpu
        gpu="$(getprop ro.hardware.egl 2>/dev/null || true)"
        [[ -n "$gpu" ]] || gpu="$(getprop ro.hardware.vulkan 2>/dev/null || true)"
        [[ "${gpu,,}" == *adreno* ]] || fatal "GPU não confirmada como Adreno (valor: ${gpu:-vazio}); driver não será aplicado."
        command -v proot-distro >/dev/null 2>&1 || true
    fi
    mkdir -p "$WORK_DIR"
    log "Início; release=$RELEASE_TAG; modo de simulação=$TEST_MODE"
}

choose_desktop() {
    local choice="${DESKTOP_CHOICE:-}"
    if [[ -z "$choice" ]]; then
        printf '\nEscolha o ambiente gráfico:\n  1) XFCE4 (padrão)\n  2) LXQt\n  3) MATE\n  4) KDE Plasma\n'
        if [[ -t 0 ]]; then
            read -r -p 'Número [1]: ' choice || fatal 'Não foi possível ler a opção de desktop.'
            choice="${choice:-1}"
        else
            choice=1
            log 'Entrada não interativa; selecionando XFCE4 (opção 1).'
        fi
    fi
    case "$choice" in
        1) DESKTOP_NAME='XFCE4'; DESKTOP_COMMAND='/usr/bin/startxfce4' ;;
        2) DESKTOP_NAME='LXQt'; DESKTOP_COMMAND='/usr/bin/startlxqt' ;;
        3) DESKTOP_NAME='MATE'; DESKTOP_COMMAND='/usr/bin/mate-session' ;;
        4) DESKTOP_NAME='KDE Plasma'; DESKTOP_COMMAND='/usr/bin/startplasma-x11' ;;
        *) fatal "Opção inválida: $choice (use 1, 2, 3 ou 4)." ;;
    esac
    DESKTOP_CHOICE="$choice"
    log "Desktop selecionado: $DESKTOP_NAME (opção $DESKTOP_CHOICE); K11 Turnip será instalado obrigatoriamente."
}

install_host_dependencies() {
    log 'Não instalar/remover Mesa/Vulkan Bionic legado; K11 será instalado no Debian/PRoot glibc.'
    run pkg update -y
    run pkg install -y x11-repo
    run pkg install -y proot-distro curl tar xz-utils binutils
    run pkg install -y termux-x11-nightly
    run pkg install -y pulseaudio
}

ensure_debian() {
    if [[ "$TEST_MODE" == 1 ]]; then
        log 'SIMULAÇÃO: garantir rootfs Debian glibc via proot-distro.'
        return 0
    fi
    if proot-distro login "$DEBIAN" -- /bin/true >/dev/null 2>&1; then
        log 'Rootfs Debian existente; será preservado.'
    else
        run proot-distro install "$DEBIAN"
    fi
}

prepare_wcp() {
    local archive="$WORK_DIR/turnip-v25.1.0-R2.wcp"
    if [[ -n "${SELFTEST_WCP:-}" ]]; then
        [[ -r "$SELFTEST_WCP" ]] || fatal "SELFTEST_WCP não pode ser lido: $SELFTEST_WCP"
        cp "$SELFTEST_WCP" "$archive"
    elif [[ "$TEST_MODE" == 1 ]]; then
        log 'SIMULAÇÃO: download do WCP omitido; sem gravações externas.'
        return 0
    else
        run curl -fL --retry 3 --retry-delay 2 "$WCP_URL" -o "$archive"
    fi
    local actual
    actual="$(sha256sum "$archive" | awk '{print $1}')"
    [[ "$actual" == "$WCP_SHA256" ]] || fatal "SHA-256 inesperado para o WCP: $actual"
    xz -t "$archive" || fatal 'O asset não é um XZ íntegro.'
    tar -tJf "$archive" > "$WORK_DIR/archive-list.txt" || fatal 'O WCP não contém um tar XZ válido.'
    for member in turnip/libvulkan_freedreno.so turnip/freedreno_icd.aarch64.json zink/libGL.so.1 zink/libglapi.so.0; do
        grep -Fxq "$member" "$WORK_DIR/archive-list.txt" || fatal "Arquivo obrigatório ausente no WCP: $member"
    done
    mkdir -p "$WORK_DIR/payload"
    tar -xJf "$archive" -C "$WORK_DIR/payload" \
        turnip/libvulkan_freedreno.so turnip/freedreno_icd.aarch64.json \
        zink/libGL.so.1 zink/libglapi.so.0
    command -v readelf >/dev/null 2>&1 || fatal 'readelf (binutils) é necessário para validar a arquitetura do driver.'
    readelf -h "$WORK_DIR/payload/turnip/libvulkan_freedreno.so" > "$WORK_DIR/elf-header.txt"
    grep -q 'AArch64' "$WORK_DIR/elf-header.txt" || fatal 'A arquitetura do driver não é AArch64.'
    readelf -d "$WORK_DIR/payload/turnip/libvulkan_freedreno.so" > "$WORK_DIR/elf-dynamic.txt"
    grep -q 'libc.so.6' "$WORK_DIR/elf-dynamic.txt" || fatal 'O binário não apresenta dependência glibc esperada.'
    grep -q 'libvulkan_freedreno.so' "$WORK_DIR/elf-dynamic.txt" || fatal 'SONAME do driver não confere.'
    log "WCP validado; SHA-256=$actual; ELF AArch64/glibc."
    log 'Payload extraído para análise/aplicação sem instalar o aplicativo Winlator.'
}

install_debian_packages() {
    local -a desktop_packages=()
    local -a application_packages=(
        firefox-esr vlc ffmpeg
        gstreamer1.0-libav gstreamer1.0-plugins-base
        gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
        gstreamer1.0-plugins-ugly gstreamer1.0-pulseaudio
        ristretto audacious pavucontrol pulseaudio-utils
        git wget curl python3 python3-flask
    )
    case "$DESKTOP_CHOICE" in
        1) desktop_packages=(xfce4 xfce4-terminal) ;;
        2) desktop_packages=(lxqt qterminal) ;;
        3) desktop_packages=(mate-desktop-environment-core mate-session-manager mate-terminal) ;;
        4) desktop_packages=(plasma-workspace plasma-desktop kwin-x11 konsole) ;;
        *) fatal "Desktop não selecionado antes da instalação: ${DESKTOP_CHOICE:-vazio}" ;;
    esac
    run proot-distro login "$DEBIAN" -- /usr/bin/apt-get update
    run proot-distro login "$DEBIAN" -- /usr/bin/apt-get install -y --no-install-recommends \
        "${desktop_packages[@]}" "${application_packages[@]}" dbus-x11 \
        libvulkan1 libdrm2 libxcb-dri3-0 libxcb1 libx11-xcb1 \
        libxcb-present0 libxcb-sync1 libxcb-randr0 libxcb-shm0 \
        libexpat1 libstdc++6 zlib1g vulkan-tools mesa-utils
}

install_python_demo() {
    cat > "$WORK_DIR/demo_python_app.py" <<'PY'
from flask import Flask

app = Flask(__name__)

@app.get("/")
def index():
    return "Linux no Termux/PRoot: Flask está funcionando.\n"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
PY
    run proot-distro login "$DEBIAN" -- /bin/mkdir -p /root/demo_python
    run proot-distro copy "$WORK_DIR/demo_python_app.py" "$DEBIAN:/root/demo_python/app.py"
    log 'Demo Python/Flask criado em /root/demo_python/app.py (porta 5000).'
}

install_k11_driver() {
    if [[ "$TEST_MODE" == 1 && -z "${SELFTEST_WCP:-}" ]]; then
        log "SIMULAÇÃO: instalar payload Turnip $RELEASE_TAG em /opt/k11-turnip; registrar ICD Vulkan."
        return 0
    fi
    local libdir=/opt/k11-turnip/lib
    local icd_src="$WORK_DIR/freedreno_icd.aarch64.json"
    mkdir -p "$WORK_DIR/payload/zink"
    cat > "$icd_src" <<'JSON'
{
  "file_format_version": "1.0.0",
  "ICD": {
    "library_path": "/opt/k11-turnip/lib/libvulkan_freedreno.so",
    "api_version": "1.4.303"
  }
}
JSON
    if [[ "$TEST_MODE" == 1 ]]; then
        log 'SELFTEST: payload extraído e manifesto ICD gerado; cópia para rootfs não executada.'
        return 0
    fi
    run proot-distro login "$DEBIAN" -- /bin/mkdir -p "$libdir" /usr/share/vulkan/icd.d
    run proot-distro copy "$WORK_DIR/payload/turnip/libvulkan_freedreno.so" "$DEBIAN:$libdir/libvulkan_freedreno.so"
    run proot-distro copy "$WORK_DIR/payload/zink/libGL.so.1" "$DEBIAN:$libdir/libGL.so.1"
    run proot-distro copy "$WORK_DIR/payload/zink/libglapi.so.0" "$DEBIAN:$libdir/libglapi.so.0"
    run proot-distro copy "$icd_src" "$DEBIAN:/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json"
    run proot-distro login "$DEBIAN" -- /bin/chmod 755 \
        "$libdir/libvulkan_freedreno.so" "$libdir/libGL.so.1" "$libdir/libglapi.so.0"
    log 'Driver K11 instalado isoladamente em /opt/k11-turnip; ICD Winlator original foi reescrito para esse caminho.'
}

write_launchers() {
    local desktop_command
    case "$DESKTOP_CHOICE" in
        1) desktop_command='/usr/bin/startxfce4' ;;
        2) desktop_command='/usr/bin/startlxqt' ;;
        3) desktop_command='/usr/bin/mate-session' ;;
        4) desktop_command='/usr/bin/startplasma-x11' ;;
        *) fatal "Não foi possível gerar launcher: opção inválida (${DESKTOP_CHOICE:-vazio})." ;;
    esac
    cat > "$HOME/start-linux.sh" <<'START'
#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
LOG="$HOME/termux-linux-session.log"
mkdir -p "$HOME/.local/run"
echo "$(date '+%F %T') Iniciando Debian/__DESKTOP_NAME__ em Termux:X11 :1" | tee -a "$LOG"
echo 'Iniciando PulseAudio para aplicativos de áudio...' | tee -a "$LOG"
if ! pulseaudio --check >/dev/null 2>&1; then
  pulseaudio --start --exit-idle-time=-1 >>"$LOG" 2>&1 || echo 'Aviso: PulseAudio não iniciou; a sessão gráfica seguirá sem áudio.' | tee -a "$LOG"
fi
if pulseaudio --check >/dev/null 2>&1 && command -v pactl >/dev/null 2>&1; then
  if ! pactl list short modules 2>/dev/null | grep -q module-native-protocol-tcp; then
    pactl load-module module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1 >/dev/null 2>>"$LOG" || echo 'Aviso: não foi possível habilitar a ponte PulseAudio local.' | tee -a "$LOG"
  fi
fi
if ! pgrep -x termux-x11 >/dev/null 2>&1; then
  termux-x11 :1 >>"$LOG" 2>&1 &
  echo $! > "$HOME/.local/run/termux-x11.pid"
fi
sleep 2
echo 'Abra o app Android Termux:X11 para visualizar a sessão.' | tee -a "$LOG"
exec proot-distro login debian --shared-tmp --shared-home \
  --env=DISPLAY=:1 \
  --env=VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json \
  --env=LD_LIBRARY_PATH=/opt/k11-turnip/lib:/usr/lib/aarch64-linux-gnu \
  --env=GALLIUM_DRIVER=zink \
  --env=MESA_LOADER_DRIVER_OVERRIDE=zink \
  --env=TU_DEBUG=noconform \
  --env=ZINK_DESCRIPTORS=lazy \
  --env=PULSE_SERVER=tcp:127.0.0.1 \
  -- /usr/bin/dbus-launch --exit-with-session __DESKTOP_COMMAND__
START
    sed -i "s|__DESKTOP_NAME__|$DESKTOP_NAME|g; s|__DESKTOP_COMMAND__|$desktop_command|g" "$HOME/start-linux.sh"
    chmod 700 "$HOME/start-linux.sh"
    cat > "$HOME/stop-linux.sh" <<'STOP'
#!/data/data/com.termux/files/usr/bin/bash
set -u
pidfile="$HOME/.local/run/termux-x11.pid"
if [[ -f "$pidfile" ]]; then
  pid="$(cat "$pidfile")"
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then kill -TERM "$pid"; fi
  rm -f "$pidfile"
fi
echo 'Encerrado apenas o Termux:X11 iniciado por este launcher. Feche a sessão gráfica no Debian.'
STOP
    chmod 700 "$HOME/stop-linux.sh"
    cat > "$HOME/verify-turnip.sh" <<'VERIFY'
#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
exec proot-distro login debian --shared-tmp \
  --env=VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json \
  --env=LD_LIBRARY_PATH=/opt/k11-turnip/lib:/usr/lib/aarch64-linux-gnu \
  -- /usr/bin/vulkaninfo --summary
VERIFY
    chmod 700 "$HOME/verify-turnip.sh"
    cat > "$HOME/verify-glx.sh" <<'VERIFY'
#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
exec proot-distro login debian --shared-tmp \
  --env=DISPLAY=:1 \
  --env=VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json \
  --env=LD_LIBRARY_PATH=/opt/k11-turnip/lib:/usr/lib/aarch64-linux-gnu \
  --env=GALLIUM_DRIVER=zink --env=MESA_LOADER_DRIVER_OVERRIDE=zink \
  -- /usr/bin/glxinfo -B
VERIFY
    chmod 700 "$HOME/verify-glx.sh"
    cat > "$HOME/verify-audio.sh" <<'VERIFY'
#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
exec proot-distro login debian --shared-tmp \
  --env=PULSE_SERVER=tcp:127.0.0.1 \
  -- /usr/bin/pactl info
VERIFY
    chmod 700 "$HOME/verify-audio.sh"
}

main() {
    check_environment
    choose_desktop
    install_host_dependencies
    ensure_debian
    prepare_wcp
    install_debian_packages
    install_k11_driver
    install_python_demo
    write_launchers
    log 'Preparação concluída. Firefox ESR, VLC/FFmpeg/codecs, Audacious, Ristretto, Git, Python/Flask e demo instalados no Debian.'
    log 'Verificações: ~/verify-turnip.sh; ~/verify-glx.sh com X11 aberto; ~/verify-audio.sh com a sessão iniciada.'
    log 'Teste visual requer Android, GPU Adreno e o app Termux:X11 aberto; não é atestado pela simulação.'
}

main "$@"
