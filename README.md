<img src="assets/icon.png" alt="Mint-Doctor" width="96" height="96">

# Mint-Doctor

Autoreparador de terminal para Linux Mint 22.3 "Zena" con Cinnamon: detecta, explica y soluciona —con tu permiso— los problemas más habituales de esta versión concreta del sistema.

![Bash 4+](https://img.shields.io/badge/bash-%3E%3D4.0-4EAA25?logo=gnubash&logoColor=white) ![Linux Mint 22.3 Cinnamon](https://img.shields.io/badge/Linux%20Mint-22.3%20Cinnamon-87CF3E?logo=linuxmint&logoColor=white) [![Licencia GPLv3](https://img.shields.io/badge/licencia-GPLv3-blue)](LICENSE)

---

> 🇪🇸 Este proyecto está en español: el script y esta documentación. Si te interesa una versión en inglés, hay una nota al final, en [Sobre el idioma](#sobre-el-idioma).

## Índice

- [¿Qué es Mint-Doctor?](#qué-es-mint-doctor)
- [La ventaja principal](#la-ventaja-principal)
- [Instalación](#instalación)
- [Comandos](#comandos)
- [Uso](#uso)
- [Compatibilidad](#compatibilidad)
- [Conviértelo en una app con Scriptya](#conviértelo-en-una-app-con-scriptya)
- [Sobre el idioma](#sobre-el-idioma)
- [Contribuir](#contribuir)
- [Licencia](#licencia)

## ¿Qué es Mint-Doctor?

Mint-Doctor es un script de terminal que revisa tu Linux Mint 22.3 con Cinnamon en busca de los problemas concretos que de verdad le pasan a esta versión: claves GPG que fallan tras actualizar, un driver NVIDIA que dejó de arrancar con el kernel nuevo, un paquete que rompe el renderizado de aplicaciones GTK4, kernels acumulados sin dejar espacio, un Timeshift "configurado" que en realidad nunca llegó a crear una copia...

No es un limpiador genérico de los que prometen dejar el PC "como nuevo". Se parece más a la checklist de un mecánico, escrita a partir de las propias notas de versión de Mint y de los problemas que se repiten en su foro oficial: repasa un punto, te explica qué encontró y por qué importa, y solo actúa si tú lo confirmas.

<img width="842" height="593" alt="mint-doctor-menu" src="https://github.com/user-attachments/assets/afad29bd-0504-458c-beb2-9c902d8dd4f2" />

## La ventaja principal

Cualquier script de "mantenimiento" sabe vaciar una papelera o lanzar `apt autoremove`. Lo que distingue a Mint-Doctor es que conoce defectos *documentados* de Mint 22.3 en concreto, entre otros:

- El driver `nvidia-driver-470` deja de funcionar con el kernel HWE 6.14+ que Mint 22.2/22.3 instalan por defecto en equipos nuevos.
- `gstreamer1.0-vaapi` puede romper el renderizado de aplicaciones basadas en WebKit/GTK4.
- PipeWire puede cortar el audio por salidas HDMI, un fallo ya documentado en las notas de la versión.
- El tiempo de espera al apagar se redujo a 10s desde Mint 22.2, y puede forzar el cierre de servicios que tardan más en cerrarse.
- Los "spices" de Cinnamon (applets, desklets, extensiones) instalados a mano pueden dejar de cargar tras el salto de Cinnamon 6.4 a 6.6.
- Con Secure Boot activo, un módulo DKMS (NVIDIA propietario, VirtualBox...) recién compilado puede quedar sin cargar por falta de firma MOK, sin que lo parezca a simple vista.

A eso se suma un diseño pensado para no romper nada por accidente:

- **Nada se aplica sin preguntar.** En modo automático (`--auto`) se asume "sí" para las reparaciones normales, pero **importar una clave GPG nueva exige siempre tu confirmación explícita**, incluso en ese modo: sin terminal para preguntar, esa clave se omite en vez de aceptarse sola.
- **Modo simulación** (`--dry-run`) para ver exactamente qué haría, sin tocar nada.
- **No corre como root.** Solo pide la contraseña con `sudo` cuando una acción concreta lo necesita, y explica para qué.
- **Copia de seguridad antes de tocar archivos de orígenes de software**, y un registro detallado de cada sesión.
- **No automatiza lo que no debería.** Reparar un NTFS marcado como "dirty", inscribir una clave MOK de Secure Boot o un repositorio oficial de Mint que no coincide con tu versión son casos donde solo se explica qué pasa y cómo solucionarlo tú mismo.

## Instalación

```bash
git clone https://github.com/filonux/mint-doctor.git
cd mint-doctor
chmod +x script/mint-doctor.sh
./script/mint-doctor.sh
```

No hace falta instalar nada más de antemano: todo lo que usa de entrada ya viene de fábrica en Linux Mint. Si algún módulo detecta que falta una herramienta puntual (`smartmontools`, `TLP`, `Timeshift`, `psmisc`...), te ofrece instalarla ella misma, con tu confirmación.

## Comandos

| Comando | Qué hace |
| --- | --- |
| `./script/mint-doctor.sh` | Abre el menú interactivo |
| `./script/mint-doctor.sh --dry-run` | Simula las acciones; no aplica ningún cambio |
| `./script/mint-doctor.sh --auto` | Analiza y repara todo automáticamente, sin menú |
| `./script/mint-doctor.sh --dry-run --auto` | Escaneo completo simulado, sin menú |
| `./script/mint-doctor.sh -h`, `--help` | Muestra la ayuda |
| `./script/mint-doctor.sh -v`, `--version` | Muestra la versión |

## Uso

Al arrancar sin argumentos, Mint-Doctor abre un menú con un panel rápido de estado (disco, RAM, APT, actualizaciones pendientes, red) y diez opciones:

1. **Información del sistema** — distribución, kernel, Cinnamon, CPU, disco/RAM, tipo de sesión. Solo lectura, no cambia nada.
2. **Paquetes y APT/dpkg** — bloqueos obsoletos, instalaciones a medias, dependencias rotas, paquetes retenidos, permisos de `pkexec`/`sudo`.
3. **Repositorios de software** — orígenes con nombre en clave de una versión anterior de Mint/Ubuntu, claves GPG ausentes o inválidas, repositorios caídos, keyring heredado.
4. **Espacio en disco y caché** — caché de APT, kernels antiguos acumulados, caché de miniaturas, papelera, tamaño del journal de systemd, runtimes de Flatpak sin usar, remoto Flathub ausente, partición `/boot` casi llena.
5. **Arranque, GRUB y reloj** — entrada de GRUB para el kernel actual, reinicio pendiente, reloj RTC desincronizado en arranque dual con Windows, volúmenes NTFS marcados como "dirty", sincronización NTP, servicios systemd fallidos, apagados forzados por el nuevo tiempo de espera.
6. **Conectividad de red** — radios bloqueadas por software (rfkill), conexión a Internet y resolución DNS comprobadas por separado.
7. **Salud del hardware** — estado S.M.A.R.T. de los discos, salud de la batería y gestión de energía con TLP, módulos DKMS sin reconstruir tras un kernel nuevo, compatibilidad del driver NVIDIA 470, servidor de sonido, Secure Boot y módulos rechazados por falta de firma MOK, Guest Additions de VirtualBox.
8. **Escritorio Cinnamon** — bloqueos recientes, accesos directos del escritorio sin marcar como confiables, el paquete `gstreamer1.0-vaapi`, códecs multimedia, sesión en modo sin aceleración 3D, compatibilidad de spices de terceros con la versión de Cinnamon instalada.
9. **Copias de seguridad (Timeshift)** — que exista un destino configurado, que haya instantáneas reales (no solo el asistente completado), su antigüedad y si hay alguna programación automática activa.
10. **Ejecutar todos los módulos** — la misma secuencia que usa `--auto`, pero preguntando cada paso.

Cada sesión queda registrada en `~/.mint-doctor/` (permisos restringidos a tu usuario; se conservan las últimas 20). Al terminar, un resumen indica cuántos problemas se detectaron, cuántos se arreglaron y cuántos se omitieron.

Para dejarlo corriendo sin supervisión (por ejemplo con un temporizador de `systemd --user` o `cron`), usa `--auto`: no abre ningún menú y devuelve el código de salida `1` si queda algún problema sin resolver (`0` si no), útil para que el lanzador sepa si hizo falta revisar algo. Si hay sesión gráfica y `notify-send` instalado, además avisa con una notificación de escritorio.

## Compatibilidad

Hecho y probado para **Linux Mint 22.3 "Zena" con Cinnamon** (6.6.x). Al arrancar comprueba la versión instalada; si detecta una distinta a la serie 22.x, avisa con un mensaje pero **no bloquea la ejecución**: los módulos que dependen de Cinnamon o de rutas propias de Mint simplemente no encontrarán nada que revisar en un sistema distinto.

- Necesita Bash, `sudo` y las herramientas estándar de un Mint con Cinnamon (APT/dpkg, systemd...).
- Debe ejecutarse como usuario normal, nunca como root ni con `sudo script/mint-doctor.sh`.
- Algunos módulos son opcionales por naturaleza: batería/TLP solo aplica en portátiles, DKMS/Secure Boot solo si usas drivers de terceros, Flatpak solo si lo tienes instalado.

## Conviértelo en una app con Scriptya

[**Scriptya**](https://github.com/filonux/Scriptya), otra herramienta del mismo autor, convierte cualquier script en una app independiente con su propio icono, integrada en el menú de Cinnamon y/o en el escritorio —y de paso deja lanzarlo, actualizarlo o desinstalarlo desde un único menú, sin escribir un `.desktop` a mano.

`mint-doctor.sh` ya incluye en su cabecera los metadatos que Scriptya sabe leer (`MENU`, `DESCRIPTION`, `TERMINAL`), así que basta con apuntarle a la carpeta del proyecto para tenerlo integrado.

## Sobre el idioma

Mint-Doctor está en español: menú, mensajes, avisos y este README. No hay versión en inglés todavía.

**Mini roadmap**, sujeto a que haya interés real:

- [ ] Traducción completa del script (menús, mensajes, ayuda) al inglés
- [ ] README en inglés
- [ ] Forma de elegir idioma sin tocar el script (detección del sistema o variable de entorno)

Si te interesaría usarlo en inglés, dilo en un issue — es la señal que hace falta para priorizarlo.

## Contribuir

Los issues y pull requests son bienvenidos; hay plantillas en `.github/` para reportar errores o proponer mejoras. La guía completa está en [CONTRIBUTING.md](.github/CONTRIBUTING.md), y el código de conducta en [CODE_OF_CONDUCT.md](.github/CODE_OF_CONDUCT.md). Para reportar un problema de seguridad, consulta [SECURITY.md](.github/SECURITY.md) en vez de abrir un issue público.

## Licencia

GPLv3. Consulta el fichero [LICENSE](LICENSE).

---

Hecho por **Filonux**.
