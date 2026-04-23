FROM jflournoy/verse-cmdstan:latest
LABEL maintainer="John Flournoy <jcflournoyphd@pm.me>"

# ========================================
# Connectome Workbench (wb_command, wb_view)
# ========================================
# Installs from NeuroDebian. wb_command -show-scene renders scenes
# headlessly via OSMesa, so no X server/VNC is required.
USER root
RUN . /etc/os-release \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      curl gnupg ca-certificates \
 && curl -fsSL "http://neuro.debian.net/lists/${VERSION_CODENAME}.us-nh.full" \
      -o /etc/apt/sources.list.d/neurodebian.sources.list \
 && curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x439754ED1F42AA2C" \
      | gpg --dearmor -o /usr/share/keyrings/neurodebian-archive-keyring.gpg \
 && sed -i 's|^deb |deb [signed-by=/usr/share/keyrings/neurodebian-archive-keyring.gpg] |' \
      /etc/apt/sources.list.d/neurodebian.sources.list \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      connectome-workbench \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Smoke test: confirm wb_command is on PATH and can report its version.
RUN wb_command -version | head -5

WORKDIR /home/rstudio
