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
- **Pinned analysis packages**, each verified by a build-time smoke test:
  - `gratia` 0.10.0 — simultaneous-interval derivatives (`derivatives(select=)`)
  - `ggseg` 2.1.1 + `ggsegGlasser` 2.0.3 + `ggseg.formats` 0.0.2 — brain figures
  - `lme4` 1.1-38 — held down from 2.0-1 and built from source against the
    image's Matrix 1.6.1.1 (Matrix 1.7-x needs R ≥ 4.4; this image is R 4.3.2)
  - `patchwork` 1.3.2 — the ggplot2 4.x (S7) `&` theme methods
  - `dagitty` 0.3-4 + `ggdag` 0.2.13 — causal-DAG reports

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
- **Package pinning:** each `install_*.R` at the repo root installs one pinned
  package (or family) and then *verifies the API the analysis actually calls* —
  gratia fits a GAM and takes a derivative, ggseg draws a brain to a device,
  lme4 fits `lmer()`, patchwork dispatches `<patchwork> & <theme>`, and
  `install_render_packages.R` exercises each of its nine in turn, kableExtra
  included. An upstream API change therefore fails `docker compose build`
  rather than silently changing results.
- **The nine render packages:** `install_render_packages.R` installs
  ciftiTools, energy, GGally, hexbin, psych, scico, targets, tarchetypes and
  kableExtra. Every one of them used to resolve from a host user library and
  from nowhere else, so the analysis code ran on one machine and nowhere else:
  under Snakemake, which sets `HOME` to the project, and in this image they
  were simply absent. `targets` and `tarchetypes` are the sharp end, since
  `run_pipeline.R` and `_targets.R` cannot load without them, and kableExtra
  was never in the image at all.
- **Python:** `/opt/venv` carries the stack
  `scripts/dropout_raw_signal_render.py` needs, pinned to numpy 1.23.5,
  pandas 1.3.5, matplotlib 3.5.3, nibabel 4.0.2 and nilearn 0.10.2. The step
  renders an inflated fs_LR surface from ciftiTools' extdata as its check, so
  it runs after `install_render_packages.R` and an API drift fails the build.
- **CRAN snapshots:** the image-wide `CRAN_SNAPSHOT` is date-pinned to
  2025-06-02 (the date where gratia 0.10.0 is current). Steps whose pin is
  newer than that override `CRAN_SNAPSHOT` on their own `RUN` line. The rule is
  to pick the snapshot date at which the pinned version is the *current* one, so
  the `__linux__/jammy` binary repo serves it and nothing falls back to the
  source archive.
- **One step cannot follow that rule, and says so here:**
  `install_render_packages.R` pins nine packages whose releases fall in
  different eras, and no single date makes all nine current. Measured
  2026-10-14, the 2026-08-01 jammy snapshot is the earliest that serves all
  nine, with ciftiTools, energy, GGally and scico current as binaries and
  hexbin, psych, targets, tarchetypes and kableExtra coming from the source
  archive; 2026-10-01 is worse, at three of nine. All nine were confirmed to
  resolve with the repos vector the script passes. Splitting the step one
  package per date would restore the rule at the cost of nine more layers.

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
