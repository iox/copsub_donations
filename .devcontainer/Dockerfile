FROM drecom/ubuntu-ruby:2.3.8

LABEL maintainer="ignacio@ihuerta.net"

# install required system packages
RUN apt-get update -qq && apt-get install -y sudo wget build-essential libfontconfig1 libxrender1 libxext6 curl net-tools git nano memcached --fix-missing --no-install-recommends

# Install mysql in noninteractive mode: sets the root password to an empty string
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

# This Dockerfile adds a non-root 'vscode' user with sudo access. However, for Linux,
# this user's GID/UID must match your local user UID/GID to avoid permission issues
# with bind mounts. Update USER_UID / USER_GID if yours is not 1000. See
# https://aka.ms/vscode-remote/containers/non-root-user for details.
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=$USER_UID

RUN groupadd --gid $USER_GID $USERNAME \
    && useradd -s /bin/bash --uid $USER_UID --gid $USER_GID -m $USERNAME \
    # [Optional] Add sudo support for the non-root user
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME\
    && chmod 0440 /etc/sudoers.d/$USERNAME


# Prepeare workdir
ENV INSTALL_PATH /workspace
RUN mkdir -p $INSTALL_PATH
WORKDIR $INSTALL_PATH

# Install nodejs
RUN curl -sL https://deb.nodesource.com/setup_9.x | bash - && apt-get install -y nodejs


# Install the latest versions of Google Chrome and Chromedriver:
RUN export DEBIAN_FRONTEND=noninteractive \
  && apt-get update \
  && apt-get install --no-install-recommends --no-install-suggests -y \
    unzip \
    gnupg \
  && GOOGLE_LINUX_DL=https://dl.google.com/linux \
  && curl -sL "$GOOGLE_LINUX_DL/linux_signing_key.pub" | apt-key add - \
  && curl -sL "$GOOGLE_LINUX_DL/direct/google-chrome-stable_current_amd64.deb" \
    > /tmp/chrome.deb \
  && apt install --no-install-recommends --no-install-suggests -y \
    /tmp/chrome.deb \
  && CHROMIUM_FLAGS='--no-sandbox --disable-dev-shm-usage' \
  # Patch Chrome launch script and append CHROMIUM_FLAGS to the last line:
  && sed -i '${s/$/'" $CHROMIUM_FLAGS"'/}' /opt/google/chrome/google-chrome \
  && BASE_URL=https://chromedriver.storage.googleapis.com \
  && VERSION=$(curl -sL "$BASE_URL/LATEST_RELEASE") \
  && curl -sL "$BASE_URL/$VERSION/chromedriver_linux64.zip" -o /tmp/driver.zip \
  && unzip /tmp/driver.zip \
  && chmod 755 chromedriver \
  && mv chromedriver /usr/local/bin/ \
  # Remove obsolete files:
  && apt-get autoremove --purge -y \
    unzip \
    gnupg \
  && apt-get clean \
  && rm -rf \
    /tmp/* \
    /usr/share/doc/* \
    /var/cache/* \
    /var/lib/apt/lists/* \
    /var/tmp/*


CMD sudo service mysql start && sudo service memcached start && /bin/sh -c "while sleep 1000; do :; done"
