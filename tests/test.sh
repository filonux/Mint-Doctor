#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/script/mint-doctor.sh"
TMP_DIR="${TMPDIR:-/tmp}/mint-doctor-tests-$$"
PASS=0
FAIL=0

cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT
mkdir -p "$TMP_DIR/bin" "$TMP_DIR/home-en" "$TMP_DIR/home-es"

pass() { printf 'ok - %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'not ok - %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
run_test() {
    local name="$1"; shift
    if "$@"; then pass "$name"; else fail "$name"; fi
}

syntax_test() {
    bash -n "$SCRIPT"
}

load_script() {
    MINT_DOCTOR_TEST_MODE=1 bash "$@"
}

locale_detection_test() {
    local detected
    detected=$(env -u MINT_DOCTOR_LANG LC_ALL=es_ES.UTF-8 LC_MESSAGES=en_US.UTF-8 LANG=en_US.UTF-8 LANGUAGE=es \
        MINT_DOCTOR_TEST_MODE=1 bash -c 'source "$1"; printf "%s" "$MINT_DOCTOR_LANG"' bash "$SCRIPT" 2>/dev/null)
    [[ "$detected" == es ]] || return 1
    detected=$(env -u MINT_DOCTOR_LANG LC_ALL=en_US.UTF-8 LC_MESSAGES=es_ES.UTF-8 LANG=en_US.UTF-8 LANGUAGE=en:es \
        MINT_DOCTOR_TEST_MODE=1 bash -c 'source "$1"; printf "%s" "$MINT_DOCTOR_LANG"' bash "$SCRIPT" 2>/dev/null)
    [[ "$detected" == en ]] || return 1
    detected=$(env -u MINT_DOCTOR_LANG LC_ALL= LC_MESSAGES=es_ES.UTF-8 LANG=en_US.UTF-8 \
        MINT_DOCTOR_TEST_MODE=1 bash -c 'source "$1"; printf "%s" "$MINT_DOCTOR_LANG"' bash "$SCRIPT" 2>/dev/null)
    [[ "$detected" == es ]] || return 1
    detected=$(env -u MINT_DOCTOR_LANG LC_ALL= LC_MESSAGES= LANG=es_ES.UTF-8 \
        MINT_DOCTOR_TEST_MODE=1 bash -c 'source "$1"; printf "%s" "$MINT_DOCTOR_LANG"' bash "$SCRIPT" 2>/dev/null)
    [[ "$detected" == es ]] || return 1
    detected=$(env -u MINT_DOCTOR_LANG LC_ALL=C LC_MESSAGES=es_ES.UTF-8 LANG=en_US.UTF-8 LANGUAGE=es \
        MINT_DOCTOR_TEST_MODE=1 bash -c 'source "$1"; printf "%s" "$MINT_DOCTOR_LANG"' bash "$SCRIPT" 2>/dev/null)
    [[ "$detected" == en ]] || return 1
    detected=$(env -u MINT_DOCTOR_LANG LC_ALL=C.UTF-8 LC_MESSAGES=es_ES.UTF-8 LANG=en_US.UTF-8 LANGUAGE=es \
        MINT_DOCTOR_TEST_MODE=1 bash -c 'source "$1"; printf "%s" "$MINT_DOCTOR_LANG"' bash "$SCRIPT" 2>/dev/null)
    [[ "$detected" == en ]] || return 1
    detected=$(env -u MINT_DOCTOR_LANG LC_ALL=POSIX LC_MESSAGES=es_ES.UTF-8 LANG=en_US.UTF-8 LANGUAGE=es \
        MINT_DOCTOR_TEST_MODE=1 bash -c 'source "$1"; printf "%s" "$MINT_DOCTOR_LANG"' bash "$SCRIPT" 2>/dev/null)
    [[ "$detected" == en ]] || return 1
    detected=$(MINT_DOCTOR_LANG=en LC_ALL=es_ES.UTF-8 LANGUAGE=es MINT_DOCTOR_TEST_MODE=1 \
        bash -c 'source "$1"; printf "%s" "$MINT_DOCTOR_LANG"' bash "$SCRIPT" 2>/dev/null)
    [[ "$detected" == en ]] || return 1
    detected=$(MINT_DOCTOR_LANG=es LC_ALL=C MINT_DOCTOR_TEST_MODE=1 \
        bash -c 'source "$1"; printf "%s" "$MINT_DOCTOR_LANG"' bash "$SCRIPT" 2>/dev/null)
    [[ "$detected" == es ]] || return 1
    detected=$(MINT_DOCTOR_LANG=de LC_ALL=es_ES.UTF-8 MINT_DOCTOR_TEST_MODE=1 \
        bash -c 'source "$1"; printf "%s" "$MINT_DOCTOR_LANG"' bash "$SCRIPT" 2>/dev/null)
    [[ "$detected" == en ]]
}

root_logging_test() {
    local home="$TMP_DIR/root-home" output
    mkdir -p "$home"
    output=$(HOME="$home" MINT_DOCTOR_LANG=en bash "$SCRIPT" --help) || return 1
    [[ ! -e "$home/.mint-doctor" ]]
}

help_version_test() {
    local en es
    en=$(MINT_DOCTOR_LANG=en bash "$SCRIPT" --help) || return 1
    es=$(MINT_DOCTOR_LANG=es bash "$SCRIPT" --help) || return 1
    grep -q 'Forces the interface language' <<<"$en" || return 1
    grep -q 'Fuerza el idioma de la interfaz' <<<"$es" || return 1
    grep -q 'GPLv3' <<<"$en" || return 1
    grep -q 'GPLv3' <<<"$es" || return 1
    [[ "$(MINT_DOCTOR_LANG=en bash "$SCRIPT" --version)" == *'Filonux · GPLv3' ]] || return 1
    [[ "$(MINT_DOCTOR_LANG=es bash "$SCRIPT" --version)" == *'Filonux · GPLv3' ]]
}

cli_language_test() {
    local forced_env forced_arg invalid
    forced_env=$(MINT_DOCTOR_LANG=es bash "$SCRIPT" --lang en --help) || return 1
    grep -q 'Forces the interface language' <<<"$forced_env" || return 1
    forced_arg=$(MINT_DOCTOR_LANG=en bash "$SCRIPT" --lang=es --help) || return 1
    grep -q 'Fuerza el idioma de la interfaz' <<<"$forced_arg" || return 1
    invalid=$(MINT_DOCTOR_LANG=en bash "$SCRIPT" --lang=de --help) || return 1
    grep -q 'Forces the interface language' <<<"$invalid"
}

yes_no_test() {
    MINT_DOCTOR_TEST_MODE=1 MINT_DOCTOR_LANG=en bash -c 'source "$1"; printf "y\n" | _ask_yes_no_loop "Continue?"' bash "$SCRIPT" || return 1
    ! MINT_DOCTOR_TEST_MODE=1 MINT_DOCTOR_LANG=en bash -c 'source "$1"; printf "n\n" | _ask_yes_no_loop "Continue?"' bash "$SCRIPT"
    MINT_DOCTOR_TEST_MODE=1 MINT_DOCTOR_LANG=es bash -c 'source "$1"; printf "s\n" | _ask_yes_no_loop "¿Continuar?"' bash "$SCRIPT" || return 1
    ! MINT_DOCTOR_TEST_MODE=1 MINT_DOCTOR_LANG=es bash -c 'source "$1"; printf "\n" | _ask_yes_no_loop "¿Continuar?"' bash "$SCRIPT"
}

catalog_translation_test() {
    python3 - "$SCRIPT" <<'PY'
import re, subprocess, sys
from pathlib import Path
script = Path(sys.argv[1]).read_text()
funcs = r'(?:msg_ok|msg_err|msg_warn|msg_info|section_header|ensure_sudo|ask_yes_no|ask_yes_no_always|run_step|run_step_sudo)'
vals = []
for m in re.finditer(funcs + r'\s+"((?:\\.|[^"\\])*)"', script):
    x = m.group(1).replace('\\"', '"')
    if x and '${' not in x and '$(' not in x and x not in ('$1', '$reason', '$desc') and not x.strip().startswith('chown root:root'):
        vals.append(x)
vals = list(dict.fromkeys(vals))
cmd = ['bash', '-c', 'source "$1"; for x in "${@:2}"; do y=$(t "$x"); [[ "$x" != "$y" ]] || printf "UNTRANSLATED:%s\\n" "$x"; done', 'bash', str(Path(sys.argv[1])), *vals]
env = dict(__import__('os').environ)
env['MINT_DOCTOR_TEST_MODE'] = '1'; env['MINT_DOCTOR_LANG'] = 'en'
r = subprocess.run(cmd, text=True, capture_output=True, env=env)
if r.returncode != 0 or r.stdout:
    sys.stderr.write(r.stdout)
    raise SystemExit(1)
print(f'checked {len(vals)} UI strings')
PY
}

run_step_catalog_test() {
    python3 - "$SCRIPT" <<'PY'
import re, subprocess, sys, os
from pathlib import Path
script = Path(sys.argv[1]).read_text()
vals=[]
for m in re.finditer(r'run_step(?:_sudo)?\s+"((?:\\.|[^"\\])*)"(?:\s+"((?:\\.|[^"\\])*)")?', script):
    for x in m.groups():
        if x and '${' not in x and '$(' not in x and not x.startswith('$'):
            vals.append(x.replace('\\"','"'))
vals=list(dict.fromkeys(vals))
cmd=['bash','-c','source "$1"; for x in "${@:2}"; do y=$(t "$x"); [[ "$x" != "$y" ]] || printf "UNTRANSLATED:%s\\n" "$x"; done','bash',str(Path(sys.argv[1])),*vals]
env=os.environ.copy(); env['MINT_DOCTOR_TEST_MODE']='1'; env['MINT_DOCTOR_LANG']='en'
r=subprocess.run(cmd,text=True,capture_output=True,env=env)
if r.returncode or r.stdout:
    sys.stderr.write(r.stdout); raise SystemExit(1)
print(f'checked {len(vals)} repair descriptions')
PY
}

direct_ui_translation_test() {
    MINT_DOCTOR_TEST_MODE=1 MINT_DOCTOR_LANG=en bash -c '
        source "$1"
        assert_t() { local out; out=$(t "$1"); [[ "$out" == "$2" ]] || { echo "expected [$2] in [$out]" >&2; return 1; }; }
        assert_t "Disco /:" "Disk /:"
        assert_t "Esto suele ocurrir tras un apagado brusco o un Administrador de actualizaciones colgado." "This usually happens after an abrupt shutdown or a hung Update Manager."
        assert_t "usa" "uses"
        assert_t "Clave:" "Key:"
        assert_t "Repositorio:" "Repository:"
        assert_t "no identificado, revisa el log" "not identified; check the log"
    ' bash "$SCRIPT"
}

dynamic_translation_test() {
    MINT_DOCTOR_TEST_MODE=1 MINT_DOCTOR_LANG=en bash -c '
        source "$1"
        assert_t() { local out; out=$(t "$1"); [[ "$out" == *"$2"* ]] || { echo "expected [$2] in [$out]" >&2; return 1; }; }
        assert_t "Esta acción necesita permisos de administrador (comprobar si los archivos de bloqueo de apt/dpkg siguen en uso)." "check whether apt/dpkg lock files are still in use"
        assert_t "Caché de paquetes descargados (APT): 8.0K (0 paquetes .deb)" "Downloaded package cache (APT): 8.0K"
        assert_t "Tamaño del registro del sistema (journal): 0B" "System journal size: 0B"
        assert_t "Hay 2 kernels antiguos ocupando espacio (se conserva el actual: 6.18.0)" "There are 2 old kernels"
        assert_t "Hay 2 servicio(s) systemd en estado \"failed\":" "There are 2 systemd service(s)"
        assert_t "Hay 3 acceso(s) directo(s) en el escritorio sin marcar como confiables:" "There are 3 desktop shortcut(s)"
        assert_t "Salud de la batería (BAT0): 91% de su capacidad de fábrica." "Battery health (BAT0): 91% of its factory capacity."
        assert_t "La instantánea más reciente tiene 5 días. Si esperabas copias más frecuentes," "The most recent snapshot is 5 days old."
        assert_t "La instantánea más reciente tiene 5 día(s)." "The most recent snapshot is 5 days old."
        assert_t "Estos módulos DKMS no están instalados para el kernel en uso (6.18.0):" "These DKMS modules are not installed for the current kernel"
        assert_t "/dev/sda: S.M.A.R.T. correcto." "/dev/sda: S.M.A.R.T. OK."
        assert_t "/dev/sda: S.M.A.R.T. informa un problema → critical" "/dev/sda: S.M.A.R.T. reports a problem → critical"
        assert_t "Esta sesión se ha iniciado en modo \"Cinnamon (Software Rendering)\", sin aceleración 3D." "This session started in \"Cinnamon (Software Rendering)\" mode"
        assert_t "Estás en una máquina virtual de VirtualBox, pero el módulo \"vboxguest\" de las Guest" "You are in a VirtualBox virtual machine"
        assert_t "compilados: el Gestor de controladores puede decir \"instalado\" aunque el módulo nunca cargue." "built: Driver Manager may say \"installed\""
        assert_t "Y /boot solo tiene 120MB libres: causa muy habitual de que un" "/boot has only 120MB free"
        assert_t "pkexec (/usr/bin/pkexec) ha perdido el bit setuid o su propietario no es root." "pkexec (/usr/bin/pkexec) has lost its setuid bit"
        assert_t "sudo (/usr/bin/sudo) ha perdido su bit setuid. Ni este script ni sudo pueden arreglarlo:" "sudo (/usr/bin/sudo) has lost its setuid bit"
        assert_t "anterior de Mint/Ubuntu (esta es Mint 22.3 \"Zena\", base Ubuntu \"noble\"):" "earlier Mint/Ubuntu release"
        assert_t "Si alguna de esas líneas sí publica paquetes para \"noble\", edítala a" "If any of those lines actually publish packages for \"noble\""
        assert_t "El repositorio OFICIAL de Mint en /etc/apt/sources.list.d/official.list usa el nombre en clave \"noble\"," "The OFFICIAL Mint repository in /etc/apt/sources.list.d/official.list uses the codename \"noble\"," 
        assert_t "Aviso: no se ha podido crear el registro; esta sesión continúa sin guardar registro." "Warning: could not create the log; continuing without a log."
    ' bash "$SCRIPT"
}

dry_run_test() {
    command -v runuser >/dev/null 2>&1 || return 2
    command -v timeout >/dev/null 2>&1 || return 2
    local rc_en rc_es
    set +e
    runuser -u nobody -- env HOME="$TMP_DIR/home-en" USER=nobody LOGNAME=nobody MINT_DOCTOR_LANG=en timeout 120s bash "$SCRIPT" --dry-run --auto >"$TMP_DIR/en.out" 2>"$TMP_DIR/en.err"
    rc_en=$?
    runuser -u nobody -- env HOME="$TMP_DIR/home-es" USER=nobody LOGNAME=nobody MINT_DOCTOR_LANG=es timeout 120s bash "$SCRIPT" --dry-run --auto >"$TMP_DIR/es.out" 2>"$TMP_DIR/es.err"
    rc_es=$?
    set -e
    (( rc_en == 0 || rc_en == 1 )) || return 1
    (( rc_es == 0 || rc_es == 1 )) || return 1
    grep -q 'Network connectivity' "$TMP_DIR/en.out" || return 1
    grep -q 'Conectividad de red' "$TMP_DIR/es.out" || return 1
    grep -q 'System backups (Timeshift)' "$TMP_DIR/en.out" || return 1
    grep -q 'Copias de seguridad del sistema (Timeshift)' "$TMP_DIR/es.out" || return 1
    ! grep -q 'SIMULACIÓN' "$TMP_DIR/en.out" || return 1
    ! grep -q 'Network connectivity' "$TMP_DIR/es.out" || return 1
}

command_equivalence_test() {
    local en_cmd es_cmd
    sed -n 's/.*Would run: //p' "$TMP_DIR/en.out" > "$TMP_DIR/en.commands"
    sed -n 's/.*Se ejecutaría: //p' "$TMP_DIR/es.out" > "$TMP_DIR/es.commands"
    diff -u "$TMP_DIR/en.commands" "$TMP_DIR/es.commands" >/dev/null
}

runtime_output_language_test() {
    command -v runuser >/dev/null 2>&1 || return 2
    local out_en out_es
    out_en=$(runuser -u nobody -- env HOME="$TMP_DIR/home-en-runtime" USER=nobody LOGNAME=nobody MINT_DOCTOR_LANG=en NO_COLOR=1 bash "$SCRIPT" --dry-run --auto 2>/dev/null || true)
    out_es=$(runuser -u nobody -- env HOME="$TMP_DIR/home-es-runtime" USER=nobody LOGNAME=nobody MINT_DOCTOR_LANG=es NO_COLOR=1 bash "$SCRIPT" --dry-run --auto 2>/dev/null || true)
    grep -q 'Used%' <<<"$out_en" || return 1
    ! grep -q 'Uso%' <<<"$out_en" || return 1
    grep -q 'Uso%' <<<"$out_es" || return 1
    ! grep -q 'Used%' <<<"$out_es" || return 1
    python3 -c 'import sys; sys.exit(1 if any(c in sys.stdin.read() for c in "áéíóúÁÉÍÓÚñÑ¿¡") else 0)' <<<"$out_en" || return 1
}

interactive_aesthetic_test() {
    command -v runuser >/dev/null 2>&1 || return 2
    command -v script >/dev/null 2>&1 || return 2
    local out_file cleaned max_len
    out_file="$TMP_DIR/menu-en.out"
    runuser -u nobody -- env HOME="$TMP_DIR/home-menu" USER=nobody LOGNAME=nobody MINT_DOCTOR_LANG=en TERM=xterm NO_COLOR=1 COLUMNS=90 \
        script -qefc "bash '$SCRIPT'" /dev/null <<< '0' >"$out_file" 2>"$TMP_DIR/menu-en.err" || true
    cleaned="$TMP_DIR/menu-en.clean"
    python3 - "$out_file" "$cleaned" <<'PY2'
import re, sys
from pathlib import Path
text=Path(sys.argv[1]).read_text(errors='replace')
text=re.sub(r'\x1b\[[0-9;?]*[ -/]*[@-~]', '', text).replace('\r','')
Path(sys.argv[2]).write_text(text)
PY2
    grep -q 'System information' "$cleaned" || return 1
    grep -q 'Choose an option \[0-10\]:' "$cleaned" || return 1
    ! grep -Fq '${LOG_DIR}' "$cleaned" || return 1
    max_len=$(python3 - "$cleaned" <<'PY3'
from pathlib import Path
import sys
print(max((len(line) for line in Path(sys.argv[1]).read_text().splitlines()), default=0))
PY3
)
    (( max_len <= 84 ))
}

aesthetic_test() {
    local out width
    out=$(MINT_DOCTOR_LANG=en NO_COLOR=1 bash "$SCRIPT" --help) || return 1
    grep -q '^Mint-Doctor v' <<<"$out" || return 1
    grep -q 'Forces the interface language' <<<"$out" || return 1
    ! grep -q $'\r' <<<"$out" || return 1
    ! grep -qE '[[:space:]]$' <<<"$out" || return 1
    out=$(MINT_DOCTOR_LANG=es NO_COLOR=1 bash "$SCRIPT" --help) || return 1
    grep -q 'Fuerza el idioma de la interfaz' <<<"$out" || return 1
    ! grep -q $'\r' <<<"$out" || return 1
    width=$(MINT_DOCTOR_LANG=en NO_COLOR=1 TERM=xterm COLUMNS=80 bash "$SCRIPT" --help | awk 'length > 84 { bad=1 } END { print bad ? 1 : 0 }')
    [[ "$width" == 0 ]]
}

project_shape_test() {
    [[ -f "$SCRIPT" ]] || return 1
    [[ ! -d "$ROOT_DIR/script/lang" ]] || return 1
    [[ ! -e "$ROOT_DIR/script/mint-doctor-en.sh" ]] || return 1
    [[ ! -e "$ROOT_DIR/script/mint-doctor-es.sh" ]] || return 1
}

raw_spanish_ui_test() {
    ! grep -nE '^[[:space:]]*(echo|printf)[^#]*(Hecho|Falló|Sistema detectado|problema\(s\) detectado|usados de|usado \()' "$SCRIPT"
}

run_test 'Bash syntax' syntax_test
run_test 'locale detection and explicit overrides' locale_detection_test
run_test 'help and version in both languages' help_version_test
run_test 'root check happens before logging' root_logging_test
run_test 'CLI language overrides and fallback' cli_language_test
run_test 'yes/no parser accepts both Spanish and English' yes_no_test
run_test 'all static UI strings have English translations' catalog_translation_test
run_test 'repair descriptions have English translations' run_step_catalog_test
run_test 'direct UI strings are translated completely' direct_ui_translation_test
run_test 'dynamic UI strings are translated completely' dynamic_translation_test
run_test 'end-to-end dry-run in English and Spanish' dry_run_test
run_test 'English and Spanish dry-runs plan the same commands' command_equivalence_test
run_test 'runtime output keeps EN and ES labels isolated' runtime_output_language_test
run_test 'interactive menu remains clean and within terminal width' interactive_aesthetic_test
run_test 'aesthetic output remains clean and within terminal width' aesthetic_test
run_test 'main program remains a single .sh file' project_shape_test
run_test 'no obvious untranslated Spanish UI remnants' raw_spanish_ui_test

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
exit "$FAIL"
