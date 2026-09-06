#!/usr/bin/env bash
# MENU: Mint-Doctor
# DESCRIPTION: Autorepair tool for Linux Mint 22.3 Cinnamon
# TERMINAL: true
#
# Copyright (C) 2026 Filonux
# Licencia: GNU GPLv3. Consulte LICENSE.txt para el texto completo.
#
# Uso:
#   ./mint-doctor.sh            Modo interactivo
#   ./mint-doctor.sh --dry-run  Modo simulación
#   ./mint-doctor.sh --auto     Escaneo automático
#
# No ejecutar como root. El script pedirá sudo solo cuando una acción concreta
# lo necesite.

# --------------------------------------------------------------------
# Locale UTF-8 para que pad_right()/draw_box() cuenten caracteres, no bytes
# --------------------------------------------------------------------
# Solo se toca LC_CTYPE (no LC_ALL, para no traducir la salida de apt/dpkg).
# Si no hay ningún locale UTF-8 disponible, se sigue sin más: es cosmético.
if [[ "$(locale charmap 2>/dev/null)" != "UTF-8" ]]; then
    for _cand in en_US.UTF-8 es_ES.UTF-8 C.UTF-8 C.utf8; do
        if locale -a 2>/dev/null | grep -qix "$_cand"; then
            export LC_CTYPE="$_cand"
            break
        fi
    done
    unset _cand
fi

# --------------------------------------------------------------------
# Language
# --------------------------------------------------------------------
_language_tag() {
    local tag="${1,,}"
    tag="${tag%%:*}"
    tag="${tag%%.*}"
    tag="${tag%%@*}"
    case "$tag" in
        es|es_*|es-* ) printf 'es' ;;
        en|en_*|en-* ) printf 'en' ;;
    esac
}

set_language() {
    local requested="${1:-${MINT_DOCTOR_LANG:-}}" locale_name language_from_env
    case "${requested,,}" in
        es|es_*|es-* ) MINT_DOCTOR_LANG=es ;;
        en|en_*|en-* ) MINT_DOCTOR_LANG=en ;;
        '' )
            locale_name="${LC_ALL:-${LC_MESSAGES:-${LANG:-C}}}"
            if [[ "$locale_name" =~ ^([Cc]|[Pp][Oo][Ss][Ii][Xx])([.@_-].*)?$ ]]; then
                MINT_DOCTOR_LANG=en
            else
                language_from_env="$(_language_tag "${LANGUAGE:-}")"
                case "$language_from_env" in
                    es|en) MINT_DOCTOR_LANG="$language_from_env" ;;
                    *)
                        case "${locale_name,,}" in
                            es|es_*|es-* ) MINT_DOCTOR_LANG=es ;;
                            * ) MINT_DOCTOR_LANG=en ;;
                        esac
                        ;;
                esac
            fi
            ;;
        * ) MINT_DOCTOR_LANG=en ;;
    esac
    export MINT_DOCTOR_LANG
}

set_language

# Alterna es<->en desde el menú interactivo, sin reiniciar el script ni
# necesitar --lang. msg_ok ya hace de no-op sobre un texto que no esté en
# español (ver t()), así que cada rama puede escribir directamente el
# mensaje ya en su idioma final.
toggle_language() {
    if [[ "$MINT_DOCTOR_LANG" == es ]]; then
        set_language en
        msg_ok "Language switched to English."
    else
        set_language es
        msg_ok "Idioma cambiado a español."
    fi
}

# Translate complete UI messages without invoking external tools.
t() {
    local text="$1"
    [[ "$MINT_DOCTOR_LANG" != en ]] && { printf '%s' "$text"; return; }
    case "$text" in
        "Hecho: "*) printf 'Done: %s' "$(t "${text#Hecho: }")"; return ;;
        "Falló: "*) printf 'Failed: %s' "$(t "${text#Falló: }")"; return ;;
        "No se ha podido aplicar: "*) printf 'Could not apply: %s' "$(t "${text#No se ha podido aplicar: }")"; return ;;
        "Esta acción necesita permisos de administrador ("*)
            local reason="${text#Esta acción necesita permisos de administrador (}"; reason="${reason:0:${#reason}-2}"
            printf 'This action requires administrator privileges (%s).' "$(t "$reason")"; return ;;
        "No se han podido obtener permisos de administrador ("*)
            local reason="${text#No se han podido obtener permisos de administrador (}"; reason="${reason:0:${#reason}-2}"
            printf 'Could not obtain administrator privileges (%s).' "$(t "$reason")"; return ;;
        "Copia de seguridad guardada en: "*) printf 'Backup saved to: %s' "${text#Copia de seguridad guardada en: }"; return ;;
        "Registro completo guardado en: "*) printf 'Full log saved to: %s' "${text#Registro completo guardado en: }"; return ;;
        "No se ha podido crear el registro en "*) printf 'Warning: could not create the log at %s; this session will continue without a log.' "${text#No se ha podido crear el registro en }"; return ;;
        "Aplicando: comentar referencia a "*) printf 'Applying: comment reference to %s' "${text#Aplicando: comentar referencia a }"; return ;;
        "Se comentarían las líneas/bloques de: "*) printf 'The following lines/blocks would be commented: %s' "${text#Se comentarían las líneas/bloques de: }"; return ;;
        "Se marcarían como confiables: "*) printf 'Would be marked as trusted: %s' "${text#Se marcarían como confiables: }"; return ;;
        "importar clave GPG "*) printf 'import GPG key %s' "${text#importar clave GPG }"; return ;;
        "instalar linux-headers-"*) printf 'install linux-headers-%s' "${text#instalar linux-headers-}"; return ;;
        "Caché de paquetes descargados (APT): "*)
            local cache_tail="${text#Caché de paquetes descargados (APT): }"
            cache_tail="${cache_tail/ paquetes .deb/ .deb packages}"
            printf 'Downloaded package cache (APT): %s' "$cache_tail"; return ;;
        "Tamaño del registro del sistema (journal): "*)
            local journal_tail="${text#Tamaño del registro del sistema (journal): }"
            [[ "$journal_tail" == desconocido ]] && journal_tail=unknown
            printf 'System journal size: %s' "$journal_tail"; return ;;
        "Caché de miniaturas: "*) printf 'Thumbnail cache: %s' "${text#Caché de miniaturas: }"; return ;;
        "La papelera contiene "*) printf 'The trash contains %s' "${text#La papelera contiene }" | sed 's/ sin vaciar\./ without being emptied./'; return ;;
        "Hay "*" kernels antiguos ocupando espacio (se conserva el actual: "*)
            local kernels_tail="${text#Hay }"; kernels_tail="${kernels_tail/kernels antiguos ocupando espacio (se conserva el actual: /old kernels taking up space (keeping the current: }"
            printf 'There are %s' "$kernels_tail"; return ;;
        "Hay "*" servicio(s) systemd en estado \"failed\":"*)
            printf 'There are %s' "${text#Hay }" | sed 's/ servicio(s) systemd en estado \"failed\":/ systemd service(s) in "failed" state:/'; return ;;
        "Hay "*" acceso(s) directo(s) en el escritorio sin marcar como confiables:"*)
            printf 'There are %s' "${text#Hay }" | sed 's/ acceso(s) directo(s) en el escritorio sin marcar como confiables:/ desktop shortcut(s) not marked as trusted:/'; return ;;
        "Estos módulos DKMS no están instalados para el kernel en uso ("*) printf 'These DKMS modules are not installed for the current kernel (%s' "${text#Estos módulos DKMS no están instalados para el kernel en uso (}"; return ;;
        "El driver nvidia-driver-470 es compatible con el kernel en uso ("*) printf 'The nvidia-driver-470 driver is compatible with the current kernel (%s' "${text#El driver nvidia-driver-470 es compatible con el kernel en uso (}"; return ;;
        ""*", de la serie 6.14 o superior, que ya no admite ese driver."*) printf '%s, from the 6.14 series or newer, which no longer supports that driver.' "${text%%, de la serie 6.14 o superior, que ya no admite ese driver.*}"; return ;;
        "/dev/"*": S.M.A.R.T. correcto.") printf '%s: S.M.A.R.T. OK.' "${text%%: S.M.A.R.T. correcto.}"; return ;;
        "/dev/"*": S.M.A.R.T. informa un problema → "*) printf '%s: S.M.A.R.T. reports a problem → %s' "${text%%: S.M.A.R.T. informa un problema → *}" "${text#*: S.M.A.R.T. informa un problema → }"; return ;;
        "/dev/"*": no se ha podido determinar el estado S.M.A.R.T. "*) printf '%s: could not determine S.M.A.R.T. status %s' "${text%%: no se ha podido determinar el estado S.M.A.R.T. *}" "${text#*: no se ha podido determinar el estado S.M.A.R.T. }"; return ;;
        "Salud de la batería ("*)
            local battery_tail="${text#Salud de la batería (}"
            battery_tail="${battery_tail/ de su capacidad de fábrica./ of its factory capacity.}"
            printf 'Battery health (%s' "$battery_tail"; return ;;
        "Estas 'spices' de terceros no declaran soporte para Cinnamon "*) printf "These third-party Cinnamon 'spices' do not declare support for Cinnamon %s" "${text#Estas 'spices' de terceros no declaran soporte para Cinnamon }"; return ;;
        "La instantánea más reciente tiene "*" días. Si esperabas copias más frecuentes,"*)
            local snapshot_tail="${text#La instantánea más reciente tiene }"
            snapshot_tail="${snapshot_tail/ días. Si esperabas copias más frecuentes,/ days old. If you expected more frequent backups,}"
            printf '%s' "The most recent snapshot is $snapshot_tail"; return ;;
        "La instantánea más reciente tiene "*" día(s)."*)
            local snapshot_tail="${text#La instantánea más reciente tiene }"
            snapshot_tail="${snapshot_tail/ día(s)./ days old.}"
            printf 'The most recent snapshot is %s' "$snapshot_tail"; return ;;
        "No se ha podido importar la clave "*" (sin permisos de administrador).") printf 'Could not import GPG key %s (administrator privileges unavailable).' "${text#No se ha podido importar la clave }" | sed 's/ (sin permisos de administrador).*)/ (administrator privileges unavailable)./'; return ;;
        "Y /boot solo tiene "*"MB libres: causa muy habitual de que un"*)
            local boot_tail="${text#Y /boot solo tiene }"
            boot_tail="${boot_tail/MB libres: causa muy habitual de que un/MB free: a very common reason for a}"
            printf '/boot has only %s' "$boot_tail"; return ;;
        "pkexec ("*)
            local pk_tail="${text#pkexec (}"
            pk_tail="${pk_tail/ ha perdido el bit setuid o su propietario no es root./ has lost its setuid bit or its owner is not root.}"
            printf 'pkexec (%s' "$pk_tail"; return ;;
        "sudo ("*)
            local sudo_tail="${text#sudo (}"
            sudo_tail="${sudo_tail/ ha perdido su bit setuid. Ni este script ni sudo pueden arreglarlo:/ has lost its setuid bit. Neither this script nor sudo can fix it:}"
            printf 'sudo (%s' "$sudo_tail"; return ;;
        "anterior de Mint/Ubuntu ("*)
            local release_tail="${text#anterior de Mint/Ubuntu (}"
            release_tail="${release_tail/esta es Mint 22.3 /this is Mint 22.3 }"
            printf 'earlier Mint/Ubuntu release (%s' "$release_tail"; return ;;
        "Si alguna de esas líneas sí publica paquetes para "*)
            local source_tail="${text#Si alguna de esas líneas sí publica paquetes para }"
            source_tail="${source_tail/, edítala a/; edit it manually from the Software Sources dialog.}"
            printf 'If any of those lines actually publish packages for %s' "$source_tail"; return ;;
        "El repositorio OFICIAL de Mint en "*)
            local repo_tail="${text#El repositorio OFICIAL de Mint en }"
            repo_tail="${repo_tail/ usa el nombre en clave / uses the codename }"
            printf 'The OFFICIAL Mint repository in %s' "$repo_tail"; return ;;
        "pero /etc/os-release identifica este sistema como "*)
            local os_tail="${text#pero /etc/os-release identifica este sistema como }"
            os_tail="${os_tail/. Suele significar que una/. This usually means a}"
            printf 'but /etc/os-release identifies this system as %s' "$os_tail"; return ;;
    esac
    if [[ -n "${MINT_DOCTOR_EN[$text]+x}" ]]; then
        printf '%s' "${MINT_DOCTOR_EN[$text]}"
    else
        printf '%s' "$text"
    fi
}

