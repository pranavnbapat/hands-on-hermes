FROM ubuntu:24.04

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8
# Unpinned on purpose: the image should pick up Ubuntu security updates.
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git tar coreutils python3 libatomic1 less nano tzdata \
 && rm -rf /var/lib/apt/lists/*

# Unprivileged user with the host's uid, so file ownership lines up.
ARG USER_UID=1000
RUN (userdel -r ubuntu 2>/dev/null || true) \
 && useradd -l -m -u "$USER_UID" -s /bin/bash participant

USER participant
WORKDIR /home/participant
ENV PATH=/home/participant/.local/bin:$PATH

ARG INSTALL_HERMES=true
ARG INSTALLER_URL=https://hermes-agent.nousresearch.com/install.sh
ARG INSTALLER_SHA256=""
ARG HERMES_REFRESH=""
RUN if [ "$INSTALL_HERMES" = "true" ]; then \
      curl -fsSL "$INSTALLER_URL" -o hermes-install.sh \
      && echo "installer sha256: $(sha256sum hermes-install.sh | cut -d' ' -f1)" \
      && if [ -n "$INSTALLER_SHA256" ]; then echo "$INSTALLER_SHA256  hermes-install.sh" | sha256sum -c -; fi \
      && { bash hermes-install.sh --non-interactive --skip-browser --skip-computer-use > install.log 2>&1 \
           || { echo "Installer failed once (seen intermittently in its Node dependencies step); retrying:"; \
                tail -n 5 install.log; \
                bash hermes-install.sh --non-interactive --skip-browser --skip-computer-use > install.log 2>&1; } \
           || { tail -n 40 install.log; exit 1; }; } \
      && hermes --version; \
    else \
      echo "Hermes not installed (INSTALL_HERMES=$INSTALL_HERMES)"; \
    fi

# Marks the workshop container. Scripts that install, configure or run Hermes
# refuse to run where this isn't set, i.e. on the host.
ENV HERMES_WORKSHOP_CONTAINER=1
