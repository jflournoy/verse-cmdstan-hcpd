# verse-cmdstan-hcpd

RStudio + CmdStan + Connectome Workbench development environment in Docker.

Extends [verse-cmdstan](https://github.com/jflournoy/verse-cmdstan) with the [Connectome Workbench](https://humanconnectome.org/software/connectome-workbench) command-line tools for neuroimaging data processing and visualization.

## Quick start

```bash
docker compose up -d
```

Then open **http://127.0.0.1:9211** to access RStudio.

## What's included

- **R 4.3.2** with tidyverse, Quarto, and development tools (via rocker/ml-verse)
- **CmdStan 2.35.0** with optimized compilation settings
- **Node.js 22.x** with TypeScript, eslint, ts-node
- **TeX Live 2026** with common packages for scientific publishing
- **Connectome Workbench 2.1.0** command-line tools:
  - `wb_command` — neuroimaging data processing and format conversion
  - `wb_view` — interactive visualization (with X11 display)
  - `wb_command -scene-capture-image` — programmatic headless rendering via OSMesa

## Using Connectome Workbench

### Headless scene rendering (no display needed)

```bash
wb_command -scene-capture-image scene.wbscene scene-name output.png 1920 1080
```

This renders a scene to PNG/other formats without requiring X11 or a VNC desktop.

### Interactive visualization (requires display)

```bash
wb_view
```

The `wb_view` GUI requires an X11 display. You can either:
- Use the RStudio terminal with X11 forwarding over SSH
- Run `xvfb-run wb_view ...` for offscreen X rendering (requires `xvfb-run` in the container)

## Configuration

### Mount directories

By default, the container mounts `$HOME/{code,data,R}` into the container at `/home/rstudio/{code,data,R}`. To customize, edit `.env`:

```bash
cp .env.example .env
# then edit .env to mount different paths
```

### RStudio port

The default port is 9211. To change:

```bash
RSTUDIO_PORT=8787 docker compose up -d
```

## Architecture notes

- **Base image:** `jflournoy/verse-cmdstan:latest` (rocker/ml-verse:4.3.2 + CmdStan)
- **Ubuntu codename:** jammy (22.04 LTS) — detected dynamically at build time
- **Connectome Workbench source:** [NeuroDebian](https://neuro.debian.net/)
- **GPU support:** NVIDIA CUDA 11.8 (if you have docker with GPU runtime)

## Building from source

```bash
docker compose build
```

## Useful commands

```bash
docker compose logs -f          # watch container output
docker compose down             # stop and remove
docker compose exec rstudio bash # enter container shell
```

## License

See [verse-cmdstan](https://github.com/jflournoy/verse-cmdstan) for parent image licensing.