declare -Ag MINT_DOCTOR_EN=(
    [pregunta]=prompt
    ['Hecho: ${desc}']='Done: ${desc}'
    ['Falló: ${desc}']='Failed: ${desc}'
    ['$reason']='$reason'
    ['$desc']='$desc'
    ['No se ha podido aplicar: ${desc} (sin permisos de administrador).']='Could not apply: ${desc} (administrator privileges unavailable).'
    ['Esta acción necesita permisos de administrador (${reason}).']='This action requires administrator privileges (${reason}).'
    ['No se han podido obtener permisos de administrador (${reason}).']='Could not obtain administrator privileges (${reason}).'
    ['Omitido por el usuario.']='Skipped by the user.'
    ['Omitido (sin terminal para confirmar, p. ej. ejecución desatendida).']='Skipped (no terminal available for confirmation, e.g. unattended execution).'
    ['Información del sistema']='System information'
    ['La sesión Wayland de Cinnamon aún es experimental en esta versión; si notas']='Cinnamon'"'"'s Wayland session is still experimental in this version; if you notice'
    ['cuelgues o parpadeos, prueba \']='freezes or flickering, try \'
    ['Snap está bloqueado de fábrica (política de Mint desde la versión 20; ver']='Snap is blocked by default (Mint policy since version 20; see'
    ['/etc/apt/preferences.d/nosnap.pref). \']='/etc/apt/preferences.d/nosnap.pref). \'
    ['ese archivo exista; solo hace falta tocarlo si necesitas una app que solo exista como Snap.']='this file exists; only change it if you need an app that is available only as Snap.'
    ['Esta sección es solo informativa, no realiza cambios.']='This section is informational only; it makes no changes.'
    ['Paquetes y gestor APT/dpkg']='Packages and APT/dpkg'
    ['Comprobando bloqueos de APT/dpkg...']='Checking APT/dpkg locks...'
    ['No se puede comprobar con seguridad si los archivos de bloqueo de apt/dpkg siguen en uso:']='Could not safely determine whether apt/dpkg lock files are in use:'
    ['falta el comando '"'"'fuser'"'"' (paquete psmisc). Sin él, Mint-Doctor no puede distinguir un']='the '"'"'fuser'"'"' command is missing (psmisc package). Without it, Mint-Doctor cannot distinguish a'
    ['bloqueo obsoleto de uno real, así que no ofrece eliminarlos a ciegas.']='stale lock from one in use, so it will not offer to remove locks blindly.'
    ['¿Instalar psmisc para poder comprobar esto de forma segura?']='Install psmisc to check this safely?'
    ['instalar psmisc']='install psmisc'
    ['comprobar si los archivos de bloqueo de apt/dpkg siguen en uso']='check whether apt/dpkg lock files are still in use'
    ['Se han encontrado archivos de bloqueo que ningún proceso está usando:']='Found lock files that are not used by any process:'
    ['¿Eliminar estos bloqueos obsoletos?']='Delete these stale locks?'
    ['eliminar bloqueos de apt/dpkg']='remove stale apt/dpkg locks'
    ['No hay bloqueos obsoletos.']='No stale locks found.'
    ['No se ha podido comprobar el estado de los bloqueos (sin permisos de administrador).']='Could not check lock status (administrator privileges unavailable).'
    ['Comprobando paquetes a medio instalar/configurar...']='Checking partially installed/configured packages...'
    ['Hay paquetes en un estado inconsistente (instalación interrumpida):']='Packages are in an inconsistent state (interrupted installation):'
    ['Y /boot solo tiene ${boot_avail_mb}MB libres: causa muy habitual de que un']='/boot has only ${boot_avail_mb}MB free: a very common reason for a'
    ['linux-image/linux-headers se quede a medio configurar. Si el paso de abajo']='linux-image/linux-headers package to remain half-configured. If the step below'
    ['falla, libera espacio ahí (opción 4, o elimina kernels antiguos) y repite.']='fails, free space there (option 4, or remove old kernels) and try again.'
    ['¿Reconfigurar los paquetes pendientes con '"'"'dpkg --configure -a'"'"'?']='Reconfigure pending packages with '"'"'dpkg --configure -a'"'"'?'
    ['reconfigurar paquetes']='reconfigure pending packages'
    ['No hay instalaciones a medias.']='No partially installed packages found.'
    ['Comprobando dependencias rotas...']='Checking broken dependencies...'
    ['comprobar el estado real de las dependencias']='check the actual dependency state'
    ['Se han detectado dependencias rotas:']='Broken dependencies were detected:'
    ['¿Intentar reparar dependencias con '"'"'apt --fix-broken install'"'"'?']='Try to repair dependencies with '"'"'apt --fix-broken install'"'"'?'
    ['reparar dependencias']='repair broken dependencies'
    ['No hay dependencias rotas.']='No broken dependencies found.'
    ['No se ha podido comprobar si hay dependencias rotas (sin permisos de administrador).']='Could not check for broken dependencies (administrator privileges unavailable).'
    ['Comprobando paquetes retenidos (hold)...']='Checking held packages...'
    ['Los siguientes paquetes están retenidos y no se actualizarán:']='The following packages are held and will not be upgraded:'
    ['Si no lo hiciste tú a propósito, puedes liberarlos con: sudo apt-mark unhold <paquete>']='If you did not do this intentionally, you can release them with: sudo apt-mark unhold <package>'
    ['No hay paquetes retenidos.']='No held packages found.'
    ['Comprobando el bit setuid de pkexec...']='Checking the pkexec setuid bit...'
    ['pkexec conserva su bit setuid (propietario root).']='pkexec retains its setuid bit (owner root).'
    ['pkexec ($pkexec_path) ha perdido el bit setuid o su propietario no es root.']='pkexec ($pkexec_path) has lost its setuid bit or its owner is not root.'
    ['Suele pasar al restaurar una copia de seguridad sin permisos especiales, con un']='This usually happens after restoring a backup without special permissions, with'
    ['endurecimiento de seguridad mal aplicado, o con la partición montada \']='incorrectly applied security hardening, or with the partition mounted \'
    ['¿Restaurar los permisos correctos de pkexec (root:root, modo 4755)?']='Restore the correct pkexec permissions (root:root, mode 4755)?'
    ['restaurar los permisos de pkexec']='restore pkexec permissions'
    ['restaurar propietario de pkexec']='restore pkexec owner'
    ['restaurar bit setuid de pkexec']='restore pkexec setuid bit'
    ['No se han podido restaurar los permisos de pkexec (sin permisos de administrador).']='Could not restore pkexec permissions (administrator privileges unavailable).'
    ['pkexec no está instalado: las herramientas gráficas con privilegios (Gestor de']='pkexec is not installed: graphical privilege tools (Update Manager,'
    ['actualizaciones, Timeshift, Synaptic...) no podrán pedir la contraseña.']='Timeshift, Synaptic...) will not be able to ask for the password.'
    ['¿Instalar policykit-1 (proporciona pkexec) para restaurar la elevación de privilegios gráfica?']='Install policykit-1 (provides pkexec) to restore graphical privilege elevation?'
    ['instalar policykit-1']='install policykit-1'
    ['sudo conserva su bit setuid.']='sudo retains its setuid bit.'
    ['sudo ($sudo_path) ha perdido su bit setuid. Ni este script ni sudo pueden arreglarlo:']='sudo ($sudo_path) has lost its setuid bit. Neither this script nor sudo can fix it:'
    ['la propia reparación necesitaría sudo, así que sería circular.']='the repair itself would require sudo, so it would be circular.'
    ['Arréglalo como root, desde el modo de recuperación o un USB en vivo, con:']='Fix it as root, from recovery mode or a live USB, with:'
    ['  chown root:root $sudo_path && chmod 4755 $sudo_path']='  chown root:root $sudo_path && chmod 4755 $sudo_path'
    ['El subsistema de paquetes está sano.']='The package subsystem is healthy.'
    ['Repositorios de software (orígenes y claves GPG)']='Software repositories (sources and GPG keys)'
    ['Hay repositorios de terceros que aún apuntan al nombre en clave de una versión']='There are third-party repositories that still point to the codename of an earlier'
    ['anterior de Mint/Ubuntu (esta es Mint 22.3 \']='Mint/Ubuntu release (this is Mint 22.3 \'
    ['Suele pasar con una PPA o repositorio de terceros añadido a mano en una versión de Mint']='This often happens with a PPA or third-party repository added manually on an earlier Mint release'
    ['anterior que nunca se actualizó. A veces '"'"'apt-get update'"'"' avisa con un error claro; otras']='that was never updated. Sometimes '"'"'apt-get update'"'"' reports a clear error; other times'
    ['veces el paquete simplemente deja de recibir actualizaciones sin ningún aviso visible.']='the package simply stops receiving updates without an obvious warning.'
    ['¿Comentar (con copia de seguridad) esas líneas para dejar de usarlas?']='Comment those lines (with a backup) so they are no longer used?'
    ['modificar archivos de orígenes de software de terceros']='modify third-party software source files'
    ['copia de seguridad de /etc/apt/sources.list.d']='backup of /etc/apt/sources.list.d'
    ['Hecho: comentar referencia a $cn en $file_cn']='Done: comment reference to $cn in $file_cn'
    ['Falló: comentar referencia a $cn en $file_cn (revisa el log para más detalle)']='Failed: comment reference to $cn in $file_cn (check the log for more detail)'
    ['Copia de seguridad guardada en: $backup_cn']='Backup saved to: $backup_cn'
    ['Si alguna de esas líneas sí publica paquetes para \']='If any of those lines actually publish packages for \'
    ['mano desde '"'"'Orígenes del software'"'"' en vez de restaurar el comentario.']='edit them manually from '"'"'Software Sources'"'"' instead of restoring the comment.'
    ['No se ha podido crear la copia de seguridad; no se modificará ningún archivo.']='No backup could be created; no file will be modified.'
    ['No se han podido modificar los archivos (sin permisos de administrador).']='Could not modify the files (administrator privileges unavailable).'
    ['Los repositorios de terceros usan el nombre en clave correcto (o no hay ninguno configurado).']='Third-party repositories use the correct codename (or none are configured).'
    ['El repositorio OFICIAL de Mint en $official_file usa el nombre en clave \']='The OFFICIAL Mint repository in $official_file uses the codename \'
    ['pero /etc/os-release identifica este sistema como \']='but /etc/os-release identifies this system as \'
    ['actualización de versión mayor se quedó a medias. Mint-Doctor no modifica este archivo']='the major-version upgrade may have stopped halfway. Mint-Doctor does not modify this file'
    ['automáticamente: revísalo a mano (o compáralo con '"'"'cat /etc/linuxmint/info'"'"', que no se ve']='automatically: review it manually (or compare it with '"'"'cat /etc/linuxmint/info'"'"', which does not appear'
    ['afectado por este problema) antes de instalar o actualizar más paquetes.']='affected by this problem) before installing or upgrading more packages.'
    ['En modo simulación se omite el resto de este módulo: '"'"'apt-get update'"'"' escribe la caché de']='In simulation mode the rest of this module is skipped: '"'"'apt-get update'"'"' writes the package-list'
    ['listas de paquetes en disco, no es una operación de solo lectura.']='cache to disk; it is not a read-only operation.'
    ['Ejecuta el script sin --dry-run para comprobar claves GPG y orígenes inaccesibles.']='Run the script without --dry-run to check GPG keys and unreachable sources.'
    ['Ejecutando '"'"'apt-get update'"'"' para detectar repositorios con problemas (puede tardar)...']='Running '"'"'apt-get update'"'"' to detect repository problems (this may take a while)...'
    ['actualizar la lista de repositorios']='update the repository list'
    ['No se ha podido comprobar el estado de los repositorios (sin permisos de administrador).']='Could not check repository status (administrator privileges unavailable).'
    [''"'"'apt-get update'"'"' ha fallado y no se ha podido determinar por qué; revisa el log.']=''"'"'apt-get update'"'"' failed and the reason could not be determined; check the log.'
    ['Todos los repositorios responden correctamente.']='All repositories are responding correctly.'
    ['Se han encontrado problemas al consultar los repositorios:']='Problems were found while querying repositories:'
    ['Faltan claves GPG para verificar algunos repositorios:']='GPG keys are missing to verify some repositories:'
    ['Importar una clave equivale a confiar en los paquetes que firme ese']='Importing a key means trusting packages signed by that'
    ['repositorio. Revisa cada uno y solo acepta los que reconozcas.']='repository. Review each one and only accept repositories you recognize.'
    ['  ¿Reconoces este repositorio e importas su clave?']='  Do you recognize this repository and want to import its key?'
    ['importar clave GPG $key']='import GPG key $key'
    ['No se ha podido importar la clave $key (sin permisos de administrador).']='Could not import GPG key $key (administrator privileges unavailable).'
    ['Hay firmas GPG que no coinciden (BADSIG), no claves ausentes, para:']='There are GPG signatures that do not match (BADSIG), not missing keys, for:'
    ['No se soluciona importando ninguna clave: suele deberse a una caché de listas de']='Importing a key does not fix this: it is usually caused by a corrupted package-list cache'
    ['paquetes corrupta o a un espejo con problemas.']='or a problematic mirror.'
    ['¿Limpiar la caché de listas de APT y reintentar '"'"'apt-get update'"'"' ?']='Clear the APT package-list cache and retry '"'"'apt-get update'"'"'?'
    ['¿Limpiar la caché de listas de APT y reintentar '"'"'apt-get update'"'"'?']='Clear the APT package-list cache and retry '"'"'apt-get update'"'"'?'
    ['limpiar la caché de listas de APT']='clear the APT package-list cache'
    ['limpiar caché de listas de APT']='clear APT package-list cache'
    ['volver a consultar repositorios (apt-get update)']='query repositories again (apt-get update)'
    ['No se ha podido limpiar la caché de listas de APT (sin permisos de administrador).']='Could not clear the APT package-list cache (administrator privileges unavailable).'
    ['Estos orígenes no responden (pueden estar caídos, mal escritos o ya no existir):']='These sources are not responding (they may be down, malformed, or no longer exist):'
    ['Recomendación: abre '"'"'Orígenes del software'"'"' (menú > Administración) y desmarca o elimina esas líneas,']='Recommendation: open '"'"'Software Sources'"'"' (menu > Administration) and disable or remove those lines,'
    ['o cambia el servidor de descarga por uno más cercano/estable.']='or change the download server to one that is closer/more stable.'
    ['¿Quieres que comente automáticamente (con copia de seguridad) las líneas de sources.list que apuntan a esos orígenes caídos?']='Do you want to comment automatically (with a backup) the sources.list lines pointing to these failed sources?'
    ['modificar archivos de orígenes de software']='modify software source files'
    ['copia de seguridad de /etc/apt/sources.list*']='backup of /etc/apt/sources.list*'
    ['Hecho: comentar referencia a $host en $list_file']='Done: comment reference to $host in $list_file'
    ['Falló: comentar referencia a $host en $list_file (revisa el log para más detalle)']='Failed: comment reference to $host in $list_file (check the log for more detail)'
    ['Copia de seguridad guardada en: $backup']='Backup saved to: $backup'
    ['No se han podido modificar los archivos de orígenes (sin permisos de administrador).']='Could not modify source files (administrator privileges unavailable).'
)

declare -Ag MINT_DOCTOR_EN_EXTRA=(
    ['Caché de paquetes descargados (APT): ${apt_cache_size:-0} (${apt_deb_count} paquetes .deb)']='Downloaded package cache (APT): ${apt_cache_size:-0} (${apt_deb_count} .deb packages)'
    ['¿Vaciar la caché de paquetes .deb ya instalados (apt clean)?']='Empty the downloaded .deb package cache (apt clean)?'
    ['limpiar caché de apt']='clean APT cache'
    ['No hay paquetes .deb acumulados en la caché de APT.']='No accumulated .deb packages in the APT cache.'
    ['Comprobando kernels antiguos instalados...']='Checking installed old kernels...'
    ['Hay $old_kernels_count kernels antiguos ocupando espacio (se conserva el actual: $current_kernel).']='There are $old_kernels_count old kernels using disk space (the current kernel is kept: $current_kernel).'
    ['¿Eliminar kernels y paquetes que ya no se usan (apt autoremove)?']='Remove unused kernels and packages (apt autoremove)?'
    ['eliminar paquetes obsoletos']='remove obsolete packages'
    ['No hay kernels antiguos acumulados.']='No old kernels accumulated.'
    ['Caché de miniaturas: ${thumb_size:-0}']='Thumbnail cache: ${thumb_size:-0}'
    ['¿Vaciar la caché de miniaturas de imágenes/vídeos?']='Empty the image/video thumbnail cache?'
    ['vaciar caché de miniaturas']='empty thumbnail cache'
    ['La caché de miniaturas no ocupa espacio significativo.']='The thumbnail cache is not using significant space.'
    ['La papelera contiene ${trash_size:-datos} sin vaciar.']='The trash contains ${trash_size:-data} waiting to be emptied.'
    ['¿Vaciar la papelera?']='Empty the trash?'
    ['vaciar papelera']='empty trash'
    ['leer el tamaño del journal de systemd']='read the systemd journal size'
    ['Tamaño del registro del sistema (journal): ${journal_raw:-desconocido}']='System journal size: ${journal_raw:-unknown}'
    ['No se ha podido determinar el tamaño del journal (sin permisos de administrador).']='Could not determine the journal size (administrator privileges unavailable).'
    ['¿Limitar el journal a 200 MB (se conservan los registros más recientes)?']='Limit the journal to 200 MB (keep the most recent entries)?'
    ['recortar el journal de systemd']='trim the systemd journal'
    ['El registro del sistema no ocupa un espacio excesivo.']='The system journal is not using excessive space.'
    ['Flatpak está instalado. Puede tener runtimes sin usar ocupando espacio.']='Flatpak is installed. It may have unused runtimes taking up space.'
    ['¿Buscar y eliminar runtimes/dependencias de Flatpak que ya no usa ninguna aplicación?']='Search for and remove Flatpak runtimes/dependencies that no application uses anymore?'
    ['No había runtimes de Flatpak sin usar que eliminar.']='There were no unused Flatpak runtimes to remove.'
    ['Hecho: eliminar dependencias Flatpak sin usar.']='Done: remove unused Flatpak dependencies.'
    ['Falló: eliminar dependencias Flatpak sin usar (revisa el log para más detalle).']='Failed: remove unused Flatpak dependencies (check the log for more detail).'
    ['Flatpak está instalado pero no tiene configurado el remoto \']='Flatpak is installed but the remote \'
    ['Aplicaciones no ofrecerá la opción Flatpak para ningún programa.']='Applications menu will not offer Flatpak for any program.'
    ['¿Añadir el remoto Flathub (https://flathub.org)?']='Add the Flathub remote (https://flathub.org)?'
    ['añadir el remoto Flathub de Flatpak']='add the Flatpak Flathub remote'
    ['El remoto Flathub está configurado en Flatpak.']='The Flathub remote is configured in Flatpak.'
    ['No se ha podido determinar el uso de la partición /boot.']='Could not determine /boot partition usage.'
    ['La partición /boot está al ${boot_pct}% de su capacidad.']='The /boot partition is at ${boot_pct}% of its capacity.'
    ['Si se llena del todo, la próxima actualización del kernel puede fallar a medias.']='If it fills completely, the next kernel update may fail halfway.'
    ['Revisa arriba los kernels antiguos: eliminarlos con autoremove libera espacio también en /boot.']='Check the old kernels above: removing them with autoremove also frees space in /boot.'
    ['La partición /boot tiene espacio suficiente (${boot_pct}% usado).']='The /boot partition has enough space (${boot_pct}% used).'
    ['El uso de disco está bajo control.']='Disk usage is under control.'
    ['Arranque, GRUB y reloj del sistema']='Boot, GRUB and system clock'
    ['El menú de arranque de GRUB no incluye el kernel actualmente en uso ($current_kernel).']='The GRUB boot menu does not include the kernel currently in use ($current_kernel).'
    ['¿Regenerar la configuración de arranque (update-grub)?']='Regenerate the boot configuration (update-grub)?'
    ['regenerar la configuración de arranque de GRUB']='regenerate the GRUB boot configuration'
    ['GRUB incluye una entrada para el kernel actual.']='GRUB includes an entry for the current kernel.'
    ['No se encontró /boot/grub/grub.cfg; se omite esta comprobación (¿gestor de arranque distinto?).']='/boot/grub/grub.cfg was not found; skipping this check (different bootloader?).'
    ['El sistema indica que hace falta reiniciar para aplicar cambios pendientes (p. ej. un kernel nuevo).']='The system says a reboot is required to apply pending changes (e.g. a new kernel).'
    ['Guarda tu trabajo y reinicia cuando puedas.']='Save your work and reboot when convenient.'
    ['No hay ningún reinicio pendiente marcado por el sistema.']='No reboot is currently marked as pending by the system.'
    ['Se ha detectado Windows en este equipo (arranque dual) y el reloj de hardware (RTC) está en UTC.']='Windows was detected on this machine (dual boot) and the hardware clock (RTC) is in UTC.'
    ['¿Configurar el RTC en hora local para que coincida con Windows?']='Set the RTC to local time to match Windows?'
    ['cambiar el modo del reloj de hardware (RTC)']='change the hardware clock (RTC) mode'
    ['El reloj de hardware (RTC) ya está en hora local, coherente con Windows.']='The hardware clock (RTC) is already in local time, consistent with Windows.'
    ['El kernel ha registrado avisos de un volumen NTFS marcado como \']='The kernel logged warnings about an NTFS volume marked as \'
    ['Solución: abre '"'"'Discos'"'"' desde el menú, selecciona ese volumen y usa ⚙ > '"'"'Reparar sistema de archivos'"'"'.']='Solution: open '"'"'Disks'"'"' from the menu, select that volume and use ⚙ > '"'"'Repair Filesystem'"'"'.'
    ['Mint-Doctor no toca particiones NTFS automáticamente para no arriesgar tus datos.']='Mint-Doctor does not modify NTFS partitions automatically to avoid risking your data.'
    ['No hay avisos recientes de volúmenes NTFS dañados.']='No recent warnings about damaged NTFS volumes.'
    ['La sincronización horaria automática (NTP) está desactivada.']='Automatic time synchronization (NTP) is disabled.'
    ['¿Activar la sincronización horaria automática?']='Enable automatic time synchronization?'
    ['activar la sincronización horaria (NTP)']='enable time synchronization (NTP)'
    ['NTP está activado pero el reloj todavía no se ha sincronizado.']='NTP is enabled but the clock has not synchronized yet.'
    ['Suele resolverse solo en cuanto haya conexión a Internet; si persiste, revisa el módulo de red.']='This usually resolves itself once there is an Internet connection; if it persists, check the network module.'
    ['El reloj del sistema está sincronizado por NTP.']='The system clock is synchronized by NTP.'
    ['Hay $failed_count servicio(s) systemd en estado \']='There are $failed_count systemd service(s) in state \'
    ['Para investigar uno en concreto: systemctl status <servicio> y journalctl -xeu <servicio>']='To investigate one in particular: systemctl status <service> and journalctl -xeu <service>'
    ['No hay servicios systemd en estado de fallo.']='No systemd services are in a failed state.'
    ['El apagado anterior tuvo que forzar el cierre de algún servicio por tardar demasiado:']='The previous shutdown had to force-stop a service because it took too long:'
    ['Mint reduce el tiempo de espera al apagar a solo 10s (frente a los 90s por defecto de']='Mint reduces the shutdown timeout to only 10s (instead of systemd'"'"'s default 90s).'
    ['systemd). Si esto te hace perder datos con frecuencia, puedes ampliarlo creando']='If this causes frequent data loss, you can increase it by creating'
    ['/etc/systemd/system.conf.d/60_custom.conf con un DefaultTimeoutStopSec mayor (revisa']='/etc/systemd/system.conf.d/60_custom.conf with a higher DefaultTimeoutStopSec (check'
    ['/etc/systemd/system.conf.d/50_linuxmint.conf para ver cómo está definido ahora).']='/etc/systemd/system.conf.d/50_linuxmint.conf to see how it is currently defined).'
    ['No hay avisos de apagados forzados por tiempo de espera en el arranque anterior.']='There were no forced-shutdown timeout warnings in the previous boot.'
    ['No hay registro de un arranque anterior (¿recién instalado?); se omite esta comprobación.']='There is no record of a previous boot (new installation?); skipping this check.'
    ['El arranque y el reloj del sistema están en orden.']='Boot and the system clock are in order.'
    ['Conectividad de red']='Network connectivity'
    ['Hay radios bloqueadas por software:']='Some radios are blocked by software:'
    ['¿Desbloquear todas las radios (WiFi/Bluetooth)?']='Unblock all radios (WiFi/Bluetooth)?'
    ['desbloquear radios con rfkill']='unblock radios with rfkill'
    ['No hay ninguna radio (WiFi/Bluetooth) bloqueada por software.']='No WiFi/Bluetooth radios are blocked by software.'
    ['Además, hay radios bloqueadas por hardware (interruptor físico o tecla Fn):']='Some radios are also blocked by hardware (physical switch or Fn key):'
    ['Eso no se puede desbloquear por software; revisa el interruptor o combinación Fn de tu equipo.']='This cannot be unblocked by software; check the switch or Fn key combination on your machine.'
    ['Hay conexión a Internet y la resolución de nombres (DNS) funciona.']='Internet connectivity is available and name resolution (DNS) works.'
    ['Hay conexión a Internet (la resolución DNS funciona), aunque no responde al ping.']='Internet connectivity is available (DNS resolution works), although ping does not respond.'
    ['Puede que ICMP esté bloqueado en tu red; no indica ningún problema por sí solo.']='ICMP may be blocked on your network; this is not a problem by itself.'
    ['Hay conexión a Internet, pero la resolución de nombres (DNS) está fallando.']='Internet connectivity is available, but name resolution (DNS) is failing.'
    ['Puede deberse a un servidor DNS caído o mal configurado en tu red o router.']='This may be caused by a down or misconfigured DNS server on your network or router.'
    ['¿Reiniciar NetworkManager (a veces resuelve bloqueos temporales de DNS)?']='Restart NetworkManager (sometimes fixes temporary DNS stalls)?'
    ['reiniciar el servicio de red']='restart the network service'
    ['No se ha detectado conexión a Internet en este momento.']='No Internet connection is detected at the moment.'
    ['Comprueba el cable/WiFi, o si el icono de red del panel muestra algún error.']='Check the cable/WiFi, or whether the network icon on the panel shows an error.'
    ['La conectividad de red no muestra problemas.']='Network connectivity shows no problems.'
)

declare -Ag MINT_DOCTOR_EN_EXTRA2=(
    ['Salud del hardware (disco, batería y controladores DKMS)']='Hardware health (disk, battery and DKMS drivers)'
    ['consultar el estado S.M.A.R.T. de los discos']='check disk S.M.A.R.T. status'
    ['/dev/$disk: S.M.A.R.T. correcto.']='/dev/$disk: S.M.A.R.T. OK.'
    ['/dev/$disk: S.M.A.R.T. informa un problema → ${health##*: }']='/dev/$disk: S.M.A.R.T. reports a problem → ${health##*: }'
    ['/dev/$disk: no se ha podido determinar el estado S.M.A.R.T. (habitual en máquinas virtuales o algunos discos USB/NVMe).']='/dev/$disk: could not determine S.M.A.R.T. status (common in virtual machines or some USB/NVMe disks).'
    ['No se ha podido comprobar el estado S.M.A.R.T. de los discos (sin permisos de administrador).']='Could not check disk S.M.A.R.T. status (administrator privileges unavailable).'
    ['Al menos un disco reporta un estado S.M.A.R.T. anómalo; hay riesgo de pérdida de datos.']='At least one disk reports an abnormal S.M.A.R.T. state; data loss is possible.'
    ['Haz una copia de seguridad cuanto antes y considera sustituir el disco.']='Back up your data as soon as possible and consider replacing the disk.'
    ['smartmontools no está instalado; no se puede comprobar la salud S.M.A.R.T. de los discos.']='smartmontools is not installed; disk S.M.A.R.T. health cannot be checked.'
    ['¿Instalar smartmontools para poder revisar la salud de los discos?']='Install smartmontools to check disk health?'
    ['instalar smartmontools']='install smartmontools'
    ['Salud de la batería ($bat): ${cap}% de su capacidad de fábrica.']='Battery health ($bat): ${cap}% of its factory capacity.'
    ['La batería ha perdido buena parte de su capacidad original; puede que dure poco o convenga sustituirla.']='The battery has lost much of its original capacity; it may have poor runtime or need replacement.'
    ['Este equipo parece un portátil (tiene batería) pero no tiene TLP instalado, que ayuda a alargar la autonomía.']='This system appears to be a laptop (it has a battery) but TLP is not installed; TLP can improve battery life.'
    ['¿Instalar y activar TLP para mejorar la gestión de energía?']='Install and enable TLP to improve power management?'
    ['instalar y activar TLP']='install and enable TLP'
    ['instalar TLP']='install TLP'
    ['activar el servicio TLP']='enable the TLP service'
    ['No se ha podido instalar TLP (sin permisos de administrador).']='Could not install TLP (administrator privileges unavailable).'
    ['TLP ya está instalado para gestionar el consumo de energía.']='TLP is already installed for power management.'
    ['Estos módulos DKMS no están instalados para el kernel en uso ($current_kernel):']='These DKMS modules are not installed for the current kernel ($current_kernel):'
    ['Suele arreglarse instalando las cabeceras del kernel actual y reconstruyendo los módulos.']='This is usually fixed by installing the current kernel headers and rebuilding the modules.'
    ['Nota: las notas de versión de Mint 22.3 avisan de problemas conocidos entre']='Note: the Mint 22.3 release notes warn about known problems between'
    ['VirtualBox y el kernel HWE 6.14. Si tras reconstruir los módulos sigue sin']='VirtualBox and the HWE 6.14 kernel. If the modules still do not work after rebuilding,'
    ['funcionar, prueba arrancando un kernel anterior desde \']='try booting an earlier kernel from \'
    ['en el menú de arranque, o instala linux-headers de un kernel LTS más antiguo.']='from the boot menu, or install linux-headers for an older LTS kernel.'
    ['¿Instalar linux-headers-${current_kernel} y reconstruir los módulos DKMS ahora?']='Install linux-headers-${current_kernel} and rebuild the DKMS modules now?'
    ['instalar cabeceras del kernel y reconstruir módulos DKMS']='install kernel headers and rebuild DKMS modules'
    ['instalar linux-headers-${current_kernel}']='install linux-headers-${current_kernel}'
    ['reconstruir módulos DKMS (dkms autoinstall)']='rebuild DKMS modules (dkms autoinstall)'
    ['No se han podido instalar las cabeceras ni reconstruir los módulos DKMS (sin permisos de administrador).']='Could not install the headers or rebuild DKMS modules (administrator privileges unavailable).'
    ['Todos los módulos DKMS están instalados para el kernel en uso.']='All DKMS modules are installed for the current kernel.'
    ['DKMS no está instalado (normal si no usas drivers propietarios como NVIDIA).']='DKMS is not installed (normal if you do not use proprietary drivers such as NVIDIA).'
    ['Tienes instalado el driver nvidia-driver-470 (para tarjetas NVIDIA antiguas) junto al kernel']='You have nvidia-driver-470 installed (for older NVIDIA cards) together with kernel'
    ['$nv_kernel, de la serie 6.14 o superior, que ya no admite ese driver.']='$nv_kernel, from the 6.14 series or newer, which no longer supports that driver.'
    ['Es un problema conocido de Mint 22.3: NVIDIA dejó de mantener el driver 470 para kernels']='This is a known Mint 22.3 issue: NVIDIA stopped maintaining driver 470 for newer kernels'
    ['nuevos. Si la pantalla se ve sin aceleración 3D o en baja resolución, arranca un kernel']='If the display has no 3D acceleration or is low-resolution, boot an earlier kernel'
    ['anterior desde \']='from \'
    ['Mint 22.1, que usa el kernel LTS 6.8 (compatible con el driver 470).']='Mint 22.1, which uses the LTS 6.8 kernel (compatible with driver 470).'
    ['El driver nvidia-driver-470 es compatible con el kernel en uso ($nv_kernel).']='The nvidia-driver-470 driver is compatible with the current kernel ($nv_kernel).'
    ['El servidor de sonido (PipeWire/PulseAudio) responde correctamente.']='The sound server (PipeWire/PulseAudio) is responding correctly.'
    ['Usas PipeWire con salida por HDMI. Mint 22.x documenta cortes de audio conocidos en']='You use PipeWire with HDMI output. Mint 22.x documents known audio dropouts in'
    ['esta combinación. Si notas cortes, puedes volver a PulseAudio con:']='this combination. If you notice dropouts, you can switch back to PulseAudio with:'
    ['  sudo apt purge pipewire pipewire-bin && systemctl enable --user pulseaudio && reinicia']='  sudo apt purge pipewire pipewire-bin && systemctl enable --user pulseaudio && reboot'
    ['No se ha podido contactar con ningún servidor de sonido (PipeWire/PulseAudio).']='Could not contact any sound server (PipeWire/PulseAudio).'
    ['Si no tienes audio en ningún dispositivo, cierra sesión y vuelve a entrar; si persiste,']='If you have no audio on any device, log out and back in; if it persists,'
    ['prueba: systemctl --user restart pipewire pipewire-pulse wireplumber']='try: systemctl --user restart pipewire pipewire-pulse wireplumber'
    ['Secure Boot está activado y el kernel ha rechazado cargar algún módulo por falta de firma:']='Secure Boot is enabled and the kernel rejected a module because it is unsigned:'
    ['Suele pasar con módulos DKMS (NVIDIA propietario, VirtualBox, Broadcom Wi-Fi...) recién']='This often happens with newly built DKMS modules (proprietary NVIDIA, VirtualBox, Broadcom Wi-Fi...)'
    ['compilados: el Gestor de controladores puede decir \']='built: Driver Manager may say \'
    ['Arreglo (exige elegir una contraseña y confirmarla tras reiniciar, no se puede automatizar):']='Fix (requires choosing a password and confirming it after reboot; it cannot be automated):'
    ['  sudo dpkg-reconfigure <paquete-dkms-afectado>   (p. ej. nvidia-dkms-XXX o virtualbox-dkms)']='  sudo dpkg-reconfigure <affected-dkms-package>   (e.g. nvidia-dkms-XXX or virtualbox-dkms)'
    ['Eso vuelve a lanzar el asistente que genera e inscribe la clave MOK (\']='This launches the wizard again to generate and enroll the MOK key (\'
    ['próximo arranque. Alternativa: desactivar Secure Boot en la BIOS/UEFI si no lo necesitas.']='next boot. Alternative: disable Secure Boot in BIOS/UEFI if you do not need it.'
    ['Secure Boot está activado, pero no hay evidencia de módulos rechazados por firma en este arranque.']='Secure Boot is enabled, but there is no evidence of signature-rejected modules during this boot.'
    ['Estás en una VM de VirtualBox y las Guest Additions (vboxguest) están cargadas.']='You are in a VirtualBox VM and the Guest Additions (vboxguest) module is loaded.'
    ['Estás en una máquina virtual de VirtualBox, pero el módulo \']='You are in a VirtualBox virtual machine, but the \'
    ['Additions no está cargado: el redimensionado automático de pantalla, el portapapeles']='Additions module is not loaded: automatic screen resizing, clipboard'
    ['compartido con el equipo anfitrión y la aceleración gráfica no funcionarán bien sin él.']='sharing with the host and graphics acceleration will not work properly without it.'
    ['¿Instalar las Guest Additions de VirtualBox desde los repositorios de Mint?']='Install the VirtualBox Guest Additions from the Mint repositories?'
    ['instalar las Guest Additions de VirtualBox']='install the VirtualBox Guest Additions'
    ['instalar Guest Additions de VirtualBox']='install VirtualBox Guest Additions'
    ['Si el módulo sigue sin cargar tras instalar, reinicia la máquina virtual.']='If the module still does not load after installation, reboot the virtual machine.'
    ['No se han podido instalar las Guest Additions (sin permisos de administrador).']='Could not install the Guest Additions (administrator privileges unavailable).'
    ['Disco, batería y controladores DKMS están en buen estado.']='Disk, battery and DKMS drivers are in good condition.'
    ['Escritorio Cinnamon']='Cinnamon desktop'
    ['Se han encontrado bloqueos de Cinnamon durante esta sesión:']='Cinnamon freezes were detected during this session:'
    ['Si ves paneles o applets desaparecidos, prueba a cerrar sesión y volver a entrar,']='If panels or applets disappear, try logging out and back in,'
    ['o pulsa Alt+F2 y escribe '"'"'r'"'"' para reiniciar Cinnamon sin cerrar tus programas.']='or press Alt+F2 and type '"'"'r'"'"' to restart Cinnamon without closing your programs.'
    ['No se han detectado bloqueos de Cinnamon en esta sesión.']='No Cinnamon freezes were detected during this session.'
    ['Hay ${#untrusted[@]} acceso(s) directo(s) en el escritorio sin marcar como confiables:']='There are ${#untrusted[@]} desktop shortcut(s) not marked as trusted:'
    ['¿Marcarlos como confiables para que funcionen con un doble clic?']='Mark them as trusted so they work with a double click?'
    ['Marcados como confiables: $ok_count acceso(s) directo(s).']='Marked as trusted: $ok_count desktop shortcut(s).'
    ['No se pudo marcar ningún acceso directo (revisa permisos).']='No shortcut could be marked (check permissions).'
    ['Los accesos directos del escritorio están marcados como confiables.']='Desktop shortcuts are marked as trusted.'
    ['Tienes instalado gstreamer1.0-vaapi (aceleración 3D por hardware para vídeo) dentro de']='gstreamer1.0-vaapi is installed (hardware 3D video acceleration) inside'
    ['una VM de VirtualBox. Las notas de Mint documentan justo este caso: la aceleración 3D']='a VirtualBox VM. Mint'"'"'s notes document this exact case: 3D acceleration'
    ['puede dar problemas de renderizado en apps WebKit/GTK4; quitar este paquete es su salida']='can cause rendering problems in WebKit/GTK4 apps; removing this package is the'
    ['más simple.']='simplest workaround.'
    ['¿Solo si notas ese problema de renderizado, quitar gstreamer1.0-vaapi ahora?']='Only if you notice that rendering problem, remove gstreamer1.0-vaapi now?'
    ['quitar gstreamer1.0-vaapi']='remove gstreamer1.0-vaapi'
    ['Tienes instalado gstreamer1.0-vaapi (aceleración 3D por hardware para vídeo). El aviso de']='gstreamer1.0-vaapi is installed (hardware 3D video acceleration). Mint'"'"'s warning about'
    ['Mint sobre renderizado WebKit/GTK4 con este paquete está documentado para cuando se']='WebKit/GTK4 rendering with this package is documented for Mint when it is'
    ['prueba Mint como invitado en VirtualBox, no para hardware real.']='tested as a VirtualBox guest, not on real hardware.'
    ['No se han instalado los códecs multimedia de Mint (paquete mint-meta-codecs).']='Mint multimedia codecs are not installed (mint-meta-codecs package).'
    ['Sin ellos, es habitual que fallen la reproducción de MP3/AAC, vídeos H.264/H.265 o DVDs.']='Without them, MP3/AAC playback, H.264/H.265 video or DVDs commonly fail.'
    ['¿Instalar el paquete de códecs multimedia (mint-meta-codecs)?']='Install the multimedia codecs package (mint-meta-codecs)?'
    ['instalar los códecs multimedia']='install the multimedia codecs'
    ['Los códecs multimedia de Mint ya están instalados.']='Mint multimedia codecs are already installed.'
    ['Esta sesión se ha iniciado en modo \']='This session started in \'
    ['Suele activarse tras varios bloqueos seguidos del Cinnamon normal y señala un problema con']='This is usually enabled after repeated Cinnamon freezes and indicates a problem with'
    ['el driver gráfico. Revisa el Gestor de controladores y la opción 7 de este script (DKMS).']='the graphics driver. Check Driver Manager and option 7 of this script (DKMS).'
    ['Estas '"'"'spices'"'"' de terceros no declaran soporte para Cinnamon ${cin_ver_mm} (metadata.json):']='These third-party '"'"'spices'"'"' do not declare support for Cinnamon ${cin_ver_mm} (metadata.json):'
    ['Es habitual justo después de actualizar a Cinnamon 6.6 (Mint 22.3). Busca una versión más']='This is common immediately after upgrading to Cinnamon 6.6 (Mint 22.3). Look for a newer version'
    ['reciente en Menú > Applets/Desklets/Extensiones > pestaña Descargar, o en']='under Menu > Applets/Desklets/Extensions > Download tab, or at'
    ['cinnamon-spices.linuxmint.com; si no la hay, el autor aún no la ha actualizado.']='cinnamon-spices.linuxmint.com; if there is none, the author has not updated it yet.'
    ['El escritorio Cinnamon no muestra problemas evidentes.']='The Cinnamon desktop shows no obvious problems.'
    ['Copias de seguridad del sistema (Timeshift)']='System backups (Timeshift)'
    ['Timeshift no está instalado. Sin él, no hay forma de deshacer una actualización']='Timeshift is not installed. Without it, there is no way to undo a problematic update'
    ['problemática volviendo a un estado anterior del sistema.']='by returning to an earlier state of the system.'
    ['¿Instalar Timeshift?']='Install Timeshift?'
    ['instalar Timeshift']='install Timeshift'
    ['Ábrelo desde el menú (Administración > Timeshift) para elegir dónde guardar las instantáneas.']='Open it from the menu (Administration > Timeshift) to choose where to store snapshots.'
    ['No se ha podido instalar Timeshift (sin permisos de administrador).']='Could not install Timeshift (administrator privileges unavailable).'
    ['Timeshift está instalado pero todavía no se ha configurado ningún destino de copia.']='Timeshift is installed but no backup destination is configured yet.'
    ['Ábrelo desde el menú (Administración > Timeshift) y sigue el asistente para elegir dónde']='Open it from the menu (Administration > Timeshift) and follow the wizard to choose where'
    ['guardar las instantáneas; tarda un par de minutos y puede salvarte de un desastre.']='to store snapshots; it takes a couple of minutes and can save you from disaster.'
    ['comprobar las instantáneas reales de Timeshift']='check real Timeshift snapshots'
    ['No se ha podido comprobar si existen instantáneas reales (sin permisos de administrador).']='Could not check whether real snapshots exist (administrator privileges unavailable).'
    ['Tener un destino configurado no basta: confírmalo tú mismo con '"'"'sudo timeshift --list'"'"'.']='Having a configured destination is not enough: confirm it yourself with '"'"'sudo timeshift --list'"'"'.'
    [''"'"'timeshift --list'"'"' no ha respondido en 20s; el dispositivo de destino podría no estar']=''"'"'timeshift --list'"'"' did not respond within 20s; the backup destination may not be'
    ['disponible o haberse desconectado a medias. Revisa que la unidad de copia siga conectada.']='available or may have been partially disconnected. Check that the backup drive is still connected.'
    ['El destino de copia configurado no está disponible ahora mismo (¿unidad externa desconectada']='The configured backup destination is not available right now (external drive disconnected'
    ['o ha cambiado el UUID de la partición?). Mientras tanto NO se están creando instantáneas nuevas,']='or the partition UUID changed?). NO new snapshots are being created meanwhile,'
    ['aunque el asistente se completara en su día.']='even if the setup wizard was completed previously.'
    ['Abre Timeshift y, en Configuración > Ubicación, reconecta o vuelve a seleccionar el destino.']='Open Timeshift and, under Settings > Location, reconnect or select the destination again.'
    ['Timeshift tiene un destino de copia configurado, pero todavía no existe ninguna instantánea real.']='Timeshift has a configured backup destination, but there is still no real snapshot.'
    ['Un destino configurado no equivale a tener copias de seguridad: sin al menos una instantánea,']='A configured destination is not the same as having backups: without at least one snapshot,'
    ['Timeshift no podría devolverte el sistema a ningún estado anterior si algo sale mal.']='Timeshift could not restore the system to any previous state if something goes wrong.'
    ['¿Crear ahora la primera instantánea? (puede tardar varios minutos)']='Create the first snapshot now? (may take several minutes)'
    ['crear la primera instantánea con Timeshift']='create the first Timeshift snapshot'
    ['Hay ${snapshot_count} instantánea(s) real(es) guardada(s).']='There are ${snapshot_count} real snapshot(s) saved.'
    ['La instantánea más reciente tiene fecha futura según el reloj del sistema.']='The most recent snapshot is dated in the future according to the system clock.'
    ['Revisa el reloj/NTP en la opción 5 de este script; con la hora mal ajustada esta']='Check the clock/NTP in option 5 of this script; with the clock wrong this'
    ['comprobación de antigüedad no es fiable.']='age check is not reliable.'
    ['La instantánea más reciente tiene ${age_days} días. Si esperabas copias más frecuentes,']='The most recent snapshot is ${age_days} days old. If you expected more frequent backups,'
    ['puede que la programación automática se haya detenido sin que lo notaras.']='the automatic schedule may have stopped without you noticing.'
    ['La instantánea más reciente tiene ${age_days} día(s).']='The most recent snapshot is ${age_days} day(s) old.'
    ['Ninguna programación automática (por hora/diaria/semanal/mensual/al arrancar) está activada.']='No automatic schedule (hourly/daily/weekly/monthly/at boot) is enabled.'
    ['Ábrelo desde el menú (Administración > Timeshift) > pestaña '"'"'Programación'"'"' para que las']='Open it from the menu (Administration > Timeshift) > '"'"'Schedule'"'"' tab so that'
    ['instantáneas se creen solas y no dependan de acordarte de pulsar '"'"'Crear'"'"'.']='snapshots are created automatically and do not depend on remembering to press '"'"'Create'"'"'.'
    ['Mint-Doctor no sustituye a Timeshift: revisa de vez en cuando que sigan creándose instantáneas']='Mint-Doctor does not replace Timeshift: check from time to time that snapshots are still being created'
    ['nuevas, sobre todo antes de una actualización grande del sistema.']='especially before a major system update.'
    ['Las copias de seguridad del sistema están en orden.']='System backups are in order.'
    ['Registro completo guardado en: $LOG_FILE']='Full log saved to: $LOG_FILE'
    ['Opción no válida.']='Invalid option.'
)

declare -Ag MINT_DOCTOR_EN_EXTRA3=(
  ['Pulsa Enter para continuar...']='Press Enter to continue...'
  ['SIMULACIÓN']='SIMULATION'
  ['Se ejecutaría:']='Would run:'
  ['Aplicando:']='Applying:'
  ['Últimas líneas de la salida:']='Last output lines:'
  ['Registro completo:']='Full log:'
  ['paquetes a medio instalar']='partially installed packages'
  ['sin problemas evidentes']='no obvious problems'
  ['activa']='active'
  ['NetworkManager inactivo']='NetworkManager inactive'
  ['paquete(s) esperando actualizarse']='package(s) pending updates'
  ['el sistema está al día']='system is up to date'
  ['Estado rápido del sistema']='Quick system status'
  ['Disco (/):']='Disk (/):'
  ['Memoria RAM:']='RAM:'
  ['Paquetes / APT:']='Packages / APT:'
  ['Actualizaciones:']='Updates:'
  ['Red:']='Network:'
  ['desconocido']='unknown'
  ['El disco está casi lleno, revisa la opción 4 (limpieza de caché).']='The disk is almost full; check option 4 (cache cleanup).'
  ['Distribución:']='Distribution:'
  ['Encendido desde:']='Uptime:'
  ['Sesión gráfica:']='Graphical session:'
  ['Tamaño']='Size'
  ['Usado']='Used'
  ['Uso%']='Used%'
  ['Aviso: no se ha podido crear el registro; esta sesión continúa sin guardar registro.']='Warning: could not create the log; continuing without a log.'
  ['Libre']='Free'
  ['MODO SIMULACIÓN ACTIVADO — no se aplicará ningún cambio']='SIMULATION MODE ENABLED — no changes will be applied'
  ['Opción desconocida:']='Unknown option:'
  ['No ejecutes Mint-Doctor directamente como root ni con sudo.']='Do not run Mint-Doctor directly as root or with sudo.'
  ['El script pedirá la contraseña con sudo solo cuando una acción concreta la necesite.']='The script will ask for your sudo password only when a specific action requires it.'
  ['Resumen de la sesión']='Session summary'
  ['Problemas detectados:']='Problems detected:'
  ['Solucionados:']='Fixed:'
  ['Omitidos:']='Skipped:'
  ['¿Qué quieres revisar?']='What do you want to check?'
  ['Elige una opción']='Choose an option'
  ['Hasta la próxima. ¡Que tu Mint funcione de maravilla!']='Goodbye. May your Mint keep working perfectly!'
  ['Interrumpido por el usuario.']='Interrupted by user.'
  ['Uso']='Usage'
  ['Autoreparador para']='Autorepair tool for'
  ['Modo interactivo (menú)']='Interactive mode (menu)'
  ['Simula las acciones, no aplica ningún cambio']='Simulates actions; no changes are applied'
  ['Analiza y repara todo automáticamente']='Checks and repairs everything automatically'
  ['Escaneo completo simulado, sin menú']='Full simulated scan, without a menu'
  ['Fuerza el idioma de la interfaz']='Forces the interface language'
  ['Muestra esta ayuda']='Show this help'
  ['Muestra la versión y sale']='Show version and exit'
  ['No lo ejecutes con sudo ni como root: el propio script pedirá la contraseña']='Do not run it with sudo or as root: the script will ask for the password itself'
  ['únicamente cuando una acción concreta la necesite.']='only when a specific action requires it.'
  ['Falta el idioma tras --lang (usa es o en).']='Missing language after --lang (use es or en).'
  ['Paquetes y APT/dpkg']='Packages and APT/dpkg'
  ['Espacio en disco y limpieza de caché']='Disk space and cache cleanup'
  ['Salud del hardware (disco, batería y controladores)']='Hardware health (disk, battery and drivers)'
  ['Copias de seguridad (Timeshift)']='System backups (Timeshift)'
  ['Ejecutar todos los módulos']='Run all modules'
  ['Idioma: Español (cambiar a English)']='Language: English (switch to Español)'
  ['Salir']='Exit'
)
MINT_DOCTOR_EN_EXTRA3['desconocida']='unknown'
MINT_DOCTOR_EN_EXTRA3['no detectado']='not detected'
MINT_DOCTOR_EN_EXTRA3['El subsistema de paquetes está sano.']='The package subsystem is healthy.'
MINT_DOCTOR_EN_EXTRA3['Se comentarían las líneas/bloques de:']='The following lines/blocks would be commented:'
MINT_DOCTOR_EN_EXTRA3['Aplicando: comentar referencia a ']='Applying: comment reference to '
MINT_DOCTOR_EN_EXTRA3['Suele pasar tras instalar un kernel nuevo sin regenerar GRUB después.']='This often happens after installing a new kernel without regenerating GRUB afterwards.'
MINT_DOCTOR_EN_EXTRA3['Paquetes implicados:']='Affected packages:'
MINT_DOCTOR_EN_EXTRA3['Windows espera que el RTC esté en hora local, así que Linux o Windows mostrarán']='Windows expects the RTC to be in local time, so Linux or Windows will show'
MINT_DOCTOR_EN_EXTRA3['la hora equivocada justo después de arrancar el otro sistema.']='the wrong time immediately after booting the other system.'
MINT_DOCTOR_EN_EXTRA3['Se marcarían como confiables:']='Would be marked as trusted:'
MINT_DOCTOR_EN_EXTRA3['eliminar bloqueos obsoletos']='remove stale locks'
MINT_DOCTOR_EN_EXTRA3['reconfigurar paquetes pendientes']='reconfigure pending packages'
MINT_DOCTOR_EN_EXTRA3['reparar dependencias rotas']='repair broken dependencies'
MINT_DOCTOR_EN_EXTRA3['migrar claves heredadas a trusted.gpg.d']='migrate legacy keys to trusted.gpg.d'
MINT_DOCTOR_EN_EXTRA3['eliminar kernels y paquetes obsoletos']='remove old kernels and obsolete packages'
MINT_DOCTOR_EN_EXTRA3['recortar journal a 200M']='trim journal to 200M'
MINT_DOCTOR_EN_EXTRA3['añadir remoto Flathub']='add Flathub remote'
MINT_DOCTOR_EN_EXTRA3['regenerar GRUB']='regenerate GRUB configuration'
MINT_DOCTOR_EN_EXTRA3['activar NTP']='enable NTP'
MINT_DOCTOR_EN_EXTRA3['reiniciar NetworkManager']='restart NetworkManager'
MINT_DOCTOR_EN_EXTRA3['instalar mint-meta-codecs']='install mint-meta-codecs'
MINT_DOCTOR_EN_EXTRA3['cuelgues o parpadeos, prueba "Cinnamon (en X11)" en el icono de la pantalla de inicio de sesión.']='freezes or flickering, try "Cinnamon (X11)" from the session selector on the login screen.'
MINT_DOCTOR_EN_EXTRA3['/etc/apt/preferences.d/nosnap.pref). "apt install snapd" no instalará nada mientras']='(/etc/apt/preferences.d/nosnap.pref). "apt install snapd" will not install anything while'
MINT_DOCTOR_EN_EXTRA3['endurecimiento de seguridad mal aplicado, o con la partición montada "nosuid".']='incorrectly applied security hardening, or with the partition mounted "nosuid".'
MINT_DOCTOR_EN_EXTRA3['  chown root:root $sudo_path && chmod 4755 $sudo_path']='  chown root:root $sudo_path && chmod 4755 $sudo_path'
MINT_DOCTOR_EN_EXTRA3['El repositorio OFICIAL de Mint en $official_file usa el nombre en clave "$official_codename",']='The OFFICIAL Mint repository in $official_file uses the codename "$official_codename",'
MINT_DOCTOR_EN_EXTRA3['pero /etc/os-release identifica este sistema como "$mint_codename". Suele significar que una']='but /etc/os-release identifies this system as "$mint_codename". This usually means a'
MINT_DOCTOR_EN_EXTRA3['Algunos repositorios firman con claves guardadas en el keyring heredado']='Some repositories use keys stored in the legacy keyring'
MINT_DOCTOR_EN_EXTRA3['(/etc/apt/trusted.gpg), un mecanismo obsoleto desde Ubuntu 22.04. No es grave y las']='(/etc/apt/trusted.gpg), an obsolete mechanism since Ubuntu 22.04. It is not serious and'
MINT_DOCTOR_EN_EXTRA3["actualizaciones funcionan igual, pero apt avisa de ello en cada 'apt-get update'."]="updates work normally, but apt warns about it on every 'apt-get update'."
MINT_DOCTOR_EN_EXTRA3['¿Migrar esas claves al directorio moderno (/etc/apt/trusted.gpg.d/) para que deje de avisar?']='Migrate those keys to the modern directory (/etc/apt/trusted.gpg.d/) to stop the warning?'
MINT_DOCTOR_EN_EXTRA3['migrar claves del keyring heredado a trusted.gpg.d']='migrate legacy keyring keys to trusted.gpg.d'
MINT_DOCTOR_EN_EXTRA3['El archivo original se conserva (sin usarse) en /etc/apt/trusted.gpg.bak-mint-doctor']='The original file is kept (unused) at /etc/apt/trusted.gpg.bak-mint-doctor'
MINT_DOCTOR_EN_EXTRA3['No se han podido migrar las claves heredadas (sin permisos de administrador).']='Could not migrate the legacy keys (administrator privileges unavailable).'
MINT_DOCTOR_EN_EXTRA3["No se pudo clasificar el error automáticamente. Revisa el detalle arriba o abre 'Orígenes del software'."]="The error could not be classified automatically. Review the details above or open 'Software Sources'."
MINT_DOCTOR_EN_EXTRA3['Los repositorios de software no muestran más problemas.']='The software repositories show no further problems.'
MINT_DOCTOR_EN_EXTRA3['Flatpak está instalado pero no tiene configurado el remoto "flathub": el Gestor de']='Flatpak is installed but the "flathub" remote is not configured: the Software Manager'
MINT_DOCTOR_EN_EXTRA3['El kernel ha registrado avisos de un volumen NTFS marcado como "dirty" (posiblemente tu partición de Windows).']='The kernel logged warnings about an NTFS volume marked as "dirty" (possibly your Windows partition).'
MINT_DOCTOR_EN_EXTRA3['Hay $failed_count servicio(s) systemd en estado "failed":']='There are $failed_count systemd service(s) in "failed" state:'
MINT_DOCTOR_EN_EXTRA3['funcionar, prueba arrancando un kernel anterior desde "Opciones avanzadas"']='work, try booting an earlier kernel from "Advanced options"'
MINT_DOCTOR_EN_EXTRA3['anterior desde "Opciones avanzadas" en el menú de arranque, o valora instalar Linux']='from "Advanced options" in the boot menu, or consider installing Linux'
MINT_DOCTOR_EN_EXTRA3['compilados: el Gestor de controladores puede decir "instalado" aunque el módulo nunca cargue.']='built: Driver Manager may say "installed" even though the module never loads.'
MINT_DOCTOR_EN_EXTRA3['Eso vuelve a lanzar el asistente que genera e inscribe la clave MOK ("Enroll MOK") en el']='This launches the wizard again to generate and enroll the MOK key ("Enroll MOK") in the'
MINT_DOCTOR_EN_EXTRA3['Estás en una máquina virtual de VirtualBox, pero el módulo "vboxguest" de las Guest']='You are in a VirtualBox virtual machine, but the "vboxguest" module from the Guest'
MINT_DOCTOR_EN_EXTRA3['Esta sesión se ha iniciado en modo "Cinnamon (Software Rendering)", sin aceleración 3D.']='This session started in "Cinnamon (Software Rendering)" mode, without 3D acceleration.'
MINT_DOCTOR_EN_EXTRA3['Autoreparador']='Autorepair tool'
MINT_DOCTOR_EN_EXTRA3['Tiempo encendido:']='Uptime:'
MINT_DOCTOR_EN_EXTRA3['comprobar si los archivos de bloqueo de apt/dpkg siguen en uso']='check whether apt/dpkg lock files are still in use'
MINT_DOCTOR_EN_EXTRA3['comprobar el estado real de las dependencias']='check the actual dependency state'
MINT_DOCTOR_EN_EXTRA3['restaurar los permisos de pkexec']='restore the pkexec permissions'
MINT_DOCTOR_EN_EXTRA3['modificar archivos de orígenes de software de terceros']='modify third-party software source files'
MINT_DOCTOR_EN_EXTRA3['actualizar la lista de repositorios']='update the repository list'
MINT_DOCTOR_EN_EXTRA3['limpiar la caché de listas de APT']='clear the APT package-list cache'
MINT_DOCTOR_EN_EXTRA3['modificar archivos de orígenes de software']='modify software source files'
MINT_DOCTOR_EN_EXTRA3['leer el tamaño del journal de systemd']='read the systemd journal size'
MINT_DOCTOR_EN_EXTRA3['consultar el estado S.M.A.R.T. de los discos']='check disk S.M.A.R.T. status'
MINT_DOCTOR_EN_EXTRA3['instalar y activar TLP']='install and enable TLP'
MINT_DOCTOR_EN_EXTRA3['instalar cabeceras del kernel y reconstruir módulos DKMS']='install kernel headers and rebuild DKMS modules'
MINT_DOCTOR_EN_EXTRA3['instalar las Guest Additions de VirtualBox']='install the VirtualBox Guest Additions'
MINT_DOCTOR_EN_EXTRA3['instalar Timeshift']='install Timeshift'
MINT_DOCTOR_EN_EXTRA3['comprobar las instantáneas reales de Timeshift']='check the real Timeshift snapshots'
MINT_DOCTOR_EN_EXTRA3['Disco /:']='Disk /:'
MINT_DOCTOR_EN_EXTRA3['Esto suele ocurrir tras un apagado brusco o un Administrador de actualizaciones colgado.']='This usually happens after an abrupt shutdown or a hung Update Manager.'
MINT_DOCTOR_EN_EXTRA3['usa']='uses'
MINT_DOCTOR_EN_EXTRA3['Clave:']='Key:'
MINT_DOCTOR_EN_EXTRA3['Repositorio:']='Repository:'
MINT_DOCTOR_EN_EXTRA3['no identificado, revisa el log']='not identified; check the log'
MINT_DOCTOR_EN_EXTRA3['Licencia GPLv3; consulte el archivo LICENSE.txt para el texto completo.']='GPLv3 license; see the LICENSE.txt file for the full text.'

for _k in "${!MINT_DOCTOR_EN_EXTRA[@]}"; do MINT_DOCTOR_EN["$_k"]="${MINT_DOCTOR_EN_EXTRA[$_k]}"; done
for _k in "${!MINT_DOCTOR_EN_EXTRA2[@]}"; do MINT_DOCTOR_EN["$_k"]="${MINT_DOCTOR_EN_EXTRA2[$_k]}"; done
for _k in "${!MINT_DOCTOR_EN_EXTRA3[@]}"; do MINT_DOCTOR_EN["$_k"]="${MINT_DOCTOR_EN_EXTRA3[$_k]}"; done
unset _k


# --------------------------------------------------------------------
# Config y estado global
# --------------------------------------------------------------------
# Semver (semver.org). Al publicar: sube este número y crea un tag de git a
# juego, "vX.Y.Z", en el mismo commit (historial completo en CHANGELOG.md).
SCRIPT_VERSION="1.14.1"
SCRIPT_NAME="Mint-Doctor"
LOG_DIR="${HOME}/.mint-doctor"
MAX_LOG_FILES=20
LOG_FILE=/dev/null   # lo rellena init_logging(); redirigir aquí antes es inofensivo

# Crea LOG_DIR/LOG_FILE y purga sesiones antiguas. Se llama desde main()
# después de comprobar que no se ejecuta como root.
init_logging() {
    # "-$$" evita que dos sesiones iniciadas en el mismo segundo compartan archivo.
    LOG_FILE="${LOG_DIR}/sesion-$(date +%Y%m%d-%H%M%S)-$$.log"
    # Permisos restringidos: el log puede incluir hostnames, IDs de clave GPG y rutas.
    mkdir -p "$LOG_DIR" 2>/dev/null
    chmod 700 "$LOG_DIR" 2>/dev/null
    if ! { touch "$LOG_FILE" 2>/dev/null && chmod 600 "$LOG_FILE" 2>/dev/null; }; then
        # Si $LOG_DIR no se puede escribir, se degrada a /dev/null en vez de
        # que cada mensaje posterior falle contra un archivo que nunca existió.
        echo "$(t 'Aviso: no se ha podido crear el registro; esta sesión continúa sin guardar registro.')" >&2
        LOG_FILE=/dev/null
        return
    fi

    # Conserva como máximo las MAX_LOG_FILES sesiones más recientes: el nombre
    # ya ordena cronológicamente como texto, así que basta un sort -r.
    local _old_logs
    mapfile -t _old_logs < <(find "$LOG_DIR" -maxdepth 1 -name 'sesion-*.log' 2>/dev/null \
                              | sort -r | tail -n "+$((MAX_LOG_FILES + 1))")
    (( ${#_old_logs[@]} > 0 )) && rm -f -- "${_old_logs[@]}"
}

DRY_RUN=0
AUTO_MODE=0
ISSUES_TOTAL=0
ISSUES_FIXED=0
ISSUES_SKIPPED=0
BOX_WIDTH=64
MINT_VERSION_OK=1
MINT_VERSION_WARNING=""

# --------------------------------------------------------------------
# Colores y símbolos (con degradación elegante si no hay terminal color)
# --------------------------------------------------------------------
# Respeta la convención NO_COLOR (no-color.org): cualquier valor no vacío
# desactiva el color aunque la terminal lo soporte.
if [[ -z "${NO_COLOR:-}" ]] && [[ -t 1 ]] && command -v tput &>/dev/null && [[ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]]; then
    C_RESET="$(tput sgr0)"
    C_BOLD="$(tput bold)"
    C_DIM="$(tput dim)"
    C_RED="$(tput setaf 1)"
    C_GREEN="$(tput setaf 2)"
    C_YELLOW="$(tput setaf 3)"
    C_BLUE="$(tput setaf 4)"
    C_CYAN="$(tput setaf 6)"
else
    C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""
    C_YELLOW=""; C_BLUE=""; C_CYAN=""
fi

ICON_OK="${C_GREEN}✔${C_RESET}"
ICON_ERR="${C_RED}✖${C_RESET}"
ICON_WARN="${C_YELLOW}⚠${C_RESET}"
ICON_INFO="${C_CYAN}ℹ${C_RESET}"
ICON_WAIT="${C_CYAN}…${C_RESET}"

# draw_box() suma 2 bordes + 2 espacios de margen a BOX_WIDTH, así que en una
# terminal más estrecha que BOX_WIDTH+4 columnas el borde derecho se
# desbordaría; se recorta al ancho real solo cuando hace falta.
if [[ -t 1 ]] && command -v tput &>/dev/null; then
    _term_cols="$(tput cols 2>/dev/null || echo 0)"
    if [[ "$_term_cols" =~ ^[0-9]+$ ]] && (( _term_cols > 0 && _term_cols - 4 < BOX_WIDTH )); then
        BOX_WIDTH=$(( _term_cols - 4 ))
        (( BOX_WIDTH < 40 )) && BOX_WIDTH=40
    fi
    unset _term_cols
fi

# --------------------------------------------------------------------
# Utilidades de interfaz
# --------------------------------------------------------------------

hr() {
    printf "%b" "${C_DIM}"
    printf '─%.0s' $(seq 1 "$BOX_WIDTH")
    printf "%b\n" "${C_RESET}"
}

# Rellena con espacios a la derecha hasta un ancho en CARACTERES, no bytes:
# "printf %-Ns" cuenta bytes y descuadraría cajas con tildes/ñ (UTF-8).
pad_right() {
    local str="$1" width="$2" pad
    pad=$(( width - ${#str} ))
    (( pad < 0 )) && pad=0
    printf '%s%*s' "$str" "$pad" ""
}

format_uptime() {
    local total_seconds="${1:-0}" days hours minutes
    [[ "$total_seconds" =~ ^[0-9]+$ ]] || return 1
    days=$((total_seconds / 86400))
    hours=$(((total_seconds % 86400) / 3600))
    minutes=$(((total_seconds % 3600) / 60))
    if [[ "$MINT_DOCTOR_LANG" == en ]]; then
        (( days > 0 )) && printf '%d day%s ' "$days" "$([[ $days -eq 1 ]] || echo s)"
        (( hours > 0 )) && printf '%d hour%s ' "$hours" "$([[ $hours -eq 1 ]] || echo s)"
        (( minutes > 0 || (days == 0 && hours == 0) )) && printf '%d minute%s' "$minutes" "$([[ $minutes -eq 1 ]] || echo s)"
    else
        (( days > 0 )) && printf '%d día%s ' "$days" "$([[ $days -eq 1 ]] || echo s)"
        (( hours > 0 )) && printf '%d hora%s ' "$hours" "$([[ $hours -eq 1 ]] || echo s)"
        (( minutes > 0 || (days == 0 && hours == 0) )) && printf '%d minuto%s' "$minutes" "$([[ $minutes -eq 1 ]] || echo s)"
    fi
}

draw_box() {
    # Dibuja una caja con las líneas pasadas como argumentos (una por línea)
    local width=$BOX_WIDTH
    printf "%b╔" "$C_CYAN"
    printf '═%.0s' $(seq 1 "$((width + 2))")
    printf "╗%b\n" "$C_RESET"
    local line
    for line in "$@"; do
        printf "%b║%b %s %b║%b\n" "$C_CYAN" "$C_RESET" "$(pad_right "$line" "$width")" "$C_CYAN" "$C_RESET"
    done
    printf "%b╚" "$C_CYAN"
    printf '═%.0s' $(seq 1 "$((width + 2))")
    printf "╝%b\n" "$C_RESET"
}

print_banner() {
    clear 2>/dev/null || true
    local cinnamon_ver mint_label
    cinnamon_ver=$(get_cinnamon_version)
    mint_label=$(get_mint_label)
    draw_box \
        "" \
        "   MINT-DOCTOR  ·  $(t 'Autoreparador') v${SCRIPT_VERSION}" \
        "   ${mint_label}  ·  Cinnamon ${cinnamon_ver}" \
        ""
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "  ${C_YELLOW}${C_BOLD}⚠ $(t 'MODO SIMULACIÓN ACTIVADO — no se aplicará ningún cambio')${C_RESET}"
    fi
    if [[ $MINT_VERSION_OK -eq 0 ]]; then
        echo -e "  ${C_YELLOW}${C_BOLD}⚠ $(t "${MINT_VERSION_WARNING}")${C_RESET}"
    fi
    echo
}

section_header() {
    local title="$(t "$1")"
    echo
    echo -e "${C_BLUE}${C_BOLD}▶ $title${C_RESET}"
    hr
}

log_line() {
    # log_line NIVEL "mensaje"
    local level="$1"; shift
    printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "$LOG_FILE"
}

msg_ok()   { local msg; msg="$(t "$1")"; echo -e "  ${ICON_OK} $msg"; log_line "OK" "$msg"; }
msg_err()  { local msg; msg="$(t "$1")"; echo -e "  ${ICON_ERR} $msg"; log_line "ERROR" "$msg"; }
msg_warn() { local msg; msg="$(t "$1")"; echo -e "  ${ICON_WARN} $msg"; log_line "WARNING" "$msg"; }
msg_info() { local msg; msg="$(t "$1")"; echo -e "  ${ICON_INFO} $msg"; log_line "INFO" "$msg"; }

# Indenta (6 espacios) cada línea de un bloque de texto multilínea, para
# mostrarlo bajo un msg_warn/msg_err ya indentado a 2 espacios por su icono.
indent_block() {
    local line
    while IFS= read -r line; do
        printf '      %s\n' "$line"
    done <<< "$1"
}

pause() {
    [[ $AUTO_MODE -eq 1 ]] && return 0
    echo
    read -rp "$(echo -e "${C_DIM}$(t 'Pulsa Enter para continuar...')${C_RESET}")" _
}

# Bucle de confirmación s/n compartido por ask_yes_no() y ask_yes_no_always().
# Devuelve 0 = sí, 1 = no (también si no hay terminal para leer, p. ej. cron).
_ask_yes_no_loop() {
    local prompt="$1" ans choice_hint
    if [[ "$MINT_DOCTOR_LANG" == en ]]; then
        choice_hint="[y/N]"
    else
        choice_hint="[s/N]"
    fi
    while true; do
        read -rp "$(echo -e "  ${C_BOLD}$(t "$prompt")${C_RESET} ${choice_hint}: ")" ans || return 1
        case "${ans,,}" in
            y|yes|s|si|sí) return 0 ;;
            n|no|"") return 1 ;;
            *)
                if [[ "$MINT_DOCTOR_LANG" == en ]]; then
                    echo "    Answer 'y' (yes) or 'n' (no)."
                else
                    echo "    Responde 's' (sí) o 'n' (no)."
                fi
                ;;
        esac
    done
}

ask_yes_no() {
    # ask_yes_no "pregunta" -> 0 = sí, 1 = no. En --auto responde "sí" sin preguntar.
    [[ $AUTO_MODE -eq 1 ]] && return 0
    _ask_yes_no_loop "$1"
}

# Igual que ask_yes_no, pero IGNORA --auto: para decisiones que aumentan la
# confianza del sistema (p. ej. importar una clave GPG nueva) y nunca deben
# aceptarse solas, ni siquiera en modo automático. Sin terminal para
# preguntar, "read" falla y se responde "no" por seguridad.
ask_yes_no_always() {
    _ask_yes_no_loop "$1"
}

# Ejecuta un paso de reparación. Respeta el modo simulación y registra en el log.
run_step() {
    local desc="$1"; shift
    local ui_desc
    ui_desc="$(t "$desc")"
    if [[ "$MINT_DOCTOR_LANG" == en ]]; then
        log_line "ACTION" "$ui_desc :: $*"
    else
        log_line "ACCION" "$ui_desc :: $*"
    fi
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "  ${C_YELLOW}[$(t 'SIMULACIÓN')]${C_RESET} $(t 'Se ejecutaría:') ${C_DIM}$*${C_RESET}"
        return 0
    fi
    echo -e "  ${ICON_WAIT} $(t 'Aplicando:') ${ui_desc}..."
    local log_before
    log_before=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if "$@" >>"$LOG_FILE" 2>&1; then
        msg_ok "Hecho: ${ui_desc}"
        ISSUES_FIXED=$((ISSUES_FIXED + 1))
        return 0
    else
        # Últimas líneas que el propio comando acaba de escribir en el log:
        # para pasos como "dpkg --configure -a" la causa real (p. ej. "/boot"
        # sin espacio, un hook de DKMS roto...) casi siempre está ahí mismo.
        local tail_out
        tail_out=$(tail -n "+$((log_before + 1))" "$LOG_FILE" 2>/dev/null | tail -n 8)
        msg_err "Falló: ${ui_desc}"
        if [[ -n "$tail_out" ]]; then
            echo -e "  ${C_DIM}$(t 'Últimas líneas de la salida:')${C_RESET}"
            indent_block "$tail_out"
        fi
        echo -e "  ${C_DIM}$(t 'Registro completo:') ${LOG_FILE}${C_RESET}"
        return 1
    fi
}

# Como run_step(), pero valida sudo antes: así --dry-run no pide contraseña
# real y una autenticación fallida no llega a ejecutar nada a ciegas.
run_step_sudo() {
    local reason="$1" desc="$2"; shift 2
    if [[ $DRY_RUN -eq 1 ]] || ensure_sudo "$reason"; then
        run_step "$desc" "$@"
        return $?
    fi
    msg_warn "No se ha podido aplicar: ${desc} (sin permisos de administrador)."
    return 1
}

need_cmd() { command -v "$1" &>/dev/null; }

# Versión de Cinnamon, cacheada: print_banner() se repinta en cada vuelta del
# menú y, sin caché, relanzaría "cinnamon --version" (hasta 2s si está colgado).
CINNAMON_VERSION_CACHE=""
get_cinnamon_version() {
    if [[ -z "$CINNAMON_VERSION_CACHE" ]]; then
        CINNAMON_VERSION_CACHE=$(timeout 2 cinnamon --version 2>/dev/null | grep -oP '[\d.]+' | head -1)
        [[ -z "$CINNAMON_VERSION_CACHE" ]] && CINNAMON_VERSION_CACHE="$(t 'no detectado')"
    fi
    printf '%s' "$CINNAMON_VERSION_CACHE"
}

# Igual que get_cinnamon_version(), pero para "Mint X.Y \"Codename\"": lee
# RELEASE/CODENAME de /etc/linuxmint/info para no quedar fijo en 22.3.
MINT_LABEL_CACHE=""
get_mint_label() {
    if [[ -z "$MINT_LABEL_CACHE" ]]; then
        local rel cn
        rel=$(grep -oP '(?<=^RELEASE=).*' /etc/linuxmint/info 2>/dev/null | tr -d '"')
        cn=$(grep -oP '(?<=^CODENAME=).*' /etc/linuxmint/info 2>/dev/null | tr -d '"')
        if [[ -n "$rel" && -n "$cn" ]]; then
            MINT_LABEL_CACHE="Linux Mint ${rel} \"${cn^}\""
        else
            MINT_LABEL_CACHE='Linux Mint 22.3 "Zena"'
        fi
    fi
    printf '%s' "$MINT_LABEL_CACHE"
}

# Escapa los metacaracteres de una expresión regular básica (BRE) para poder
# buscar una cadena de forma literal: sin esto, los puntos de "uname -r"
# (p. ej. "6.14.0-15-generic") coincidirían con cualquier carácter.
re_escape() {
    printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g'
}

# Convierte un tamaño legible (p. ej. "1,2G", "512M", "800K") a un entero en
# MB, para poder comparar contra umbrales numéricos en vez de texto.
size_to_mb() {
    local raw="${1//,/.}" num unit
    unit="${raw: -1}"
    num="${raw%"${unit}"}"
    [[ "$num" =~ ^[0-9.]+$ ]] || { echo 0; return; }
    case "$unit" in
        T|t) awk -v n="$num" 'BEGIN{printf "%d", n*1024*1024}' ;;
        G|g) awk -v n="$num" 'BEGIN{printf "%d", n*1024}' ;;
        M|m) awk -v n="$num" 'BEGIN{printf "%d", n}' ;;
        K|k) awk -v n="$num" 'BEGIN{printf "%d", n/1024}' ;;
        B|b) awk -v n="$num" 'BEGIN{printf "%d", n/1024/1024}' ;;
        *)   echo 0 ;;
    esac
}

# sudo con aviso claro de por qué se pide la contraseña. Devuelve 1 si no se
# han podido obtener permisos (p. ej. sin terminal, típico desde cron); quien
# llama debe comprobar el código de salida antes de fiarse del resultado.
ensure_sudo() {
    local reason="$1"
    # No se salta en --dry-run: "sudo -v" no aplica ningún cambio por sí
    # mismo, así que comprobarlo aquí no rompe la promesa de --dry-run.
    msg_info "Esta acción necesita permisos de administrador (${reason})."
    if ! sudo -v; then
        msg_err "No se han podido obtener permisos de administrador (${reason})."
        return 1
    fi
}

register_issue() {
    ISSUES_TOTAL=$((ISSUES_TOTAL + 1))
}

register_skip() {
    ISSUES_SKIPPED=$((ISSUES_SKIPPED + 1))
    if [[ -t 0 ]]; then
        msg_warn "Omitido por el usuario."
    else
        msg_warn "Omitido (sin terminal para confirmar, p. ej. ejecución desatendida)."
    fi
}

# --------------------------------------------------------------------
# Panel rápido de estado (solo lectura, sin sudo, rápido)
# --------------------------------------------------------------------
quick_status() {
    local disk_pct disk_line ram_line apt_state net_state upd_line upd_count
    local disk_used disk_free ram_used ram_total
    read -r disk_used disk_free disk_pct < <(df -h / 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5,$4,$5}')
    read -r ram_used ram_total < <(free -h 2>/dev/null | awk 'NR==2{print $3,$2}')
    if [[ "$MINT_DOCTOR_LANG" == en ]]; then
        disk_line="${disk_pct:-?}% used (${disk_free:-?} free)"
        ram_line="${ram_used:-?} used of ${ram_total:-?}"
    else
        disk_line="${disk_pct:-?}% usado (${disk_free:-?} libres)"
        ram_line="${ram_used:-?} usados de ${ram_total:-?}"
    fi

    if dpkg --audit 2>/dev/null | grep -q .; then
        apt_state="${ICON_WARN} $(t 'paquetes a medio instalar')"
    else
        apt_state="${ICON_OK} $(t 'sin problemas evidentes')"
    fi

    if systemctl is-active --quiet NetworkManager 2>/dev/null; then
        net_state="${ICON_OK} $(t 'activa')"
    else
        net_state="${ICON_WARN} $(t 'NetworkManager inactivo')"
    fi

    # Recuento según la caché local de APT (no descarga nada; puede quedar
    # desactualizado hasta el próximo "apt-get update", que el módulo 3
    # refresca). LC_ALL=C evita depender del texto traducido de "apt list".
    upd_count=$(LC_ALL=C apt list --upgradable 2>/dev/null | grep -c upgradable || true)
    if [[ "$upd_count" -gt 0 ]] 2>/dev/null; then
        upd_line="${ICON_WARN} $upd_count $(t 'paquete(s) esperando actualizarse')"
    else
        upd_line="${ICON_OK} $(t 'el sistema está al día')"
    fi

    echo -e "${C_BOLD}$(t 'Estado rápido del sistema')${C_RESET}"
    hr
    printf "  %-22s %s\n" "$(t 'Disco (/):')" "${disk_line:-$(t 'desconocido')}"
    printf "  %-22s %s\n" "$(t 'Memoria RAM:')" "${ram_line:-$(t 'desconocido')}"
    printf "  %-22s %b\n" "$(t 'Paquetes / APT:')" "$apt_state"
    printf "  %-22s %b\n" "$(t 'Actualizaciones:')" "$upd_line"
    printf "  %-22s %b\n" "$(t 'Red:')" "$net_state"
    if [[ -n "$disk_pct" ]] && [[ "$disk_pct" -ge 90 ]] 2>/dev/null; then
        echo -e "  ${ICON_WARN} ${C_YELLOW}$(t 'El disco está casi lleno, revisa la opción 4 (limpieza de caché).')${C_RESET}"
    fi
    echo
}

# ======================================================================
# MÓDULO 1: Información del sistema
# ======================================================================
mod_info() {
    section_header "Información del sistema"
    local mint_ver base_ver kernel cinnamon_ver uptime_str session_type
    mint_ver=$(grep -oP '(?<=PRETTY_NAME=").*(?=")' /etc/os-release 2>/dev/null)
    base_ver=$(grep -oP '(?<=DISTRIB_DESCRIPTION=).*' /etc/upstream-release/lsb-release 2>/dev/null | tr -d '"')
    [[ -z "$mint_ver" ]] && mint_ver="$(t 'desconocida')"
    [[ -n "$base_ver" ]] && mint_ver="${mint_ver}  (base: ${base_ver})"
    kernel=$(uname -r)
    # Timeout y caché ya aplicados dentro de get_cinnamon_version().
    cinnamon_ver=$(get_cinnamon_version)
    uptime_str=$(format_uptime "$(awk '{print int($1)}' /proc/uptime 2>/dev/null)")
    session_type="${XDG_SESSION_TYPE:-$(t 'desconocida')}"

    printf "  %s %s\n" "$(pad_right "$(t 'Distribución:')" 22)" "${mint_ver:-desconocida}"
    printf "  %-22s %s\n" "Kernel:" "$kernel"
    printf "  %-22s %s\n" "Cinnamon:" "$cinnamon_ver"
    printf "  %-22s %s\n" "$(t 'Tiempo encendido:')" "${uptime_str:-$(t 'desconocido')}"
    printf "  %s %s\n" "$(pad_right "$(t 'Sesión gráfica:')" 22)" "$session_type"
    # La sesión Wayland de Cinnamon 6.6 sigue siendo experimental; sus
    # cuelgues/parpadeos a veces se confunden con un fallo de hardware.
    if [[ "$session_type" == "wayland" ]]; then
        msg_info "La sesión Wayland de Cinnamon aún es experimental en esta versión; si notas"
        msg_info "cuelgues o parpadeos, prueba \"Cinnamon (en X11)\" en el icono de la pantalla de inicio de sesión."
    fi
    # LC_ALL=C fuerza lscpu a inglés: en español traduce "Model name" y el
    # grep no encontraría nada.
    printf "  %-22s %s\n" "CPU:" "$(LC_ALL=C lscpu 2>/dev/null | grep 'Model name' | sed 's/Model name:\s*//')"

    # Tabla con printf+pad_right, no con el %-Ns de awk: mawk cuenta BYTES, no
    # caracteres, y "$(t 'Tamaño')" con su "ñ" descuadraría la columna siguiente.
    local d_size d_used d_free d_pct m_total m_used m_free
    read -r _ d_size d_used d_free d_pct _ < <(df -h / 2>/dev/null | awk 'NR==2')
    read -r _ m_total m_used m_free _ < <(free -h 2>/dev/null | awk 'NR==2')
    echo
    printf "  %s %s %s %s %s\n" "$(pad_right "" 22)" "$(pad_right "$(t 'Tamaño')" 8)" "$(pad_right "$(t 'Usado')" 8)" "$(pad_right "$(t 'Libre')" 8)" "$(t 'Uso%')"
    printf "  %s %s %s %s %s\n" "$(pad_right "$(t 'Disco /:')" 22)" "$(pad_right "${d_size:-?}" 8)" "$(pad_right "${d_used:-?}" 8)" "$(pad_right "${d_free:-?}" 8)" "${d_pct:-?}"
    printf "  %s %s %s %s\n" "$(pad_right "" 22)" "$(pad_right "Total" 8)" "$(pad_right "$(t 'Usado')" 8)" "$(t 'Libre')"
    printf "  %s %s %s %s\n" "$(pad_right "$(t 'Memoria RAM:')" 22)" "$(pad_right "${m_total:-?}" 8)" "$(pad_right "${m_used:-?}" 8)" "${m_free:-?}"
    echo

    # Mint bloquea Snap de fábrica vía nosnap.pref desde la versión 20; es una
    # decisión de diseño, no un fallo, así que no llama a register_issue.
    if [[ -f /etc/apt/preferences.d/nosnap.pref ]]; then
        msg_info "Snap está bloqueado de fábrica (política de Mint desde la versión 20; ver"
        msg_info "/etc/apt/preferences.d/nosnap.pref). \"apt install snapd\" no instalará nada mientras"
        msg_info "ese archivo exista; solo hace falta tocarlo si necesitas una app que solo exista como Snap."
    fi

    msg_info "Esta sección es solo informativa, no realiza cambios."
}

# ======================================================================
# MÓDULO 2: Paquetes y APT/dpkg
# ======================================================================
mod_apt() {
    section_header "Paquetes y gestor APT/dpkg"
    local found_issue=0

    # --- 2.1 Bloqueos (locks) obsoletos ---
    # "fuser" es lo único que distingue un bloqueo obsoleto de uno real en
    # uso; sin él no se puede ofrecer borrarlos con seguridad.
    msg_info "Comprobando bloqueos de APT/dpkg..."
    if ! need_cmd fuser; then
        found_issue=1
        register_issue
        msg_warn "No se puede comprobar con seguridad si los archivos de bloqueo de apt/dpkg siguen en uso:"
        msg_warn "falta el comando 'fuser' (paquete psmisc). Sin él, Mint-Doctor no puede distinguir un"
        msg_warn "bloqueo obsoleto de uno real, así que no ofrece eliminarlos a ciegas."
        if ask_yes_no "¿Instalar psmisc para poder comprobar esto de forma segura?"; then
            run_step_sudo "instalar psmisc" "instalar psmisc" sudo apt-get -y install psmisc
        else
            register_skip
        fi
    elif ensure_sudo "comprobar si los archivos de bloqueo de apt/dpkg siguen en uso"; then
        local lock_files=(/var/lib/dpkg/lock-frontend /var/lib/dpkg/lock
                           /var/cache/apt/archives/lock /var/lib/apt/lists/lock)
        local stale_locks=()
        local f
        for f in "${lock_files[@]}"; do
            if [[ -e "$f" ]]; then
                if ! sudo fuser "$f" &>/dev/null; then
                    stale_locks+=("$f")
                fi
            fi
        done
        if [[ ${#stale_locks[@]} -gt 0 ]]; then
            found_issue=1
            register_issue
            msg_warn "Se han encontrado archivos de bloqueo que ningún proceso está usando:"
            printf "      %s\n" "${stale_locks[@]}"
            echo -e "  ${C_DIM}$(t 'Esto suele ocurrir tras un apagado brusco o un Administrador de actualizaciones colgado.')${C_RESET}"
            if ask_yes_no "¿Eliminar estos bloqueos obsoletos?"; then
                run_step_sudo "eliminar bloqueos de apt/dpkg" "eliminar bloqueos obsoletos" sudo rm -f "${stale_locks[@]}"
            else
                register_skip
            fi
        else
            msg_ok "No hay bloqueos obsoletos."
        fi
    else
        msg_warn "No se ha podido comprobar el estado de los bloqueos (sin permisos de administrador)."
    fi

    # --- 2.2 Instalación de paquetes interrumpida ---
    msg_info "Comprobando paquetes a medio instalar/configurar..."
    local audit_out
    audit_out=$(dpkg --audit 2>/dev/null)
    if [[ -n "$audit_out" ]]; then
        found_issue=1
        register_issue
        msg_warn "Hay paquetes en un estado inconsistente (instalación interrumpida):"
        indent_block "$audit_out"

        # Aviso orientativo (no bloquea el intento): si el kernel está entre
        # los paquetes afectados, la causa más habitual de que su postinst
        # falle es que no cabe el nuevo vmlinuz/initrd en /boot. "df /boot"
        # funciona igual si /boot es una partición propia o solo un
        # directorio de /, así que no hace falta distinguir el caso.
        if [[ "$audit_out" == *linux-image* || "$audit_out" == *linux-headers* ]]; then
            local boot_avail_mb
            boot_avail_mb=$(df --output=avail -m /boot 2>/dev/null | tail -n1 | tr -d ' ')
            if [[ "$boot_avail_mb" =~ ^[0-9]+$ ]] && (( boot_avail_mb < 150 )); then
                msg_warn "Y /boot solo tiene ${boot_avail_mb}MB libres: causa muy habitual de que un"
                msg_warn "linux-image/linux-headers se quede a medio configurar. Si el paso de abajo"
                msg_warn "falla, libera espacio ahí (opción 4, o elimina kernels antiguos) y repite."
            fi
        fi

        if ask_yes_no "¿Reconfigurar los paquetes pendientes con 'dpkg --configure -a'?"; then
            run_step_sudo "reconfigurar paquetes" "reconfigurar paquetes pendientes" sudo dpkg --configure -a
        else
            register_skip
        fi
    else
        msg_ok "No hay instalaciones a medias."
    fi

    # --- 2.3 Dependencias rotas ---
    # Se detecta por el código de salida (100 = fallo, igual en cualquier
    # idioma), no por texto: "apt-get check" traduce sus mensajes y en
    # español no contiene "error"/"broken"/"roto" en ningún sitio.
    msg_info "Comprobando dependencias rotas..."
    if ensure_sudo "comprobar el estado real de las dependencias"; then
        local check_out check_rc
        check_out=$(sudo apt-get check 2>&1)
        check_rc=$?
        if [[ $check_rc -ne 0 ]]; then
            found_issue=1
            register_issue
            msg_warn "Se han detectado dependencias rotas:"
            indent_block "$check_out"
            if ask_yes_no "¿Intentar reparar dependencias con 'apt --fix-broken install'?"; then
                run_step_sudo "reparar dependencias" "reparar dependencias rotas" sudo apt-get -y --fix-broken install
            else
                register_skip
            fi
        else
            msg_ok "No hay dependencias rotas."
        fi
    else
        msg_warn "No se ha podido comprobar si hay dependencias rotas (sin permisos de administrador)."
    fi

    # --- 2.4 Paquetes retenidos (held) ---
    msg_info "Comprobando paquetes retenidos (hold)..."
    local held
    held=$(apt-mark showhold 2>/dev/null)
    if [[ -n "$held" ]]; then
        found_issue=1
        register_issue
        msg_warn "Los siguientes paquetes están retenidos y no se actualizarán:"
        indent_block "$held"
        msg_info "Si no lo hiciste tú a propósito, puedes liberarlos con: sudo apt-mark unhold <paquete>"
    else
        msg_ok "No hay paquetes retenidos."
    fi

    # --- 2.5 Bit setuid de pkexec perdido ---
    # pkexec debe ser -rwsr-xr-x root:root (modo 4755); sin el setuid, las
    # herramientas gráficas con privilegios (Gestor de actualizaciones,
    # Timeshift, Synaptic...) fallan al pedir la contraseña con mensajes poco
    # claros, aunque "sudo" en terminal siga funcionando. Se repara con sudo,
    # no con pkexec, para no depender del propio fallo que corrige.
    msg_info "Comprobando el bit setuid de pkexec..."
    local pkexec_path
    pkexec_path=$(command -v pkexec 2>/dev/null)
    if [[ -n "$pkexec_path" ]]; then
        local pkexec_owner
        pkexec_owner=$(stat -c '%U' "$pkexec_path" 2>/dev/null)
        if [[ -u "$pkexec_path" ]] && [[ "$pkexec_owner" == "root" ]]; then
            msg_ok "pkexec conserva su bit setuid (propietario root)."
        else
            found_issue=1
            register_issue
            msg_warn "pkexec ($pkexec_path) ha perdido el bit setuid o su propietario no es root."
            msg_warn "Suele pasar al restaurar una copia de seguridad sin permisos especiales, con un"
            msg_warn "endurecimiento de seguridad mal aplicado, o con la partición montada \"nosuid\"."
            if ask_yes_no "¿Restaurar los permisos correctos de pkexec (root:root, modo 4755)?"; then
                if [[ $DRY_RUN -eq 1 ]] || ensure_sudo "restaurar los permisos de pkexec"; then
                    # Dos pasos para un problema: cada run_step suma 1 a
                    # ISSUES_FIXED si tiene éxito. Se resta aquí, tras el
                    # primero, para que solo el segundo deje el contador en +1
                    # si ambos salen bien (si el chmod fallara, el chown ya no
                    # contaría solo como "arreglado").
                    if run_step "restaurar propietario de pkexec" sudo chown root:root "$pkexec_path"; then
                        [[ $DRY_RUN -eq 1 ]] || ISSUES_FIXED=$((ISSUES_FIXED - 1))
                        run_step "restaurar bit setuid de pkexec" sudo chmod 4755 "$pkexec_path"
                    fi
                else
                    msg_warn "No se han podido restaurar los permisos de pkexec (sin permisos de administrador)."
                fi
            else
                register_skip
            fi
        fi
    else
        found_issue=1
        register_issue
        msg_warn "pkexec no está instalado: las herramientas gráficas con privilegios (Gestor de"
        msg_warn "actualizaciones, Timeshift, Synaptic...) no podrán pedir la contraseña."
        if ask_yes_no "¿Instalar policykit-1 (proporciona pkexec) para restaurar la elevación de privilegios gráfica?"; then
            run_step_sudo "instalar policykit-1" "instalar policykit-1" sudo apt-get -y install policykit-1
        else
            register_skip
        fi
    fi

    # --- 2.6 Bit setuid de sudo perdido (solo diagnóstico) ---
    # Si el propio "sudo" ha perdido su setuid, ni este script ni "sudo"
    # pueden repararlo (la reparación necesitaría sudo: sería circular). Solo
    # se explica el problema y el comando exacto para corregirlo como root,
    # desde el modo de recuperación o un USB en vivo.
    local sudo_path
    sudo_path=$(command -v sudo 2>/dev/null)
    if [[ -n "$sudo_path" ]]; then
        if [[ -u "$sudo_path" ]]; then
            msg_ok "sudo conserva su bit setuid."
        else
            found_issue=1
            register_issue
            msg_err "sudo ($sudo_path) ha perdido su bit setuid. Ni este script ni sudo pueden arreglarlo:"
            msg_err "la propia reparación necesitaría sudo, así que sería circular."
            msg_info "Arréglalo como root, desde el modo de recuperación o un USB en vivo, con:"
            msg_info "  chown root:root $sudo_path && chmod 4755 $sudo_path"
        fi
    fi

    [[ $found_issue -eq 0 ]] && msg_ok "El subsistema de paquetes está sano."
}

# Comenta las referencias a $host en $file. Soporta el formato clásico de una
# línea (.list) y el formato deb822 (.sources, habitual desde Ubuntu 24.04 /
# Mint 22.x), donde un repositorio es un bloque de varias líneas: ahí hay que
# comentar el bloque entero o el archivo queda con una estrofa rota.
#
# La coincidencia respeta límites de palabra (como el "grep -w" del módulo
# 3.0): buscar el host "una" no comenta por error "fortuna-labs" en su URL.
# Compara $host de forma literal (index/substr), así que no hace falta
# escapar sus caracteres especiales.
comment_source_host() {
    local host="$1" file="$2" tmp stanza_mode=0
    [[ "$file" == *.sources ]] && stanza_mode=1
    tmp="$(mktemp)"
    awk -v host="$host" -v stanza_mode="$stanza_mode" '
        function is_word_char(c) {
            return (c ~ /^[[:alnum:]_]$/)
        }
        function has_word_match(line,    start, blen, before, after, from, pos) {
            blen = length(host)
            if (blen == 0) return 0
            from = 1
            while (1) {
                pos = index(substr(line, from), host)
                if (pos == 0) return 0
                start = from + pos - 1
                before = (start == 1) ? "" : substr(line, start - 1, 1)
                after  = substr(line, start + blen, 1)
                if (!is_word_char(before) && !is_word_char(after)) return 1
                from = start + 1
            }
        }
        function flush(   i) {
            for (i = 1; i <= n; i++) {
                if (has && buf[i] !~ /^#/) print "# [mint-doctor] " buf[i]
                else print buf[i]
            }
            n = 0; has = 0
        }
        {
            if (stanza_mode && $0 == "") { flush(); print ""; next }
            n++; buf[n] = $0
            if (has_word_match($0)) has = 1
            if (!stanza_mode) flush()
        }
        END { flush() }
    ' "$file" > "$tmp"
    # Tres códigos de salida, no solo éxito/fallo:
    #   0 -> se modificó el archivo
    #   1 -> fallo real (p. ej. "sudo install" no pudo escribir)
    #   2 -> no había nada que cambiar (el host ya estaba comentado, p. ej. un
    #        bloque .sources con varios hosts caídos que ya quedó comentado
    #        entero al procesar el primero de ellos)
    # No convertir el 2 en un 0: quien llama necesita distinguir "no hacía
    # falta nada" de "fallo real" para no mostrar un "❌ Falló" falso.
    if cmp -s "$file" "$tmp"; then
        rm -f "$tmp"
        return 2
    fi
    if sudo install -m 644 -o root -g root "$tmp" "$file"; then
        rm -f "$tmp"
        return 0
    else
        rm -f "$tmp"
        return 1
    fi
}

# ======================================================================
# MÓDULO 3: Repositorios de software (orígenes, claves GPG)
# ======================================================================
mod_repos() {
    section_header "Repositorios de software (orígenes y claves GPG)"
    local found_issue=0

    # --- 3.0 Repositorios de terceros con el nombre en clave de una versión
    #     anterior de Mint/Ubuntu (p. ej. una PPA añadida a mano en 22/22.1/
    #     22.2 que nunca se actualizó a 22.3). Es muy habitual: a veces
    #     "apt-get update" avisa con un error claro, pero otras el paquete
    #     simplemente deja de recibir actualizaciones sin que se note. Es de
    #     solo lectura, así que, a diferencia del resto del módulo, se
    #     comprueba siempre, incluso en --dry-run.
    local ubuntu_codename mint_codename
    ubuntu_codename=$(grep -oP '(?<=^UBUNTU_CODENAME=).*' /etc/os-release 2>/dev/null | tr -d '"')
    mint_codename=$(grep -oP '(?<=^VERSION_CODENAME=).*' /etc/os-release 2>/dev/null | tr -d '"')
    # Nombres en clave de Mint/Ubuntu anteriores a "zena"/"noble". Cualquiera
    # de estos, como palabra completa, en un archivo de orígenes de terceros
    # es casi con toda seguridad un resto de una versión anterior del sistema
    # (se excluye aparte el propio repositorio oficial de Mint: ver más abajo).
    local old_codenames=(bionic focal jammy tara tessa tina tricia ulyana
                          ulyssa uma una vanessa vera victoria virginia
                          wilma xia zara)
    # No se corta en la primera coincidencia: un mismo archivo .sources puede
    # tener varios bloques con distintos nombres en clave antiguos, y si solo
    # se registrara el primero, el resto quedaría sin detectar ni comentar.
    local src stale_repo_files=() cn
    for src in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
        [[ -f "$src" ]] || continue
        [[ "$(basename "$src")" == "official-package-repositories.list" ]] && continue
        for cn in "${old_codenames[@]}"; do
            # Se ignoran las líneas ya comentadas: si no, una entrada que este
            # mismo script ya comentó en una ejecución anterior se seguiría
            # marcando como problema para siempre (nunca contaría como resuelta).
            grep -v '^[[:space:]]*#' "$src" 2>/dev/null | grep -qiw "$cn" && stale_repo_files+=("${src}:${cn}")
        done
    done

    if [[ ${#stale_repo_files[@]} -gt 0 ]]; then
        found_issue=1
        register_issue
        msg_warn "Hay repositorios de terceros que aún apuntan al nombre en clave de una versión"
        msg_warn "anterior de Mint/Ubuntu (esta es Mint 22.3 \"${mint_codename:-zena}\", base Ubuntu \"${ubuntu_codename:-noble}\"):"
        local entry
        for entry in "${stale_repo_files[@]}"; do
            echo "      ${entry%%:*}  ($(t 'usa') \"${entry##*:}\")"
        done
        msg_info "Suele pasar con una PPA o repositorio de terceros añadido a mano en una versión de Mint"
        msg_info "anterior que nunca se actualizó. A veces 'apt-get update' avisa con un error claro; otras"
        msg_info "veces el paquete simplemente deja de recibir actualizaciones sin ningún aviso visible."
        if ask_yes_no "¿Comentar (con copia de seguridad) esas líneas para dejar de usarlas?"; then
            if [[ $DRY_RUN -eq 1 ]]; then
                echo -e "  ${C_YELLOW}[$(t 'SIMULACIÓN')]${C_RESET} $(t 'Se comentarían las líneas/bloques de:') ${C_DIM}$(printf '%s ' "${stale_repo_files[@]%%:*}")${C_RESET}"
            elif ensure_sudo "modificar archivos de orígenes de software de terceros"; then
                local backup_cn
                backup_cn="${LOG_DIR}/sources-backup-codenames-$(date +%Y%m%d-%H%M%S).tar.gz"
                # La copia es un paso previo, no "el arreglo": si falla, no se toca
                # ningún archivo, y se resta el +1 que run_step ya sumó a
                # ISSUES_FIXED, para no contarla como un arreglo aparte.
                if run_step "copia de seguridad de /etc/apt/sources.list.d" \
                    tar -czf "$backup_cn" --ignore-failed-read /etc/apt/sources.list /etc/apt/sources.list.d; then
                    ISSUES_FIXED=$((ISSUES_FIXED - 1))
                    local file_cn rc_cn any_fixed_cn=0
                    for entry in "${stale_repo_files[@]}"; do
                        file_cn="${entry%%:*}"; cn="${entry##*:}"
                        if [[ "$MINT_DOCTOR_LANG" == en ]]; then log_line "ACTION" "comment $cn reference in $file_cn"; else log_line "ACCION" "comentar referencia a $cn en $file_cn"; fi
                        echo -e "  ${ICON_WAIT} $(t 'Aplicando:') comentar referencia a $cn en $file_cn..."
                        comment_source_host "$cn" "$file_cn"
                        rc_cn=$?
                        case $rc_cn in
                            0) msg_ok "Hecho: comentar referencia a $cn en $file_cn"; any_fixed_cn=1 ;;
                            2) log_line "INFO" "sin cambios: $file_cn ya estaba comentado" ;;
                            *) msg_err "Falló: comentar referencia a $cn en $file_cn (revisa el log para más detalle)" ;;
                        esac
                    done
                    [[ $any_fixed_cn -eq 1 ]] && ISSUES_FIXED=$((ISSUES_FIXED + 1))
                    msg_info "Copia de seguridad guardada en: $backup_cn"
                    msg_info "Si alguna de esas líneas sí publica paquetes para \"${ubuntu_codename:-noble}\", edítala a"
                    msg_info "mano desde 'Orígenes del software' en vez de restaurar el comentario."
                else
                    msg_err "No se ha podido crear la copia de seguridad; no se modificará ningún archivo."
                fi
            else
                msg_warn "No se han podido modificar los archivos (sin permisos de administrador)."
            fi
        else
            register_skip
        fi
    else
        msg_ok "Los repositorios de terceros usan el nombre en clave correcto (o no hay ninguno configurado)."
    fi

    # Aparte, y más serio: si el propio repositorio OFICIAL de Mint no
    # coincide con el nombre en clave de esta versión, nunca se toca de forma
    # automática. Puede significar una actualización de versión mayor que se
    # quedó a medias (documentado varias veces en el foro de Mint) o, más
    # raramente, que /etc/os-release se haya sobrescrito con los valores de
    # Ubuntu; comentar esa línea a ciegas podría dejar el sistema sin su
    # fuente principal de actualizaciones, así que aquí solo se avisa.
    local official_file="/etc/apt/sources.list.d/official-package-repositories.list"
    if [[ -f "$official_file" ]] && [[ -n "$mint_codename" ]]; then
        local official_line official_codename
        official_line=$(grep -P '^\s*deb\s+\S+\s+\S+\s+main\s+upstream\s+import\s+backport' "$official_file" 2>/dev/null | head -1)
        official_codename=$(awk '{print $3}' <<< "$official_line")
        if [[ -n "$official_codename" ]] && [[ "$official_codename" != "$mint_codename" ]]; then
            found_issue=1
            register_issue
            msg_err "El repositorio OFICIAL de Mint en $official_file usa el nombre en clave \"$official_codename\","
            msg_err "pero /etc/os-release identifica este sistema como \"$mint_codename\". Suele significar que una"
            msg_err "actualización de versión mayor se quedó a medias. Mint-Doctor no modifica este archivo"
            msg_err "automáticamente: revísalo a mano (o compáralo con 'cat /etc/linuxmint/info', que no se ve"
            msg_err "afectado por este problema) antes de instalar o actualizar más paquetes."
        fi
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        msg_warn "En modo simulación se omite el resto de este módulo: 'apt-get update' escribe la caché de"
        msg_warn "listas de paquetes en disco, no es una operación de solo lectura."
        msg_info "Ejecuta el script sin --dry-run para comprobar claves GPG y orígenes inaccesibles."
        return
    fi
    msg_info "Ejecutando 'apt-get update' para detectar repositorios con problemas (puede tardar)..."
    if ! ensure_sudo "actualizar la lista de repositorios"; then
        msg_warn "No se ha podido comprobar el estado de los repositorios (sin permisos de administrador)."
        return
    fi
    # Se fuerza LC_ALL/LANG=C solo para este comando (no para el resto del
    # script) porque el resto de este módulo reconoce la salida de apt-get
    # buscando texto en inglés ("Err:", "GPG error: ... The following
    # signatures..."). Con el sistema en español, apt-get traduciría esos
    # mensajes y la detección de errores/repositorios fallaría en silencio.
    local update_out update_rc
    update_out=$(sudo LC_ALL=C LANG=C apt-get update 2>&1)
    update_rc=$?
    echo "$update_out" >> "$LOG_FILE"

    local errors
    errors=$(echo "$update_out" | grep -E '^(Err:|E:|W:)')
    if [[ -z "$errors" ]]; then
        if [[ $update_rc -ne 0 ]]; then
            # apt-get devolvió fallo pero no dejó ninguna línea reconocible
            # de error (p. ej. sudo no pudo autenticar sin terminal, o no
            # hay red en absoluto). Mejor decirlo claramente que reportar
            # "todo correcto" sin haber comprobado nada de verdad.
            msg_err "'apt-get update' ha fallado y no se ha podido determinar por qué; revisa el log."
            register_issue
            return
        fi
        msg_ok "Todos los repositorios responden correctamente."
        return
    fi

    msg_warn "Se han encontrado problemas al consultar los repositorios:"
    indent_block "$errors"
    echo

    # 3.1 Claves GPG ausentes (NO_PUBKEY)
    # Importar una clave GPG significa confiar en todo lo que ese repositorio
    # firme a partir de ahora, así que se pregunta clave por clave (no en
    # bloque), mostrando el repositorio asociado a cada una para poder
    # reconocerlo. La pregunta ignora --auto: nunca se importa una clave
    # nueva sin confirmación humana explícita.
    local missing_keys
    missing_keys=$(echo "$update_out" | grep -oP 'NO_PUBKEY \K[0-9A-F]+' | sort -u)
    if [[ -n "$missing_keys" ]]; then
        # Empareja cada clave con el repositorio que aparece en la misma
        # línea de error ("GPG error: <repo>: ... NO_PUBKEY <clave>").
        declare -A key_repo
        local gpg_line k d
        while IFS= read -r gpg_line; do
            [[ -z "$gpg_line" ]] && continue
            d=$(grep -oP 'GPG error: \K.*(?=: The following signatures)' <<< "$gpg_line")
            # Una línea puede traer varias claves ("NO_PUBKEY AAA NO_PUBKEY
            # BBB"): se recorre cada coincidencia por separado para no
            # juntarlas en una sola clave de array que luego no se encuentre.
            while IFS= read -r k; do
                [[ -z "$k" ]] && continue
                if [[ -n "$d" ]]; then
                    key_repo["$k"]="$d"
                elif [[ -z "${key_repo[$k]+_}" ]]; then
                    key_repo["$k"]="repositorio no identificado, revisa el log"
                fi
            done < <(grep -oP 'NO_PUBKEY \K[0-9A-F]+' <<< "$gpg_line")
        done < <(echo "$update_out" | grep -i 'NO_PUBKEY')

        msg_warn "Faltan claves GPG para verificar algunos repositorios:"
        msg_warn "Importar una clave equivale a confiar en los paquetes que firme ese"
        msg_warn "repositorio. Revisa cada uno y solo acepta los que reconozcas."
        echo
        local key
        for key in $missing_keys; do
            found_issue=1
            register_issue
            echo -e "      ${C_BOLD}$(t 'Clave:')${C_RESET} $key"
            echo -e "      ${C_BOLD}$(t 'Repositorio:')${C_RESET} ${key_repo[$key]:-$(t 'no identificado, revisa el log')}"
            if ask_yes_no_always "  ¿Reconoces este repositorio e importas su clave?"; then
                if ensure_sudo "importar clave GPG $key"; then
                    # El chmod 644 es necesario: APT verifica firmas con el usuario
                    # "_apt" (sandbox), no como root, y con un umask restrictivo gpg
                    # podría crear el keyring en 600, inservible para apt. Los
                    # paréntesis importan: sin ellos "A || B && C" solo ejecuta C
                    # cuando hizo falta B. $key va como parámetro posicional ($1), no
                    # interpolado, para no depender de que sea siempre hexadecimal.
                    run_step "importar clave GPG $key" sudo bash -c \
                        '(gpg --no-default-keyring --keyring /etc/apt/trusted.gpg.d/mint-doctor-recovered.gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys "$1" \
                         || gpg --no-default-keyring --keyring /etc/apt/trusted.gpg.d/mint-doctor-recovered.gpg --keyserver hkps://keys.openpgp.org --recv-keys "$1") \
                         && chmod 644 /etc/apt/trusted.gpg.d/mint-doctor-recovered.gpg' _ "$key"
                else
                    msg_warn "No se ha podido importar la clave $key (sin permisos de administrador)."
                fi
            else
                register_skip
            fi
            echo
        done
        unset key_repo
    fi

    # 3.2 Firmas GPG inválidas (BADSIG)
    # A diferencia de NO_PUBKEY, aquí la clave SÍ se pudo comprobar pero la
    # firma no coincide: no se arregla importando nada, suele ser una caché
    # de listas corrupta o un espejo con problemas. Se limpia esa caché
    # (no concede ninguna confianza nueva) y se vuelve a consultar.
    local badsig_keys
    badsig_keys=$(echo "$update_out" | grep -oP 'BADSIG \K[0-9A-F]+' | sort -u)
    if [[ -n "$badsig_keys" ]]; then
        found_issue=1
        register_issue
        msg_err "Hay firmas GPG que no coinciden (BADSIG), no claves ausentes, para:"
        indent_block "$badsig_keys"
        msg_info "No se soluciona importando ninguna clave: suele deberse a una caché de listas de"
        msg_info "paquetes corrupta o a un espejo con problemas."
        if ask_yes_no "¿Limpiar la caché de listas de APT y reintentar 'apt-get update'?"; then
            if ensure_sudo "limpiar la caché de listas de APT"; then
                # Igual que en 2.5: se resta nada más confirmarse la limpieza,
                # para que solo la reconsulta posterior (el paso que de verdad
                # confirma que el problema se resolvió) deje el contador en +1.
                if run_step "limpiar caché de listas de APT" sudo rm -rf "/var/lib/apt/lists/"*; then
                    [[ $DRY_RUN -eq 1 ]] || ISSUES_FIXED=$((ISSUES_FIXED - 1))
                    run_step "volver a consultar repositorios (apt-get update)" sudo apt-get update
                fi
            else
                msg_warn "No se ha podido limpiar la caché de listas de APT (sin permisos de administrador)."
            fi
        else
            register_skip
        fi
    fi

    # 3.3 Repositorios inaccesibles (404 / no se pudo conectar)
    local bad_hosts
    bad_hosts=$(echo "$errors" | grep -oP 'Err:\d+ \K\S+' | sort -u)
    if [[ -n "$bad_hosts" ]]; then
        found_issue=1
        register_issue
        msg_warn "Estos orígenes no responden (pueden estar caídos, mal escritos o ya no existir):"
        indent_block "$bad_hosts"
        msg_info "Recomendación: abre 'Orígenes del software' (menú > Administración) y desmarca o elimina esas líneas,"
        msg_info "o cambia el servidor de descarga por uno más cercano/estable."
        if ask_yes_no "¿Quieres que comente automáticamente (con copia de seguridad) las líneas de sources.list que apuntan a esos orígenes caídos?"; then
            if ensure_sudo "modificar archivos de orígenes de software"; then
                local backup
                backup="${LOG_DIR}/sources-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
                # Sin sudo: sources.list y sources.list.d/* son legibles por
                # cualquier usuario, y así el .tar.gz queda con tu propio usuario
                # como dueño en vez de root dentro de ~/.mint-doctor.
                # Mismo criterio que en 3.0: la copia es un paso previo, no "el
                # arreglo", así que se resta el +1 que run_step ya sumó.
                if run_step "copia de seguridad de /etc/apt/sources.list*" \
                    tar -czf "$backup" --ignore-failed-read /etc/apt/sources.list /etc/apt/sources.list.d; then
                    ISSUES_FIXED=$((ISSUES_FIXED - 1))
                    # Se cuenta como "solucionado" una sola vez si se ha modificado al
                    # menos un archivo, no una vez por archivo tocado: el usuario ha
                    # confirmado UNA acción ("comentar los orígenes caídos"), aunque
                    # esa acción termine tocando varios archivos .list/.sources. Así
                    # el resumen final no muestra más arreglos que problemas
                    # detectados para este módulo.
                    local host host_re list_file rc any_fixed=0
                    for host in $bad_hosts; do
                        host_re=$(re_escape "$host")
                        for list_file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
                            [[ -f "$list_file" ]] || continue
                            if grep -q "$host_re" "$list_file" 2>/dev/null; then
                                if [[ "$MINT_DOCTOR_LANG" == en ]]; then log_line "ACTION" "comment $host reference in $list_file"; else log_line "ACCION" "comentar referencia a $host en $list_file"; fi
                                echo -e "  ${ICON_WAIT} $(t 'Aplicando:') comentar referencia a $host en $list_file..."
                                comment_source_host "$host" "$list_file"
                                rc=$?
                                case $rc in
                                    0)
                                        msg_ok "Hecho: comentar referencia a $host en $list_file"
                                        any_fixed=1
                                        ;;
                                    2)
                                        # Nada que hacer: por ejemplo el bloque .sources ya
                                        # quedó comentado entero al tratar otro host caído
                                        # del mismo bloque. No es un fallo, así que no se
                                        # muestra "❌ Falló" ni se cuenta como corrección.
                                        log_line "INFO" "sin cambios: $host ya estaba comentado en $list_file"
                                        ;;
                                    *)
                                        msg_err "Falló: comentar referencia a $host en $list_file (revisa el log para más detalle)"
                                        ;;
                                esac
                            fi
                        done
                    done
                    [[ $any_fixed -eq 1 ]] && ISSUES_FIXED=$((ISSUES_FIXED + 1))
                    msg_info "Copia de seguridad guardada en: $backup"
                else
                    msg_err "No se ha podido crear la copia de seguridad; no se modificará ningún archivo."
                fi
            else
                msg_warn "No se han podido modificar los archivos de orígenes (sin permisos de administrador)."
            fi
        else
            register_skip
        fi
    fi

    # 3.4 Claves en el keyring heredado (/etc/apt/trusted.gpg), obsoleto desde
    # Ubuntu 22.04+ (y por tanto en todo Mint 21/22.x). apt sigue funcionando
    # con normalidad, pero avisa en cada "apt-get update". Solo COPIAR las
    # claves a trusted.gpg.d no basta para que el aviso desaparezca: apt sigue
    # viendo contenido en /etc/apt/trusted.gpg y lo sigue señalando como
    # origen heredado. Por eso, tras copiarlas, el archivo original se
    # RENOMBRA (no se borra) a modo de copia de seguridad: ninguna clave se
    # pierde ni gana confianza nueva, solo cambia de sitio.
    local legacy_warn=0
    if echo "$update_out" | grep -qi "legacy trusted.gpg keyring"; then
        legacy_warn=1
        if [[ -s /etc/apt/trusted.gpg ]]; then
            found_issue=1
            register_issue
            msg_warn "Algunos repositorios firman con claves guardadas en el keyring heredado"
            msg_warn "(/etc/apt/trusted.gpg), un mecanismo obsoleto desde Ubuntu 22.04. No es grave y las"
            msg_warn "actualizaciones funcionan igual, pero apt avisa de ello en cada 'apt-get update'."
            if ask_yes_no "¿Migrar esas claves al directorio moderno (/etc/apt/trusted.gpg.d/) para que deje de avisar?"; then
                if ensure_sudo "migrar claves del keyring heredado a trusted.gpg.d"; then
                    if run_step "migrar claves heredadas a trusted.gpg.d" sudo bash -c \
                        'install -m 644 -o root -g root /etc/apt/trusted.gpg /etc/apt/trusted.gpg.d/mint-doctor-legacy-trusted.gpg &&
                         mv /etc/apt/trusted.gpg /etc/apt/trusted.gpg.bak-mint-doctor'; then
                        msg_info "El archivo original se conserva (sin usarse) en /etc/apt/trusted.gpg.bak-mint-doctor"
                    fi
                else
                    msg_warn "No se han podido migrar las claves heredadas (sin permisos de administrador)."
                fi
            else
                register_skip
            fi
        fi
    fi

    if [[ -z "$missing_keys" && -z "$badsig_keys" && -z "$bad_hosts" && $legacy_warn -eq 0 ]]; then
        found_issue=1
        register_issue
        msg_info "No se pudo clasificar el error automáticamente. Revisa el detalle arriba o abre 'Orígenes del software'."
    fi

    [[ $found_issue -eq 0 ]] && msg_ok "Los repositorios de software no muestran más problemas."
}

# ======================================================================
# MÓDULO 4: Espacio en disco y limpieza de caché
# ======================================================================
mod_cache() {
    section_header "Espacio en disco y limpieza de caché"
    local found_issue=0

    # 4.1 Caché de APT
    # Nota: "du -sh" de una carpeta vacía ya ocupa "4.0K" o similar (el propio
    # directorio), nunca "0" literal, así que comparar contra "0" siempre daba
    # positivo. Comprobamos en su lugar si hay .deb reales descargados.
    local apt_cache_size apt_deb_count
    apt_cache_size=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
    apt_deb_count=$(find /var/cache/apt/archives -maxdepth 1 -name '*.deb' 2>/dev/null | wc -l)
    msg_info "Caché de paquetes descargados (APT): ${apt_cache_size:-0} (${apt_deb_count} paquetes .deb)"
    if [[ "$apt_deb_count" -gt 0 ]]; then
        found_issue=1
        register_issue
        if ask_yes_no "¿Vaciar la caché de paquetes .deb ya instalados (apt clean)?"; then
            run_step_sudo "limpiar caché de apt" "limpiar caché de apt" sudo apt-get clean
        else
            register_skip
        fi
    else
        msg_ok "No hay paquetes .deb acumulados en la caché de APT."
    fi

    # 4.2 Kernels antiguos
    msg_info "Comprobando kernels antiguos instalados..."
    local current_kernel current_kernel_re installed_kernels old_kernels_count
    current_kernel=$(uname -r)
    current_kernel_re=$(re_escape "$current_kernel")
    # Solo paquetes de kernel versionados de verdad (p. ej.
    # "linux-image-6.8.0-40-generic"): empiezan con un dígito justo después
    # de "linux-image-". Los metapaquetes como "linux-image-generic" o
    # "linux-image-virtual" no siguen ese patrón y no son un kernel instalado
    # en sí (dependen de la versión real, que ya se cuenta aparte), así que
    # se excluyen para no inflar el recuento mostrado.
    installed_kernels=$(dpkg -l 'linux-image-*' 2>/dev/null | awk '/^ii/{print $2}' | grep -P '^linux-image-[0-9]' | grep -v "$current_kernel_re")
    old_kernels_count=$(echo "$installed_kernels" | grep -c . || true)
    # Umbral 2+, no 1+: conservar un único kernel antiguo (además del actual)
    # es la red de seguridad habitual para poder arrancar el anterior si el
    # más reciente da problemas, así que no se avisa por tener exactamente
    # uno. Solo se avisa cuando ya se han acumulado varios.
    if [[ "$old_kernels_count" -gt 1 ]]; then
        found_issue=1
        register_issue
        msg_warn "Hay $old_kernels_count kernels antiguos ocupando espacio (se conserva el actual: $current_kernel)."
        if ask_yes_no "¿Eliminar kernels y paquetes que ya no se usan (apt autoremove)?"; then
            run_step_sudo "eliminar paquetes obsoletos" "eliminar kernels y paquetes obsoletos" sudo apt-get -y autoremove --purge
        else
            register_skip
        fi
    else
        msg_ok "No hay kernels antiguos acumulados."
    fi

    # 4.3 Caché de miniaturas
    # Igual que con la caché de APT: una carpeta vacía ya ocupa varios KB por
    # sí misma, así que usamos un umbral numérico (1 MB) en vez de comparar
    # el texto de "du -sh" contra "0".
    local thumb_dir="$HOME/.cache/thumbnails"
    if [[ -d "$thumb_dir" ]]; then
        local thumb_kb thumb_size
        thumb_kb=$(du -sk "$thumb_dir" 2>/dev/null | cut -f1)
        thumb_size=$(du -sh "$thumb_dir" 2>/dev/null | cut -f1)
        msg_info "Caché de miniaturas: ${thumb_size:-0}"
        if [[ -n "$thumb_kb" ]] && (( thumb_kb > 1024 )); then
            found_issue=1
            register_issue
            if ask_yes_no "¿Vaciar la caché de miniaturas de imágenes/vídeos?"; then
                run_step "vaciar caché de miniaturas" rm -rf "${thumb_dir:?}/"*
            else
                register_skip
            fi
        else
            msg_ok "La caché de miniaturas no ocupa espacio significativo."
        fi
    fi

    # 4.4 Papelera
    local trash_dir="$HOME/.local/share/Trash"
    if [[ -d "$trash_dir/files" ]] && [[ -n "$(ls -A "$trash_dir/files" 2>/dev/null)" ]]; then
        local trash_size
        trash_size=$(du -sh "$trash_dir" 2>/dev/null | cut -f1)
        found_issue=1
        register_issue
        msg_warn "La papelera contiene ${trash_size:-datos} sin vaciar."
        if ask_yes_no "¿Vaciar la papelera?"; then
            run_step "vaciar papelera" rm -rf "${trash_dir:?}/files" "${trash_dir:?}/info"
        else
            register_skip
        fi
    fi

    # 4.5 Journal de systemd
    # journalctl --disk-usage es de solo lectura y en Mint el usuario normal
    # ya pertenece al grupo "adm"/"systemd-journal", así que no debería hacer
    # falta sudo; solo se recurre a él si la lectura sin privilegios falla.
    # Solo se ofrece recortar el journal si realmente pesa más de 200 MB.
    if need_cmd journalctl; then
        local journal_raw journal_mb
        journal_raw=$(journalctl --disk-usage 2>/dev/null | grep -oP '[\d.,]+[BKMG]' | tail -1)
        if [[ -z "$journal_raw" && $DRY_RUN -ne 1 ]] && ensure_sudo "leer el tamaño del journal de systemd"; then
            journal_raw=$(sudo journalctl --disk-usage 2>/dev/null | grep -oP '[\d.,]+[BKMG]' | tail -1)
        fi
        msg_info "Tamaño del registro del sistema (journal): ${journal_raw:-desconocido}"
        if [[ -z "$journal_raw" ]]; then
            msg_warn "No se ha podido determinar el tamaño del journal (sin permisos de administrador)."
        else
            journal_mb=$(size_to_mb "$journal_raw")
            if [[ "$journal_mb" -gt 200 ]]; then
                found_issue=1
                register_issue
                if ask_yes_no "¿Limitar el journal a 200 MB (se conservan los registros más recientes)?"; then
                    run_step_sudo "recortar el journal de systemd" "recortar journal a 200M" sudo journalctl --vacuum-size=200M
                else
                    register_skip
                fi
            else
                msg_ok "El registro del sistema no ocupa un espacio excesivo."
            fi
        fi
    fi

    # 4.6 Flatpak sin usar
    # Flatpak no ofrece una forma fiable de "listar sin tocar nada" los
    # runtimes sin usar en todas las versiones, así que esto no se cuenta
    # como "problema detectado" de antemano: se registra solo si el usuario
    # decide ejecutar la comprobación/limpieza.
    if need_cmd flatpak; then
        msg_info "Flatpak está instalado. Puede tener runtimes sin usar ocupando espacio."
        if ask_yes_no "¿Buscar y eliminar runtimes/dependencias de Flatpak que ya no usa ninguna aplicación?"; then
            if [[ $DRY_RUN -eq 1 ]]; then
                echo -e "  ${C_YELLOW}[$(t 'SIMULACIÓN')]${C_RESET} $(t 'Se ejecutaría:') ${C_DIM}flatpak uninstall --unused --noninteractive --assumeyes${C_RESET}"
            else
                # "flatpak uninstall --unused" siempre sale con éxito, incluso
                # sin nada que eliminar (imprime "Nothing unused to uninstall"),
                # así que run_step por sí solo no basta para saber si de verdad
                # se ha liberado algo: se mira la salida para no contar como
                # "problema" y "solucionado" una limpieza que no hizo nada.
                local flatpak_out flatpak_rc
                if [[ "$MINT_DOCTOR_LANG" == en ]]; then log_line "ACTION" "remove unused Flatpak dependencies"; else log_line "ACCION" "eliminar dependencias Flatpak sin usar"; fi
                flatpak_out=$(LC_ALL=C flatpak uninstall --unused --noninteractive --assumeyes 2>&1)
                flatpak_rc=$?
                echo "$flatpak_out" >> "$LOG_FILE"
                if echo "$flatpak_out" | grep -qi "Nothing unused to uninstall"; then
                    msg_ok "No había runtimes de Flatpak sin usar que eliminar."
                elif [[ $flatpak_rc -eq 0 ]]; then
                    found_issue=1
                    register_issue
                    ISSUES_FIXED=$((ISSUES_FIXED + 1))
                    msg_ok "Hecho: eliminar dependencias Flatpak sin usar."
                else
                    found_issue=1
                    register_issue
                    msg_err "Falló: eliminar dependencias Flatpak sin usar (revisa el log para más detalle)."
                fi
            fi
        fi
    fi

    # 4.7 Flatpak instalado pero sin el remoto Flathub configurado
    # Se han visto varios casos en el foro oficial de Mint de gente a la que
    # le falta o desaparece el remoto "flathub" (p. ej. al instalar flatpak a
    # mano con "apt install flatpak" en vez de por el Gestor de Aplicaciones,
    # o tras borrarlo por error). Sin él, el Gestor de Aplicaciones deja de
    # ofrecer la pestaña "Flatpak" para cualquier programa y "flatpak
    # install"/"flatpak search" no encuentran nada.
    if need_cmd flatpak; then
        local flatpak_remotes
        flatpak_remotes=$(flatpak remotes --columns=name 2>/dev/null)
        if ! echo "$flatpak_remotes" | grep -qix "flathub"; then
            found_issue=1
            register_issue
            msg_warn "Flatpak está instalado pero no tiene configurado el remoto \"flathub\": el Gestor de"
            msg_warn "Aplicaciones no ofrecerá la opción Flatpak para ningún programa."
            if ask_yes_no "¿Añadir el remoto Flathub (https://flathub.org)?"; then
                run_step_sudo "añadir el remoto Flathub de Flatpak" "añadir remoto Flathub" \
                    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
            else
                register_skip
            fi
        else
            msg_ok "El remoto Flathub está configurado en Flatpak."
        fi
    fi

    # 4.8 Partición /boot casi llena
    # Cuando /boot vive en una partición separada (habitual con cifrado de
    # disco o particionados manuales) suele ser pequeña y cada kernel nuevo
    # ocupa varias decenas de MB. Si se llena, la instalación del siguiente
    # kernel falla a mitad de la actualización y puede dejar el sistema sin
    # arrancar. Si /boot no es un punto de montaje propio (el caso más
    # común), esta comprobación se omite: ya queda cubierta por el espacio
    # de "/".
    if mountpoint -q /boot 2>/dev/null; then
        local boot_pct
        boot_pct=$(df /boot 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')
        if [[ -z "$boot_pct" ]]; then
            msg_warn "No se ha podido determinar el uso de la partición /boot."
        elif [[ "$boot_pct" -ge 80 ]] 2>/dev/null; then
            found_issue=1
            register_issue
            msg_warn "La partición /boot está al ${boot_pct}% de su capacidad."
            msg_warn "Si se llena del todo, la próxima actualización del kernel puede fallar a medias."
            msg_info "Revisa arriba los kernels antiguos: eliminarlos con autoremove libera espacio también en /boot."
        else
            msg_ok "La partición /boot tiene espacio suficiente (${boot_pct}% usado)."
        fi
    fi

    [[ $found_issue -eq 0 ]] && msg_ok "El uso de disco está bajo control."
}

# ======================================================================
# MÓDULO 5: Arranque, GRUB y reloj del sistema
# ======================================================================
mod_boot() {
    section_header "Arranque, GRUB y reloj del sistema"
    local found_issue=0

    # 5.1 GRUB desactualizado (kernel nuevo sin entrada en el menú de arranque)
    if [[ -f /boot/grub/grub.cfg ]]; then
        local current_kernel current_kernel_re
        current_kernel=$(uname -r)
        current_kernel_re=$(re_escape "$current_kernel")
        if ! grep -q "$current_kernel_re" /boot/grub/grub.cfg 2>/dev/null; then
            found_issue=1
            register_issue
            msg_warn "El menú de arranque de GRUB no incluye el kernel actualmente en uso ($current_kernel)."
            echo -e "  ${C_DIM}$(t 'Suele pasar tras instalar un kernel nuevo sin regenerar GRUB después.')${C_RESET}"
            if ask_yes_no "¿Regenerar la configuración de arranque (update-grub)?"; then
                run_step_sudo "regenerar la configuración de arranque de GRUB" "regenerar GRUB" sudo update-grub
            else
                register_skip
            fi
        else
            msg_ok "GRUB incluye una entrada para el kernel actual."
        fi
    else
        msg_info "No se encontró /boot/grub/grub.cfg; se omite esta comprobación (¿gestor de arranque distinto?)."
    fi

    # 5.2 Reinicio pendiente
    # Algunos paquetes (sobre todo el kernel) dejan este archivo como aviso
    # de que el cambio no estará activo del todo hasta el próximo reinicio.
    if [[ -f /var/run/reboot-required ]]; then
        found_issue=1
        register_issue
        msg_warn "El sistema indica que hace falta reiniciar para aplicar cambios pendientes (p. ej. un kernel nuevo)."
        if [[ -f /var/run/reboot-required.pkgs ]]; then
            echo -e "  ${C_DIM}$(t 'Paquetes implicados:') $(tr '\n' ' ' < /var/run/reboot-required.pkgs)${C_RESET}"
        fi
        msg_info "Guarda tu trabajo y reinicia cuando puedas."
    else
        msg_ok "No hay ningún reinicio pendiente marcado por el sistema."
    fi

    # 5.3 Reloj desincronizado con Windows en equipos de arranque dual
    # Windows asume que el reloj de la placa (RTC) guarda la hora local;
    # Linux, por defecto, lo pone en UTC. Si conviven ambos sistemas sin
    # "hablar el mismo idioma", uno de los dos mostrará la hora equivocada
    # justo después de arrancar el otro. Se detecta Windows buscando su
    # gestor de arranque en la partición EFI, sin usar "os-prober" (que
    # además reescribe el menú de GRUB, algo que no queremos hacer aquí).
    if [[ -d /boot/efi/EFI/Microsoft ]] && need_cmd timedatectl; then
        local rtc_local
        rtc_local=$(timedatectl show --property=LocalRTC --value 2>/dev/null)
        if [[ "$rtc_local" == "no" ]]; then
            found_issue=1
            register_issue
            msg_warn "Se ha detectado Windows en este equipo (arranque dual) y el reloj de hardware (RTC) está en UTC."
            echo -e "  ${C_DIM}$(t 'Windows espera que el RTC esté en hora local, así que Linux o Windows mostrarán')${C_RESET}"
            echo -e "  ${C_DIM}$(t 'la hora equivocada justo después de arrancar el otro sistema.')${C_RESET}"
            if ask_yes_no "¿Configurar el RTC en hora local para que coincida con Windows?"; then
                run_step_sudo "cambiar el modo del reloj de hardware (RTC)" \
                    "usar hora local para el RTC" sudo timedatectl set-local-rtc 1 --adjust-system-clock
            else
                register_skip
            fi
        else
            msg_ok "El reloj de hardware (RTC) ya está en hora local, coherente con Windows."
        fi
    fi

    # 5.4 Volumen NTFS marcado como "dirty"
    # Es un problema conocido en la serie de kernels de Mint 22.x: una
    # partición Windows puede quedar marcada como "dirty" y el sistema se
    # niega a montarla en escritura. Se lee del journal (no de "dmesg"
    # directamente) porque el buffer de "dmesg" suele estar restringido a
    # root, mientras que journalctl sí es legible por el grupo "adm".
    if need_cmd journalctl; then
        local ntfs_dirty
        ntfs_dirty=$(journalctl -k -b 0 --no-pager 2>/dev/null | grep -i "ntfs" | grep -iE "dirty|force. flag" | tail -3)
        if [[ -n "$ntfs_dirty" ]]; then
            found_issue=1
            register_issue
            msg_warn "El kernel ha registrado avisos de un volumen NTFS marcado como \"dirty\" (posiblemente tu partición de Windows)."
            msg_info "Solución: abre 'Discos' desde el menú, selecciona ese volumen y usa ⚙ > 'Reparar sistema de archivos'."
            msg_info "Mint-Doctor no toca particiones NTFS automáticamente para no arriesgar tus datos."
        else
            msg_ok "No hay avisos recientes de volúmenes NTFS dañados."
        fi
    fi

    # 5.5 Sincronización horaria (NTP)
    # Un reloj desincronizado provoca errores de certificado TLS/HTTPS que
    # parecen "de red" pero no lo son (p. ej. "apt-get update" fallando con
    # "certificate has expired" aunque el certificado sea válido). timedatectl
    # lee este estado sin necesitar privilegios de administrador.
    if need_cmd timedatectl; then
        local ntp_enabled ntp_synced
        ntp_enabled=$(timedatectl show --property=NTP --value 2>/dev/null)
        ntp_synced=$(timedatectl show --property=NTPSynchronized --value 2>/dev/null)
        if [[ "$ntp_enabled" == "no" ]]; then
            found_issue=1
            register_issue
            msg_warn "La sincronización horaria automática (NTP) está desactivada."
            if ask_yes_no "¿Activar la sincronización horaria automática?"; then
                run_step_sudo "activar la sincronización horaria (NTP)" "activar NTP" sudo timedatectl set-ntp true
            else
                register_skip
            fi
        elif [[ "$ntp_synced" == "no" ]]; then
            found_issue=1
            register_issue
            msg_warn "NTP está activado pero el reloj todavía no se ha sincronizado."
            msg_info "Suele resolverse solo en cuanto haya conexión a Internet; si persiste, revisa el módulo de red."
        else
            msg_ok "El reloj del sistema está sincronizado por NTP."
        fi
    fi

    # 5.6 Servicios systemd en estado de fallo
    # Un servicio "failed" (p. ej. tras un arranque interrumpido o un
    # paquete mal configurado) no siempre es visible a simple vista.
    # "systemctl --failed" es de solo lectura y no requiere sudo.
    if need_cmd systemctl; then
        local failed_units failed_count
        failed_units=$(systemctl --failed --no-legend --plain 2>/dev/null)
        failed_count=$(echo "$failed_units" | grep -c . || true)
        if [[ "$failed_count" -gt 0 ]] 2>/dev/null; then
            found_issue=1
            register_issue
            msg_warn "Hay $failed_count servicio(s) systemd en estado \"failed\":"
            echo "$failed_units" | awk '{print "      "$1}'
            msg_info "Para investigar uno en concreto: systemctl status <servicio> y journalctl -xeu <servicio>"
        else
            msg_ok "No hay servicios systemd en estado de fallo."
        fi
    fi

    # 5.7 Apagados forzados por el tiempo de espera de 10s de Mint
    # Mint reduce DefaultTimeoutStopSec a 10s (frente a los 90s por defecto de
    # systemd) desde hace varias versiones, ajustable en
    # /etc/systemd/system.conf.d/. Si algún servicio o sesión tarda más que
    # eso en cerrarse, systemd lo mata a la fuerza (SIGKILL) en vez de
    # esperar, lo que puede perder cambios sin guardar. Se busca en el
    # journal del arranque ANTERIOR (el que terminó con ese apagado) el
    # aviso característico de systemd al forzar el cierre de una unidad. Si
    # no hay un arranque anterior registrado (equipo recién instalado o
    # journal no persistente), se omite la comprobación en vez de asumir que
    # no hubo problemas: lo uno no implica lo otro.
    if need_cmd journalctl; then
        if journalctl -b -1 -n 1 &>/dev/null; then
            local shutdown_kills
            shutdown_kills=$(journalctl -b -1 --no-pager 2>/dev/null \
                              | grep -E "Stopping timed out\. Killing\.|Failed with result 'timeout'" | tail -5)
            if [[ -n "$shutdown_kills" ]]; then
                found_issue=1
                register_issue
                msg_warn "El apagado anterior tuvo que forzar el cierre de algún servicio por tardar demasiado:"
                indent_block "$shutdown_kills"
                msg_info "Mint reduce el tiempo de espera al apagar a solo 10s (frente a los 90s por defecto de"
                msg_info "systemd). Si esto te hace perder datos con frecuencia, puedes ampliarlo creando"
                msg_info "/etc/systemd/system.conf.d/60_custom.conf con un DefaultTimeoutStopSec mayor (revisa"
                msg_info "/etc/systemd/system.conf.d/50_linuxmint.conf para ver cómo está definido ahora)."
            else
                msg_ok "No hay avisos de apagados forzados por tiempo de espera en el arranque anterior."
            fi
        else
            msg_info "No hay registro de un arranque anterior (¿recién instalado?); se omite esta comprobación."
        fi
    fi

    [[ $found_issue -eq 0 ]] && msg_ok "El arranque y el reloj del sistema están en orden."
}

# ======================================================================
# MÓDULO 6: Conectividad de red
# ======================================================================
mod_network() {
    section_header "Conectividad de red"
    local found_issue=0

    # 6.1 Wifi/Bluetooth bloqueados por software (rfkill)
    # Es muy habitual que quede bloqueado tras salir de suspensión o al
    # tocar por error la tecla de "modo avión".
    if need_cmd rfkill; then
        local soft_blocked hard_blocked
        # Ojo con el número de líneas de contexto: "Hard blocked" va después de
        # "Soft blocked", así que la línea con el índice del dispositivo queda
        # 2 líneas por encima, no 1 (a diferencia de "Soft blocked").
        soft_blocked=$(rfkill list 2>/dev/null | grep -B1 "Soft blocked: yes" | grep -oP '^\d+: \K.*')
        hard_blocked=$(rfkill list 2>/dev/null | grep -B2 "Hard blocked: yes" | grep -oP '^\d+: \K.*')
        if [[ -n "$soft_blocked" ]]; then
            found_issue=1
            register_issue
            msg_warn "Hay radios bloqueadas por software:"
            indent_block "$soft_blocked"
            if ask_yes_no "¿Desbloquear todas las radios (WiFi/Bluetooth)?"; then
                run_step "desbloquear radios con rfkill" rfkill unblock all
            else
                register_skip
            fi
        else
            msg_ok "No hay ninguna radio (WiFi/Bluetooth) bloqueada por software."
        fi
        if [[ -n "$hard_blocked" ]]; then
            msg_info "Además, hay radios bloqueadas por hardware (interruptor físico o tecla Fn):"
            indent_block "$hard_blocked"
            msg_info "Eso no se puede desbloquear por software; revisa el interruptor o combinación Fn de tu equipo."
        fi
    fi

    # 6.2 Conectividad IP y resolución DNS
    # Se comprueban por separado para distinguir "no hay red" de "hay red
    # pero falla el DNS", que son problemas distintos con arreglos distintos.
    local ip_ok=0 dns_ok=0
    if need_cmd ping && ping -c1 -W2 1.1.1.1 &>/dev/null; then
        ip_ok=1
    fi
    if need_cmd getent && getent hosts linuxmint.com &>/dev/null; then
        dns_ok=1
    fi

    if [[ $dns_ok -eq 1 ]]; then
        # Una resolución DNS que funciona ya demuestra que hay red, aunque el
        # ping haya fallado (p. ej. ICMP bloqueado por el router/ISP o por un
        # portal de WiFi público): no tiene sentido decir "sin conexión"
        # contradiciendo esta misma señal.
        if [[ $ip_ok -eq 1 ]]; then
            msg_ok "Hay conexión a Internet y la resolución de nombres (DNS) funciona."
        else
            msg_ok "Hay conexión a Internet (la resolución DNS funciona), aunque no responde al ping."
            msg_info "Puede que ICMP esté bloqueado en tu red; no indica ningún problema por sí solo."
        fi
    elif [[ $ip_ok -eq 1 ]]; then
        found_issue=1
        register_issue
        msg_warn "Hay conexión a Internet, pero la resolución de nombres (DNS) está fallando."
        msg_info "Puede deberse a un servidor DNS caído o mal configurado en tu red o router."
        if ask_yes_no "¿Reiniciar NetworkManager (a veces resuelve bloqueos temporales de DNS)?"; then
            run_step_sudo "reiniciar el servicio de red" "reiniciar NetworkManager" sudo systemctl restart NetworkManager
        else
            register_skip
        fi
    else
        found_issue=1
        register_issue
        msg_warn "No se ha detectado conexión a Internet en este momento."
        msg_info "Comprueba el cable/WiFi, o si el icono de red del panel muestra algún error."
    fi

    [[ $found_issue -eq 0 ]] && msg_ok "La conectividad de red no muestra problemas."
}

# ======================================================================
# MÓDULO 7: Salud del hardware (disco, batería, DKMS, Secure Boot, sonido)
# ======================================================================
mod_hardware() {
    section_header "Salud del hardware (disco, batería y controladores DKMS)"
    local found_issue=0

    # 7.1 Estado S.M.A.R.T. de los discos
    if need_cmd smartctl; then
        local disk disks any_bad=0
        disks=$(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print $1}')
        if [[ -n "$disks" ]]; then
            # Si no se consiguen permisos de administrador, mejor decirlo
            # claramente aquí que dejar que cada "sudo smartctl" falle en
            # silencio: antes eso se confundía con el aviso normal de "no se
            # ha podido determinar el estado" (pensado para VMs/USB), dando
            # un diagnóstico engañoso cuando el motivo real era otro.
            if ensure_sudo "consultar el estado S.M.A.R.T. de los discos"; then
                for disk in $disks; do
                    [[ "$disk" == zram* || "$disk" == loop* ]] && continue
                    local health
                    health=$(sudo smartctl -H "/dev/$disk" 2>/dev/null | grep -i "overall-health\|SMART Health Status")
                    if echo "$health" | grep -qiE "PASSED|OK"; then
                        msg_ok "/dev/$disk: S.M.A.R.T. correcto."
                    elif [[ -n "$health" ]]; then
                        any_bad=1
                        msg_err "/dev/$disk: S.M.A.R.T. informa un problema → ${health##*: }"
                    else
                        # smartctl no siempre puede determinar la salud (habitual
                        # en discos virtuales de VMs y en algunos USB/NVMe). No es
                        # lo mismo que "correcto": hay que decirlo, no callarlo.
                        msg_warn "/dev/$disk: no se ha podido determinar el estado S.M.A.R.T. (habitual en máquinas virtuales o algunos discos USB/NVMe)."
                    fi
                done
            else
                msg_warn "No se ha podido comprobar el estado S.M.A.R.T. de los discos (sin permisos de administrador)."
            fi
            if [[ $any_bad -eq 1 ]]; then
                found_issue=1
                register_issue
                msg_warn "Al menos un disco reporta un estado S.M.A.R.T. anómalo; hay riesgo de pérdida de datos."
                msg_info "Haz una copia de seguridad cuanto antes y considera sustituir el disco."
            fi
        fi
    else
        found_issue=1
        register_issue
        msg_info "smartmontools no está instalado; no se puede comprobar la salud S.M.A.R.T. de los discos."
        if ask_yes_no "¿Instalar smartmontools para poder revisar la salud de los discos?"; then
            run_step_sudo "instalar smartmontools" "instalar smartmontools" sudo apt-get -y install smartmontools
        else
            register_skip
        fi
    fi

    # 7.2 Batería (solo portátiles) y gestión de energía con TLP
    if compgen -G "/sys/class/power_supply/BAT*" > /dev/null 2>&1; then
        local bat_path bat
        bat_path=$(compgen -G "/sys/class/power_supply/BAT*" | head -1)
        bat=$(basename "$bat_path")
        if need_cmd upower; then
            local cap cap_int
            cap=$(upower -i "/org/freedesktop/UPower/devices/battery_${bat}" 2>/dev/null \
                  | awk -F: '/capacity/{gsub(/[ %]/,"",$2); print $2}')
            cap_int="${cap%%.*}"
            if [[ -n "$cap_int" ]]; then
                msg_info "Salud de la batería ($bat): ${cap}% de su capacidad de fábrica."
                if [[ "$cap_int" =~ ^[0-9]+$ ]] && (( cap_int < 60 )); then
                    found_issue=1
                    register_issue
                    msg_warn "La batería ha perdido buena parte de su capacidad original; puede que dure poco o convenga sustituirla."
                fi
            fi
        fi
        if ! need_cmd tlp; then
            found_issue=1
            register_issue
            msg_warn "Este equipo parece un portátil (tiene batería) pero no tiene TLP instalado, que ayuda a alargar la autonomía."
            if ask_yes_no "¿Instalar y activar TLP para mejorar la gestión de energía?"; then
                if [[ $DRY_RUN -eq 1 ]] || ensure_sudo "instalar y activar TLP"; then
                    # Dos pasos para un único problema ("falta TLP"): se resta la
                    # cuenta del primero en cuanto tiene éxito, así que solo el
                    # segundo (activar el servicio, el que de verdad resuelve el
                    # problema) deja el contador en +1. Si activar fallara tras
                    # instalar bien, ya no se contaría como "arreglado" sin más.
                    if run_step "instalar TLP" sudo apt-get -y install tlp tlp-rdw; then
                        [[ $DRY_RUN -eq 1 ]] || ISSUES_FIXED=$((ISSUES_FIXED - 1))
                        run_step "activar el servicio TLP" sudo systemctl enable --now tlp
                    fi
                else
                    msg_warn "No se ha podido instalar TLP (sin permisos de administrador)."
                fi
            else
                register_skip
            fi
        else
            msg_ok "TLP ya está instalado para gestionar el consumo de energía."
        fi
    fi

    # 7.3 Módulos DKMS sin reconstruir (NVIDIA, Broadcom Wi-Fi, VirtualBox...)
    # Cada vez que se instala un kernel nuevo, DKMS debe recompilar estos
    # módulos de terceros para esa versión concreta. Si falla (típicamente
    # por faltar los linux-headers del kernel nuevo), el driver no carga: la
    # señal más habitual es arrancar en baja resolución o sin aceleración
    # gráfica justo después de una actualización. "dkms status" es de solo
    # lectura y no requiere sudo.
    if need_cmd dkms; then
        local current_kernel current_kernel_re dkms_out
        current_kernel=$(uname -r)
        current_kernel_re=$(re_escape "$current_kernel")
        dkms_out=$(dkms status 2>/dev/null)
        if [[ -n "$dkms_out" ]]; then
            local mods m m_re missing=()
            # Nombre de cada módulo (lo que precede a la primera "/" o ","),
            # sin duplicados, sin importar para qué kernel(es) esté registrado.
            mods=$(echo "$dkms_out" | awk -F'[,/]' '{print $1}' | sort -u)
            for m in $mods; do
                m_re=$(re_escape "$m")
                if ! echo "$dkms_out" | grep -q "^${m_re}/.*, ${current_kernel_re}, .*: installed"; then
                    missing+=("$m")
                fi
            done
            if [[ ${#missing[@]} -gt 0 ]]; then
                found_issue=1
                register_issue
                msg_warn "Estos módulos DKMS no están instalados para el kernel en uso ($current_kernel):"
                printf '      %s\n' "${missing[@]}"
                msg_info "Suele arreglarse instalando las cabeceras del kernel actual y reconstruyendo los módulos."
                # Aviso específico de Mint 22.3: sus notas de versión documentan
                # problemas del kernel HWE 6.14 con los módulos de VirtualBox.
                # Reinstalar cabeceras y reconstruir (más abajo) resuelve la
                # mayoría de los casos, pero si el problema es justo ese, puede
                # no bastar y conviene saberlo de antemano.
                local m2
                for m2 in "${missing[@]}"; do
                    if [[ "$m2" == *vbox* || "$m2" == *virtualbox* ]]; then
                        msg_info "Nota: las notas de versión de Mint 22.3 avisan de problemas conocidos entre"
                        msg_info "VirtualBox y el kernel HWE 6.14. Si tras reconstruir los módulos sigue sin"
                        msg_info "funcionar, prueba arrancando un kernel anterior desde \"Opciones avanzadas\""
                        msg_info "en el menú de arranque, o instala linux-headers de un kernel LTS más antiguo."
                        break
                    fi
                done
                if ask_yes_no "¿Instalar linux-headers-${current_kernel} y reconstruir los módulos DKMS ahora?"; then
                    if [[ $DRY_RUN -eq 1 ]] || ensure_sudo "instalar cabeceras del kernel y reconstruir módulos DKMS"; then
                        # Igual que en TLP (7.2): se resta la cuenta de las
                        # cabeceras en cuanto se instalan bien, para que solo la
                        # reconstrucción de módulos (el paso que de verdad
                        # resuelve el problema) deje el contador en +1.
                        if run_step "instalar linux-headers-${current_kernel}" sudo apt-get -y install "linux-headers-${current_kernel}"; then
                            [[ $DRY_RUN -eq 1 ]] || ISSUES_FIXED=$((ISSUES_FIXED - 1))
                            run_step "reconstruir módulos DKMS (dkms autoinstall)" sudo dkms autoinstall
                        fi
                    else
                        msg_warn "No se han podido instalar las cabeceras ni reconstruir los módulos DKMS (sin permisos de administrador)."
                    fi
                else
                    register_skip
                fi
            else
                msg_ok "Todos los módulos DKMS están instalados para el kernel en uso."
            fi
        fi
    else
        msg_info "DKMS no está instalado (normal si no usas drivers propietarios como NVIDIA)."
    fi

    # 7.4 Driver NVIDIA 470 incompatible con el kernel HWE 6.14+
    # Problema documentado en las notas de la versión de Mint 22.3: las
    # tarjetas NVIDIA antiguas que dependen de la rama de drivers 470 (la
    # última que las admite; NVIDIA ya no la mantiene) dejaron de funcionar
    # con el kernel HWE 6.14 que Mint 22.2/22.3 instalan por defecto en
    # equipos nuevos. No hay un paquete que lo arregle automáticamente (esas
    # tarjetas no tienen un driver más moderno que las soporte), así que
    # aquí solo se detecta y se explica la solución oficial: usar un kernel
    # anterior o quedarse en Linux Mint 22.1 (kernel LTS 6.8).
    if dpkg -l 'nvidia-driver-470*' 2>/dev/null | grep -q '^ii'; then
        local nv_kernel nv_maj nv_min
        nv_kernel=$(uname -r)
        nv_maj=$(grep -oP '^\d+' <<< "$nv_kernel")
        nv_min=$(grep -oP '^\d+\.\K\d+' <<< "$nv_kernel")
        if [[ -n "$nv_maj" && -n "$nv_min" ]] && { (( nv_maj > 6 )) || { (( nv_maj == 6 )) && (( nv_min >= 14 )); }; }; then
            found_issue=1
            register_issue
            msg_err "Tienes instalado el driver nvidia-driver-470 (para tarjetas NVIDIA antiguas) junto al kernel"
            msg_err "$nv_kernel, de la serie 6.14 o superior, que ya no admite ese driver."
            msg_info "Es un problema conocido de Mint 22.3: NVIDIA dejó de mantener el driver 470 para kernels"
            msg_info "nuevos. Si la pantalla se ve sin aceleración 3D o en baja resolución, arranca un kernel"
            msg_info "anterior desde \"Opciones avanzadas\" en el menú de arranque, o valora instalar Linux"
            msg_info "Mint 22.1, que usa el kernel LTS 6.8 (compatible con el driver 470)."
        else
            msg_ok "El driver nvidia-driver-470 es compatible con el kernel en uso ($nv_kernel)."
        fi
    fi

    # 7.5 Servidor de sonido (PipeWire o PulseAudio)
    # Desde Mint 22.x el servidor de sonido por defecto es PipeWire, pero las
    # propias notas de la versión documentan volver a PulseAudio como
    # solución válida ante ciertos problemas de audio (p. ej. cortes por
    # HDMI), así que aquí no se exige PipeWire en concreto: solo se
    # comprueba que responda ALGÚN servidor de sonido. "pactl info" activa
    # el servicio bajo demanda si usa activación por socket, así que no da
    # falsos negativos con PipeWire simplemente inactivo "en reposo". Solo
    # se comprueba si hay una sesión gráfica real (DISPLAY/WAYLAND_DISPLAY):
    # es un servicio de la sesión de usuario, no del sistema, y consultarlo
    # sin sesión (p. ej. --auto vía cron) daría un falso aviso.
    if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && need_cmd pactl; then
        if pactl info &>/dev/null; then
            msg_ok "El servidor de sonido (PipeWire/PulseAudio) responde correctamente."
            # Aviso específico de Mint 22.x: sus notas de versión documentan
            # cortes de audio conocidos ("choppy sound") con PipeWire concretamente
            # en salidas HDMI (hay un informe de fallo de Debian enlazado en las
            # propias notas). Solo se avisa si de verdad aplica: servidor PipeWire
            # Y salida activa por HDMI. Es puramente informativo: cambiar el
            # servidor de sonido del sistema es una decisión del usuario, no algo
            # que este script deba tocar por su cuenta.
            local sound_server_name default_sink
            sound_server_name=$(pactl info 2>/dev/null | grep -i "Server Name")
            default_sink=$(pactl get-default-sink 2>/dev/null)
            if echo "$sound_server_name" | grep -qi "pipewire" && echo "$default_sink" | grep -qi "hdmi"; then
                msg_info "Usas PipeWire con salida por HDMI. Mint 22.x documenta cortes de audio conocidos en"
                msg_info "esta combinación. Si notas cortes, puedes volver a PulseAudio con:"
                msg_info "  sudo apt purge pipewire pipewire-bin && systemctl enable --user pulseaudio && reinicia"
            fi
        else
            found_issue=1
            register_issue
            msg_warn "No se ha podido contactar con ningún servidor de sonido (PipeWire/PulseAudio)."
            msg_info "Si no tienes audio en ningún dispositivo, cierra sesión y vuelve a entrar; si persiste,"
            msg_info "prueba: systemctl --user restart pipewire pipewire-pulse wireplumber"
        fi
    fi

    # 7.6 Secure Boot activado + módulo(s) de kernel rechazados por falta de
    # firma MOK (típico con DKMS: NVIDIA propietario, VirtualBox, Broadcom
    # Wi-Fi...). Es una causa de confusión muy habitual: el Gestor de
    # controladores puede decir "instalado", e incluso "dkms status" puede
    # decir "installed", pero el módulo nunca llega a cargarse porque, con
    # Secure Boot activo, el kernel rechaza cualquier módulo que no esté
    # firmado con una clave inscrita (MOK). El propio equipo de Mint tiene
    # abierta una mejora equivalente para "mintupgrade" (issue #125 en
    # linuxmint/mintupgrade) por este mismo motivo. Se exige evidencia real
    # en el log del kernel de ESTE arranque (no solo la precondición "Secure
    # Boot activo + hay DKMS"), para no avisar de un problema que en
    # realidad no se esté dando.
    #
    # No se ofrece un arreglo automático: inscribir una clave MOK exige
    # elegir una contraseña nueva y confirmarla tras reiniciar en una
    # pantalla de firmware (el "MOK Manager" azul), un paso deliberadamente
    # interactivo que no se puede ni se debe automatizar desde un script.
    if need_cmd mokutil && need_cmd journalctl; then
        local sb_state rejected_mods
        sb_state=$(mokutil --sb-state 2>/dev/null)
        if echo "$sb_state" | grep -qi "SecureBoot enabled"; then
            rejected_mods=$(journalctl -k -b 0 --no-pager 2>/dev/null \
                             | grep -iE "Key was rejected by service|Loading of unsigned module is rejected|Loading of module with unavailable key is rejected" \
                             | tail -5)
            if [[ -n "$rejected_mods" ]]; then
                found_issue=1
                register_issue
                msg_err "Secure Boot está activado y el kernel ha rechazado cargar algún módulo por falta de firma:"
                indent_block "$rejected_mods"
                msg_info "Suele pasar con módulos DKMS (NVIDIA propietario, VirtualBox, Broadcom Wi-Fi...) recién"
                msg_info "compilados: el Gestor de controladores puede decir \"instalado\" aunque el módulo nunca cargue."
                msg_info "Arreglo (exige elegir una contraseña y confirmarla tras reiniciar, no se puede automatizar):"
                msg_info "  sudo dpkg-reconfigure <paquete-dkms-afectado>   (p. ej. nvidia-dkms-XXX o virtualbox-dkms)"
                msg_info "Eso vuelve a lanzar el asistente que genera e inscribe la clave MOK (\"Enroll MOK\") en el"
                msg_info "próximo arranque. Alternativa: desactivar Secure Boot en la BIOS/UEFI si no lo necesitas."
            else
                msg_ok "Secure Boot está activado, pero no hay evidencia de módulos rechazados por firma en este arranque."
            fi
        fi
    fi

    # 7.7 Máquina virtual VirtualBox sin las Guest Additions cargadas
    # Las notas de la versión de Mint 22.3 dedican un apartado entero a cómo
    # probarla dentro de VirtualBox; sin las Guest Additions (módulo de
    # kernel "vboxguest"), el redimensionado automático de pantalla, el
    # portapapeles compartido y la aceleración gráfica no funcionan bien. Se
    # detecta primero que el propio sistema es una VM de VirtualBox (con
    # "systemd-detect-virt", sin necesitar sudo) para no avisar de esto en
    # hardware real, donde el módulo "vboxguest" no pintaría nada. Desde
    # Ubuntu 24.04/Mint 22.x el módulo ya no depende de un paquete -dkms
    # aparte: se instala junto con linux-modules-extra del kernel en uso.
    if need_cmd systemd-detect-virt; then
        local virt_type
        virt_type=$(systemd-detect-virt 2>/dev/null)
        if [[ "$virt_type" == "oracle" ]]; then
            if lsmod 2>/dev/null | grep -q '^vboxguest'; then
                msg_ok "Estás en una VM de VirtualBox y las Guest Additions (vboxguest) están cargadas."
            else
                found_issue=1
                register_issue
                msg_warn "Estás en una máquina virtual de VirtualBox, pero el módulo \"vboxguest\" de las Guest"
                msg_warn "Additions no está cargado: el redimensionado automático de pantalla, el portapapeles"
                msg_warn "compartido con el equipo anfitrión y la aceleración gráfica no funcionarán bien sin él."
                if ask_yes_no "¿Instalar las Guest Additions de VirtualBox desde los repositorios de Mint?"; then
                    if [[ $DRY_RUN -eq 1 ]] || ensure_sudo "instalar las Guest Additions de VirtualBox"; then
                        if run_step "instalar Guest Additions de VirtualBox" \
                            sudo apt-get -y install virtualbox-guest-utils virtualbox-guest-x11 "linux-modules-extra-$(uname -r)"; then
                            msg_info "Si el módulo sigue sin cargar tras instalar, reinicia la máquina virtual."
                        fi
                    else
                        msg_warn "No se han podido instalar las Guest Additions (sin permisos de administrador)."
                    fi
                else
                    register_skip
                fi
            fi
        fi
    fi

    [[ $found_issue -eq 0 ]] && msg_ok "Disco, batería y controladores DKMS están en buen estado."
}

# ======================================================================
# MÓDULO 8: Escritorio Cinnamon
# ======================================================================
mod_cinnamon() {
    section_header "Escritorio Cinnamon"
    local found_issue=0

    # 8.1 Bloqueos recientes de Cinnamon (segfaults, applets caídos)
    if need_cmd journalctl; then
        local crash_lines
        crash_lines=$(journalctl -b 0 --no-pager 2>/dev/null \
                      | grep -iE "cinnamon.*(segfault|core dumped|killed by signal)" | tail -5)
        if [[ -n "$crash_lines" ]]; then
            found_issue=1
            register_issue
            msg_warn "Se han encontrado bloqueos de Cinnamon durante esta sesión:"
            indent_block "$crash_lines"
            msg_info "Si ves paneles o applets desaparecidos, prueba a cerrar sesión y volver a entrar,"
            msg_info "o pulsa Alt+F2 y escribe 'r' para reiniciar Cinnamon sin cerrar tus programas."
        else
            msg_ok "No se han detectado bloqueos de Cinnamon en esta sesión."
        fi
    fi

    # 8.2 Accesos directos de escritorio marcados como "no confiables"
    # Nemo (el gestor de archivos de Mint) exige marcar cada .desktop del
    # escritorio como confiable antes de poder lanzarlo con un doble clic;
    # si no, se ve como un icono genérico con el aviso "archivo de inicio
    # no confiable". Se arregla dándole permiso de ejecución y marcándolo
    # con el mismo atributo que usa Nemo/GIO al pulsar "Permitir lanzamiento".
    # "xdg-user-dir DESKTOP" (paquete xdg-user-dirs, presente de fábrica en
    # Cinnamon) es la fuente correcta: respeta tanto el idioma del sistema
    # como una carpeta renombrada a mano. Los nombres fijos "Desktop"/
    # "Escritorio" quedan como reserva por si el comando falta o no devuelve
    # una ruta existente.
    local desktop_dir=""
    if need_cmd xdg-user-dir; then
        desktop_dir=$(xdg-user-dir DESKTOP 2>/dev/null)
        [[ -d "$desktop_dir" ]] || desktop_dir=""
    fi
    if [[ -z "$desktop_dir" ]]; then
        desktop_dir="$HOME/Desktop"
        [[ -d "$desktop_dir" ]] || desktop_dir="$HOME/Escritorio"
    fi
    if [[ -d "$desktop_dir" ]]; then
        local untrusted=() f
        while IFS= read -r -d '' f; do
            [[ -x "$f" ]] || untrusted+=("$f")
        done < <(find "$desktop_dir" -maxdepth 1 -name '*.desktop' -print0 2>/dev/null)
        if [[ ${#untrusted[@]} -gt 0 ]]; then
            found_issue=1
            register_issue
            msg_warn "Hay ${#untrusted[@]} acceso(s) directo(s) en el escritorio sin marcar como confiables:"
            printf '      %s\n' "${untrusted[@]##*/}"
            if ask_yes_no "¿Marcarlos como confiables para que funcionen con un doble clic?"; then
                if [[ $DRY_RUN -eq 1 ]]; then
                    local names_str
                    names_str=$(printf '%s ' "${untrusted[@]##*/}")
                    echo -e "  ${C_YELLOW}[$(t 'SIMULACIÓN')]${C_RESET} $(t 'Se marcarían como confiables:') ${C_DIM}${names_str}${C_RESET}"
                else
                    local file ok_count=0
                    for file in "${untrusted[@]}"; do
                        if chmod +x "$file" 2>>"$LOG_FILE"; then
                            need_cmd gio && gio set "$file" "metadata::trusted" true 2>>"$LOG_FILE"
                            ok_count=$((ok_count + 1))
                        fi
                    done
                    if [[ $ok_count -gt 0 ]]; then
                        msg_ok "Marcados como confiables: $ok_count acceso(s) directo(s)."
                        ISSUES_FIXED=$((ISSUES_FIXED + 1))
                        if [[ "$MINT_DOCTOR_LANG" == en ]]; then log_line "ACTION" "mark $ok_count desktop shortcuts as trusted in $desktop_dir"; else log_line "ACCION" "marcar como confiables $ok_count accesos directos en $desktop_dir"; fi
                    else
                        msg_err "No se pudo marcar ningún acceso directo (revisa permisos)."
                    fi
                fi
            else
                register_skip
            fi
        else
            msg_ok "Los accesos directos del escritorio están marcados como confiables."
        fi
    fi

    # 8.3 Aceleración 3D + gstreamer1.0-vaapi: aviso de VirtualBox, no un
    # problema general de cualquier instalación
    # Las notas de la versión de Mint documentan esto para quien PRUEBA Mint
    # como invitado en VirtualBox: con gstreamer1.0-vaapi instalado (lo trae
    # mint-meta-codecs), reproducir vídeo sin aceleración 3D en la VM cierra
    # la sesión X por completo, pero activarla puede dar problemas de
    # renderizado en apps WebKit/GTK4; ahí Mint recomienda quitar
    # gstreamer1.0-vaapi como salida más simple a ese dilema. En hardware
    # real esta combinación no está documentada, así que solo se ofrece
    # quitarlo dentro de una VM de VirtualBox, donde sí aplica tal cual;
    # fuera de una VM solo se informa, sin sugerir perder la aceleración de
    # vídeo real por un problema que no le corresponde. Igual que con
    # Flatpak (4.6), no cuenta como "problema detectado" salvo que el
    # usuario decida actuar.
    if dpkg -l gstreamer1.0-vaapi 2>/dev/null | grep -q '^ii'; then
        local virt_type_vaapi=""
        need_cmd systemd-detect-virt && virt_type_vaapi=$(systemd-detect-virt 2>/dev/null)
        if [[ "$virt_type_vaapi" == "oracle" ]]; then
            msg_info "Tienes instalado gstreamer1.0-vaapi (aceleración 3D por hardware para vídeo) dentro de"
            msg_info "una VM de VirtualBox. Las notas de Mint documentan justo este caso: la aceleración 3D"
            msg_info "puede dar problemas de renderizado en apps WebKit/GTK4; quitar este paquete es su salida"
            msg_info "más simple."
            if [[ $AUTO_MODE -ne 1 ]] && ask_yes_no "¿Solo si notas ese problema de renderizado, quitar gstreamer1.0-vaapi ahora?"; then
                found_issue=1
                register_issue
                run_step_sudo "quitar gstreamer1.0-vaapi" "quitar gstreamer1.0-vaapi" sudo apt-get -y remove gstreamer1.0-vaapi
            fi
        else
            msg_info "Tienes instalado gstreamer1.0-vaapi (aceleración 3D por hardware para vídeo). El aviso de"
            msg_info "Mint sobre renderizado WebKit/GTK4 con este paquete está documentado para cuando se"
            msg_info "prueba Mint como invitado en VirtualBox, no para hardware real."
        fi
    fi

    # 8.4 Códecs multimedia (mint-meta-codecs)
    # Por defecto, el instalador de Mint solo añade los códecs propietarios
    # (MP3, H.264, DVD...) si se marca la casilla correspondiente durante la
    # instalación del sistema; es fácil pasarla por alto, y tras eso muchos
    # vídeos/audios no se reproducen con un mensaje de error que no explica
    # la causa real. Se comprueba con dpkg (no con "apt list") porque es más
    # rápido y no depende de tener la caché de APT recién actualizada.
    # "mint-meta-codecs-core" es la variante sin XApps (Xplayer) que cubre lo
    # mismo a efectos de códecs, así que también cuenta como "ya resuelto".
    if ! dpkg -l mint-meta-codecs 2>/dev/null | grep -q '^ii' \
       && ! dpkg -l mint-meta-codecs-core 2>/dev/null | grep -q '^ii'; then
        found_issue=1
        register_issue
        msg_warn "No se han instalado los códecs multimedia de Mint (paquete mint-meta-codecs)."
        msg_warn "Sin ellos, es habitual que fallen la reproducción de MP3/AAC, vídeos H.264/H.265 o DVDs."
        if ask_yes_no "¿Instalar el paquete de códecs multimedia (mint-meta-codecs)?"; then
            run_step_sudo "instalar los códecs multimedia" "instalar mint-meta-codecs" sudo apt-get -y install mint-meta-codecs
        else
            register_skip
        fi
    else
        msg_ok "Los códecs multimedia de Mint ya están instalados."
    fi

    # 8.5 Sesión actual en modo de repliegue "Cinnamon (Software Rendering)"
    # Cinnamon cae en esta sesión sin aceleración 3D (binario cinnamon2d) tras
    # bloqueos repetidos del Cinnamon normal; casi siempre delata un problema
    # de driver gráfico. Solo se informa: el arreglo (revisar el driver) ya lo
    # cubre el módulo 7 (DKMS/Secure Boot/NVIDIA).
    if [[ "${DESKTOP_SESSION:-}${XDG_SESSION_DESKTOP:-}" == *cinnamon2d* ]] || pgrep -x cinnamon2d &>/dev/null; then
        found_issue=1
        register_issue
        msg_warn "Esta sesión se ha iniciado en modo \"Cinnamon (Software Rendering)\", sin aceleración 3D."
        msg_info "Suele activarse tras varios bloqueos seguidos del Cinnamon normal y señala un problema con"
        msg_info "el driver gráfico. Revisa el Gestor de controladores y la opción 7 de este script (DKMS)."
    fi

    # 8.6 Spices de terceros (applets/desklets/extensiones) sin soporte
    # declarado para la versión de Cinnamon en uso. Cada spice indica en su
    # metadata.json qué versiones admite ("cinnamon-version": [...]); tras el
    # salto 22.2→22.3 (Cinnamon 6.4→6.6) es habitual que las instaladas a mano
    # desde cinnamon-spices.linuxmint.com aún no lo incluyan y dejen de
    # cargarse sin aviso claro, algo reportado varias veces en el foro oficial
    # de Mint. Solo informa (requiere python3 para leer el JSON; no se toca
    # nada de terceros de forma automática).
    if need_cmd python3; then
        local cin_ver_mm spice_type spice_dir meta incompatible=()
        cin_ver_mm=$(grep -oP '\d+\.\d+' <<< "$(get_cinnamon_version)" | head -1)
        if [[ -n "$cin_ver_mm" ]]; then
            for spice_type in applets desklets extensions; do
                spice_dir="$HOME/.local/share/cinnamon/$spice_type"
                [[ -d "$spice_dir" ]] || continue
                while IFS= read -r -d '' meta; do
                    local name
                    name=$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
versions = data.get("cinnamon-version")
if isinstance(versions, list) and sys.argv[2] not in versions:
    print(data.get("name", sys.argv[1]))
' "$meta" "$cin_ver_mm" 2>/dev/null)
                    [[ -n "$name" ]] && incompatible+=("$name")
                done < <(find "$spice_dir" -mindepth 2 -maxdepth 2 -name 'metadata.json' -print0 2>/dev/null)
            done
            if [[ ${#incompatible[@]} -gt 0 ]]; then
                found_issue=1
                register_issue
                msg_warn "Estas 'spices' de terceros no declaran soporte para Cinnamon ${cin_ver_mm} (metadata.json):"
                printf '      %s\n' "${incompatible[@]}"
                msg_info "Es habitual justo después de actualizar a Cinnamon 6.6 (Mint 22.3). Busca una versión más"
                msg_info "reciente en Menú > Applets/Desklets/Extensiones > pestaña Descargar, o en"
                msg_info "cinnamon-spices.linuxmint.com; si no la hay, el autor aún no la ha actualizado."
            fi
        fi
    fi

    [[ $found_issue -eq 0 ]] && msg_ok "El escritorio Cinnamon no muestra problemas evidentes."
}

# ======================================================================
# MÓDULO 9: Copias de seguridad del sistema (Timeshift)
# ======================================================================
#
# Que el asistente se haya completado (backup_device_uuid no vacío en
# timeshift.json) no implica que existan instantáneas reales: pudo
# completarse sin llegar a crear ninguna, la unidad de destino pudo
# desconectarse después, o las programaciones automáticas pueden estar
# todas desactivadas. Por eso se consulta el estado real con "timeshift
# --list" (exige sudo; Timeshift siempre requiere permisos de root,
# incluso solo para listar) en vez de fiarse del .json.
#
# A diferencia del módulo 3 (que se salta entero en --dry-run porque
# "apt-get update" escribe la caché de listas en disco), aquí "timeshift
# --list" sí se ejecuta también en modo simulación: es una consulta de
# solo lectura del estado real (monta el destino para leerlo y lo
# desmonta, pero no persiste ningún cambio), así que omitirla en
# --dry-run solo serviría para dar un diagnóstico menos fiable sin
# ganar nada a cambio. Lo único que --dry-run desactiva de verdad aquí
# es la posible creación de la primera instantánea (vía run_step).
mod_backup() {
    section_header "Copias de seguridad del sistema (Timeshift)"
    local found_issue=0

    if ! need_cmd timeshift; then
        found_issue=1
        register_issue
        msg_warn "Timeshift no está instalado. Sin él, no hay forma de deshacer una actualización"
        msg_warn "problemática volviendo a un estado anterior del sistema."
        if ask_yes_no "¿Instalar Timeshift?"; then
            if [[ $DRY_RUN -eq 1 ]] || ensure_sudo "instalar Timeshift"; then
                # El mensaje de apertura solo tiene sentido si la instalación
                # salió bien; si run_step falla, ya muestra su propio error.
                if run_step "instalar Timeshift" sudo apt-get -y install timeshift; then
                    msg_info "Ábrelo desde el menú (Administración > Timeshift) para elegir dónde guardar las instantáneas."
                fi
            else
                msg_warn "No se ha podido instalar Timeshift (sin permisos de administrador)."
            fi
        else
            register_skip
        fi
        return
    fi

    # 9.1 ¿Se completó alguna vez el asistente de configuración?
    # /etc/timeshift/timeshift.json es -rw-r--r-- (legible por cualquier
    # usuario), así que esta primera comprobación no necesita sudo. Un
    # "backup_device_uuid" vacío significa que el asistente nunca se completó
    # y, por tanto, es imposible que exista ninguna instantánea todavía.
    local config_file="/etc/timeshift/timeshift.json"
    if [[ ! -f "$config_file" ]] || ! grep -q '"backup_device_uuid" *: *"[^"]' "$config_file" 2>/dev/null; then
        found_issue=1
        register_issue
        msg_warn "Timeshift está instalado pero todavía no se ha configurado ningún destino de copia."
        msg_info "Ábrelo desde el menú (Administración > Timeshift) y sigue el asistente para elegir dónde"
        msg_info "guardar las instantáneas; tarda un par de minutos y puede salvarte de un desastre."
        return
    fi

    # 9.2 ¿Existen instantáneas REALES y sigue disponible el destino?
    # Un destino configurado no es lo mismo que tener copias de seguridad.
    # "timeshift --list" es la única fuente fiable, porque consulta el
    # estado real del dispositivo en vez de repetir lo que dice el .json.
    if ! ensure_sudo "comprobar las instantáneas reales de Timeshift"; then
        msg_warn "No se ha podido comprobar si existen instantáneas reales (sin permisos de administrador)."
        msg_info "Tener un destino configurado no basta: confírmalo tú mismo con 'sudo timeshift --list'."
        return
    fi

    local list_out list_rc
    # "timeout" cubre el caso de una unidad de destino externa que ya no
    # responde (desconectada a medias, USB defectuoso...): sin este límite el
    # script podría quedarse colgado aquí de forma indefinida.
    #
    # Se fuerza LC_ALL/LANG=C (igual que en 2.3 y el módulo 3): más abajo se
    # busca texto en inglés en la salida, y Timeshift traduce sus mensajes de
    # consola vía gettext, así que en español ese texto no aparecería.
    list_out=$(sudo LC_ALL=C LANG=C timeout 20 timeshift --list --scripted 2>&1)
    list_rc=$?
    echo "$list_out" >> "$LOG_FILE"

    if [[ $list_rc -eq 124 ]]; then
        found_issue=1
        register_issue
        msg_err "'timeshift --list' no ha respondido en 20s; el dispositivo de destino podría no estar"
        msg_err "disponible o haberse desconectado a medias. Revisa que la unidad de copia siga conectada."
        return
    fi

    if echo "$list_out" | grep -qiE "device not available|not accessible|could not mount"; then
        found_issue=1
        register_issue
        msg_err "El destino de copia configurado no está disponible ahora mismo (¿unidad externa desconectada"
        msg_err "o ha cambiado el UUID de la partición?). Mientras tanto NO se están creando instantáneas nuevas,"
        msg_err "aunque el asistente se completara en su día."
        msg_info "Abre Timeshift y, en Configuración > Ubicación, reconecta o vuelve a seleccionar el destino."
        return
    fi

    # Se cuentan las filas reales de la tabla de instantáneas (líneas con un
    # número de índice seguido de una marca de tiempo con el formato exacto
    # que usa Timeshift: AAAA-MM-DD_HH-MM-SS). Es más robusto que fiarse del
    # texto "N snapshots, X libres" de la cabecera, cuya redacción exacta ha
    # cambiado entre versiones de Timeshift.
    local snap_stamps snapshot_count latest_stamp
    mapfile -t snap_stamps < <(echo "$list_out" | grep -oP '[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}-[0-9]{2}-[0-9]{2}' | sort -u)
    snapshot_count=${#snap_stamps[@]}

    if [[ $snapshot_count -eq 0 ]]; then
        found_issue=1
        register_issue
        msg_warn "Timeshift tiene un destino de copia configurado, pero todavía no existe ninguna instantánea real."
        msg_warn "Un destino configurado no equivale a tener copias de seguridad: sin al menos una instantánea,"
        msg_warn "Timeshift no podría devolverte el sistema a ningún estado anterior si algo sale mal."
        if ask_yes_no "¿Crear ahora la primera instantánea? (puede tardar varios minutos)"; then
            run_step_sudo "crear la primera instantánea con Timeshift" "crear la primera instantánea con Timeshift" \
                sudo timeshift --create --scripted --comments "Mint-Doctor: primera instantánea"
        else
            register_skip
        fi
        return
    fi

    latest_stamp="${snap_stamps[-1]}"
    msg_ok "Hay ${snapshot_count} instantánea(s) real(es) guardada(s)."

    # 9.3 Antigüedad de la instantánea más reciente
    # Timeshift separa fecha y hora con "_", y dentro de la hora usa "-" en
    # vez de ":" (p. ej. "2026-03-01_02-00-01"), así que hay que convertirlo
    # antes de pasárselo a "date -d".
    local latest_parseable latest_epoch now_epoch age_days
    latest_parseable=$(sed -E 's/^([0-9]{4}-[0-9]{2}-[0-9]{2})_([0-9]{2})-([0-9]{2})-([0-9]{2})$/\1 \2:\3:\4/' <<< "$latest_stamp")
    latest_epoch=$(date -d "$latest_parseable" +%s 2>/dev/null)
    if [[ -n "$latest_epoch" ]]; then
        now_epoch=$(date +%s)
        age_days=$(( (now_epoch - latest_epoch) / 86400 ))
        if (( age_days < 0 )); then
            found_issue=1
            register_issue
            msg_warn "La instantánea más reciente tiene fecha futura según el reloj del sistema."
            msg_info "Revisa el reloj/NTP en la opción 5 de este script; con la hora mal ajustada esta"
            msg_info "comprobación de antigüedad no es fiable."
        elif (( age_days > 30 )); then
            found_issue=1
            register_issue
            msg_warn "La instantánea más reciente tiene ${age_days} días. Si esperabas copias más frecuentes,"
            msg_warn "puede que la programación automática se haya detenido sin que lo notaras."
        else
            msg_info "La instantánea más reciente tiene ${age_days} día(s)."
        fi
    fi

    # 9.4 ¿Hay alguna programación automática activada?
    # Un destino configurado con instantáneas ya antiguas puede deberse a que
    # TODAS las frecuencias (hourly/daily/weekly/monthly/boot) estén en
    # "false": en ese caso Timeshift solo crea copias cuando alguien pulsa
    # "Crear" a mano, y es fácil olvidarse de hacerlo con regularidad.
    local sched any_schedule=0
    for sched in schedule_hourly schedule_daily schedule_weekly schedule_monthly schedule_boot; do
        if grep -q "\"${sched}\" *: *\"true\"" "$config_file" 2>/dev/null; then
            any_schedule=1
            break
        fi
    done
    if [[ $any_schedule -eq 0 ]]; then
        found_issue=1
        register_issue
        msg_warn "Ninguna programación automática (por hora/diaria/semanal/mensual/al arrancar) está activada."
        msg_info "Ábrelo desde el menú (Administración > Timeshift) > pestaña 'Programación' para que las"
        msg_info "instantáneas se creen solas y no dependan de acordarte de pulsar 'Crear'."
    fi

    msg_info "Mint-Doctor no sustituye a Timeshift: revisa de vez en cuando que sigan creándose instantáneas"
    msg_info "nuevas, sobre todo antes de una actualización grande del sistema."

    [[ $found_issue -eq 0 ]] && msg_ok "Las copias de seguridad del sistema están en orden."
}

# ======================================================================
# Ayuda y línea de comandos
# ======================================================================
print_help() {
    cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} · $(t 'Autoreparador para') $(get_mint_label) (Cinnamon)

$(t 'Uso'):
  $(basename "$0")                    $(t 'Modo interactivo (menú)')
  $(basename "$0") --dry-run          $(t 'Simula las acciones, no aplica ningún cambio')
  $(basename "$0") --auto             $(t 'Analiza y repara todo automáticamente')
  $(basename "$0") --dry-run --auto   $(t 'Escaneo completo simulado, sin menú')
  $(basename "$0") --lang es|en       $(t 'Fuerza el idioma de la interfaz')
  $(basename "$0") -h, --help         $(t 'Muestra esta ayuda')
  $(basename "$0") -v, --version      $(t 'Muestra la versión y sale')

$(t 'No lo ejecutes con sudo ni como root: el propio script pedirá la contraseña')
$(t 'únicamente cuando una acción concreta la necesite.')

Copyright (C) 2026 Filonux
$(t 'Licencia GPLv3; consulte el archivo LICENSE.txt para el texto completo.')
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=1 ;;
            --auto) AUTO_MODE=1 ;;
            --lang)
                [[ $# -ge 2 ]] || { echo "$(t 'Falta el idioma tras --lang (usa es o en).')" >&2; exit 2; }
                set_language "$2"
                shift
                ;;
            --lang=*) set_language "${1#*=}" ;;
            -h|--help) print_help; exit 0 ;;
            -v|--version) echo "${SCRIPT_NAME} v${SCRIPT_VERSION} · Filonux · GPLv3"; exit 0 ;;
            *)
                echo "$(t 'Opción desconocida:') $1" >&2
                print_help >&2
                exit 1
                ;;
        esac
        shift
    done
}

check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        echo -e "${C_RED}${C_BOLD}$(t 'No ejecutes Mint-Doctor directamente como root ni con sudo.')${C_RESET}" >&2
        echo "$(t 'El script pedirá la contraseña con sudo solo cuando una acción concreta la necesite.')" >&2
        exit 1
    fi
}

# Aviso NO bloqueante si esto no es Linux Mint 22.x: el script se anuncia
# para esa serie pero hasta ahora no lo comprobaba. Se resuelve una sola vez
# (desde main()) y se cachea en MINT_VERSION_OK/_WARNING para que
# print_banner solo tenga que leerlo en cada repintado del menú, sin repetir
# la detección. /etc/linuxmint/info va primero por ser inmune al caso, ya
# visto en el módulo 3, de que /etc/os-release quede con los valores de
# Ubuntu en vez de los de Mint.
check_mint_version() {
    local release=""
    [[ -r /etc/linuxmint/info ]] && release=$(grep -oP '(?<=^RELEASE=).*' /etc/linuxmint/info 2>/dev/null | tr -d '"')
    if [[ -z "$release" ]]; then
        local os_id
        os_id=$(grep -oP '(?<=^ID=).*' /etc/os-release 2>/dev/null | tr -d '"')
        [[ "$os_id" == "linuxmint" ]] && release=$(grep -oP '(?<=^VERSION_ID=).*' /etc/os-release 2>/dev/null | tr -d '"')
    fi
    [[ "$release" == 22* ]] && return

    MINT_VERSION_OK=0
    if [[ -n "$release" ]]; then
        if [[ "$MINT_DOCTOR_LANG" == en ]]; then
            MINT_VERSION_WARNING="Detected system: Linux Mint ${release} · this script was tested against the 22.x series"
        else
            MINT_VERSION_WARNING="Sistema detectado: Linux Mint ${release} · este script se probó en la serie 22.x"
        fi
    else
        if [[ "$MINT_DOCTOR_LANG" == en ]]; then
            MINT_VERSION_WARNING="Could not confirm Linux Mint 22.x on this system (another distribution?)"
        else
            MINT_VERSION_WARNING="No se ha podido confirmar Linux Mint 22.x en este equipo (¿otra distribución?)"
        fi
    fi
    if [[ "$MINT_DOCTOR_LANG" == en ]]; then
        log_line "WARNING" "$MINT_VERSION_WARNING"
    else
        log_line "AVISO" "$MINT_VERSION_WARNING"
    fi
}

# ======================================================================
# Resumen final de la sesión
# ======================================================================
print_summary() {
    echo
    hr
    echo -e "${C_BOLD}$(t 'Resumen de la sesión')${C_RESET}"
    printf "  %-24s %d\n" "$(t 'Problemas detectados:')" "$ISSUES_TOTAL"
    printf "  %-24s %d\n" "$(t 'Solucionados:')" "$ISSUES_FIXED"
    printf "  %-24s %d\n" "$(t 'Omitidos:')" "$ISSUES_SKIPPED"
    echo
    [[ "$LOG_FILE" == /dev/null ]] || msg_info "Registro completo guardado en: $LOG_FILE"

    # Aviso de escritorio solo para --auto: si lo lanzas desatendido (cron o
    # un systemd timer de usuario) es la única forma de enterarte de que
    # encontró algo sin ir a mirar el log a mano. En el menú interactivo no
    # hace falta, porque ya estás delante viendo este mismo resumen. Se omite
    # sin más si no hay sesión gráfica o si no está instalado "notify-send"
    # (paquete libnotify-bin): es un aviso adicional, no algo de lo que
    # dependa el funcionamiento del script.
    if [[ $AUTO_MODE -eq 1 ]] && [[ $ISSUES_TOTAL -gt 0 ]] \
       && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && need_cmd notify-send; then
        local notify_msg
        if [[ "$MINT_DOCTOR_LANG" == en ]]; then
            notify_msg="${ISSUES_TOTAL} issue(s) detected, ${ISSUES_FIXED} fixed. Log: ${LOG_FILE}"
            [[ $DRY_RUN -eq 1 ]] && notify_msg="[SIMULATION, no changes applied] ${notify_msg}"
        else
            notify_msg="${ISSUES_TOTAL} problema(s) detectado(s), ${ISSUES_FIXED} solucionado(s). Registro: ${LOG_FILE}"
            [[ $DRY_RUN -eq 1 ]] && notify_msg="[SIMULACIÓN, sin cambios aplicados] ${notify_msg}"
        fi
        notify-send -i dialog-warning "Mint-Doctor" "$notify_msg" 2>/dev/null
    fi
}

# No incluye quick_status(): main_menu() ya lo pinta en cada vuelta del
# bucle (visible justo antes de elegir esta opción), y main() lo llama aquí
# mismo para --auto. Repetirlo aquí dentro solo duplicaría el cálculo
# (incluye "apt list --upgradable") y el bloque en pantalla.
run_all_modules() {
    mod_info
    mod_apt
    mod_repos
    mod_cache
    mod_boot
    mod_network
    mod_hardware
    mod_cinnamon
    mod_backup
}

# ======================================================================
# Menú interactivo
# ======================================================================
main_menu() {
    local opt
    while true; do
        print_banner
        quick_status
        echo -e "${C_BOLD}$(t '¿Qué quieres revisar?')${C_RESET}"
        hr
        echo "  1) $(t 'Información del sistema')"
        echo "  2) $(t 'Paquetes y APT/dpkg')"
        echo "  3) $(t 'Repositorios de software (orígenes y claves GPG)')"
        echo "  4) $(t 'Espacio en disco y limpieza de caché')"
        echo "  5) $(t 'Arranque, GRUB y reloj del sistema')"
        echo "  6) $(t 'Conectividad de red')"
        echo "  7) $(t 'Salud del hardware (disco, batería y controladores)')"
        echo "  8) $(t 'Escritorio Cinnamon')"
        echo "  9) $(t 'Copias de seguridad (Timeshift)')"
        echo " 10) $(t 'Ejecutar todos los módulos')"
        echo " 11) $(t 'Idioma: Español (cambiar a English)')"
        echo "  0) $(t 'Salir')"
        echo
        read -rp "$(echo -e "${C_BOLD}$(t 'Elige una opción')${C_RESET} [0-11]: ")" opt || break
        case "$opt" in
            1) mod_info; pause ;;
            2) mod_apt; pause ;;
            3) mod_repos; pause ;;
            4) mod_cache; pause ;;
            5) mod_boot; pause ;;
            6) mod_network; pause ;;
            7) mod_hardware; pause ;;
            8) mod_cinnamon; pause ;;
            9) mod_backup; pause ;;
            10) run_all_modules; print_summary; pause ;;
            11) toggle_language; pause ;;
            0|q|Q) break ;;
            *) msg_warn "Opción no válida."; pause ;;
        esac
    done
}

# ======================================================================
# Punto de entrada
# ======================================================================
main() {
    parse_args "$@"
    check_not_root
    init_logging
    check_mint_version

    if [[ $AUTO_MODE -eq 1 ]]; then
        print_banner
        quick_status
        run_all_modules
        print_summary
    else
        main_menu
        echo
        echo -e "${C_CYAN}$(t 'Hasta la próxima. ¡Que tu Mint funcione de maravilla!')${C_RESET}"
        pause
    fi

    # Código de salida útil para cron/systemd que envuelvan una ejecución
    # --auto desatendida: 0 si no queda ningún problema sin resolver, 1 si
    # queda al menos uno. Se limita a --auto a propósito: en el menú
    # interactivo ya has visto el resultado en pantalla, y devolver aquí un
    # código distinto de cero solo confunde a lanzadores "TERMINAL: true"
    # (los del propio "MENU:" de la cabecera), que lo interpretan como que
    # el script en sí ha fallado aunque solo haya detectado avisos.
    if [[ $AUTO_MODE -eq 1 ]] && [[ $ISSUES_TOTAL -gt $ISSUES_FIXED ]]; then
        return 1
    fi
    return 0
}

# Código de salida estándar 128+señal (130 para INT, 143 para TERM) en vez
# de forzar siempre 130, para que quien llame al script (systemd, un
# wrapper...) distinga de qué señal vino la interrupción.
on_interrupt() {
    echo -e "\n${C_YELLOW}$(t 'Interrumpido por el usuario.')${C_RESET}"
    print_summary
    exit "$((128 + $1))"
}
trap 'on_interrupt 2' INT
trap 'on_interrupt 15' TERM

if [[ "${MINT_DOCTOR_TEST_MODE:-0}" != 1 ]]; then
    main "$@"
fi
