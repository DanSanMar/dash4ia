# dash4ia

Monitor de recursos de terminal, en un único script Bash, pensado para vigilar
**cargas de IA en local** (LLMs, difusión, etc.): uso de CPU y su temperatura,
memoria RAM, GPU/VRAM y los procesos que más CPU consumen.

![versión](https://img.shields.io/badge/versión-1.2-blue)
![licencia](https://img.shields.io/badge/licencia-GPL--3.0--or--later-green)

## Características

- **CPU**: uso total y temperatura, con barra y color según umbral.
- **RAM**: memoria usada / total y memoria disponible.
- **GPU / VRAM**: NVIDIA (vía `nvidia-smi`), AMD e Intel (vía `/sys`).
  Muestra uso de GPU, VRAM usada / total / disponible, temperatura y
  ventilador (en RPM, o en % si el driver solo expone el ciclo de trabajo).
- **Carga del sistema**: `load avg` de 1/5/15 min y número de CPUs.
- **Procesos**: los 3 que más CPU consumen, destacando los de IA con `[IA]`.
- **Dos modos**: `full` (pantalla alternativa, sin parpadeo) y `simple`
  (texto plano, ideal para terminales no interactivas o tuberías).
- **Sin dependencias obligatorias**: si falta una utilidad, esa sección se
  degrada con elegancia (por ejemplo, muestra `n/d`).

## Requisitos

- Linux con Bash 4 o superior.
- Las lecturas base se hacen desde `/proc` (CPU, RAM, carga y procesos).
- **Opcionales** (se usan si están presentes):
  - `nvidia-smi` — GPUs NVIDIA.
  - `lspci` — nombre del modelo de GPU AMD/Intel.
  - `sensors` — temperatura de CPU cuando `/sys` no la expone.

## Instalación

```bash
git clone <url-del-repo> dash4ia
cd dash4ia
chmod +x dash4ia.sh
```

## Uso

```bash
./dash4ia.sh              # bucle con refresco por defecto (cada 2 s)
./dash4ia.sh -i 1         # refresco cada 1 s
./dash4ia.sh -1           # una sola muestra y salir
./dash4ia.sh -1 -s        # una muestra en texto plano (pruebas / tuberías)
./dash4ia.sh -V           # mostrar la versión
./dash4ia.sh -h           # ayuda
```

En modo `full` se entra en la pantalla alternativa y se restaura al salir.
Para terminar el bucle pulsa **Ctrl+C**.

### Opciones

| Opción | Descripción |
| --- | --- |
| `-i, --interval SEG` | Intervalo de refresco en segundos (por defecto `2`). |
| `-s, --simple` | Modo texto plano: sin colores, sin bordes ni pantalla alternativa. |
| `-1, --once` | Dibuja un único frame y sale. |
| `-V, --version` | Muestra la versión y sale. |
| `-h, --help` | Muestra la ayuda y sale. |

### Variables de entorno

| Variable | Valores | Descripción |
| --- | --- | --- |
| `DASH4IA_INTERVAL` | número | Intervalo por defecto (segundos). |
| `DASH4IA_MODE` | `full` \| `simple` | Modo de salida por defecto. |

Los flags de línea de comandos tienen prioridad sobre las variables de entorno.

## Notas

- El modo `full` usa la pantalla alternativa (`tput smcup`) y restaura el
  terminal al salir.
- La detección de "procesos de IA" es heurística: busca ciertos patrones en el
  nombre del proceso (`ollama`, `llama`, `vllm`, `comfy`, `python`, etc.).
- Las GPUs AMD/Intel se leen vía `sysfs`; en algunos equipos puede no haber
  datos de VRAM o de ventilador, en cuyo caso se muestra `n/d`.

## Licencia

Este proyecto se distribuye bajo la **GNU General Public License v3.0 o
posterior** (GPL-3.0-or-later). Copyright (C) 2026 **DanSanMar**.

Consulta el archivo [LICENSE](LICENSE) para el texto completo.
