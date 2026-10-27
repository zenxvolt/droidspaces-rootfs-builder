# Dockerfile (GUI)
# Stage 1: Build and customize the rootfs for development (GUI - Kali Rolling)
ARG TARGETPLATFORM
FROM kalilinux/kali-rolling AS customizer

ENV DEBIAN_FRONTEND=noninteractive

# Kali mirrors to try while building, in order. The default redirector
# (http.kali.org) can send GitHub runners to a mirror that is unreachable
# ("Unable to connect to mirror...", exit code 100), and apt keeps retrying that
# same mirror, so pick one that works instead.
# Override with: --build-arg KALI_MIRRORS="http://host/kali http://host2/kali"
ARG KALI_MIRRORS="http://kali.download/kali http://mirror.freedif.org/kali http://ftp.halifax.rwth-aachen.de/kali http://http.kali.org/kali"

# Update base system using the first mirror that works.
# While building, /etc/apt/apt.conf.d/80-ds-build and /etc/apt/ds-build.list
# replace the stock apt sources for every later apt-get call. Both files are
# removed in the final cleanup layer, so the shipped rootfs keeps the stock sources.
RUN <<EOF_APT
{
    echo 'Acquire::Retries "5";'
    echo 'Acquire::http::Timeout "30";'
    echo 'Acquire::https::Timeout "30";'
    echo 'Dir::Etc::SourceList "/etc/apt/ds-build.list";'
    echo 'Dir::Etc::SourceParts "/nonexistent";'
} > /etc/apt/apt.conf.d/80-ds-build

KEYRING=/usr/share/keyrings/kali-archive-keyring.gpg
SIGNED_BY=""
if [ -f "$KEYRING" ]; then SIGNED_BY="[signed-by=$KEYRING] "; fi

for mirror in $KALI_MIRRORS; do
    echo ">>> Trying Kali mirror: $mirror"
    echo "deb ${SIGNED_BY}$mirror kali-rolling main contrib non-free non-free-firmware" > /etc/apt/ds-build.list
    if apt-get update -o APT::Update::Error-Mode=any && apt-get upgrade -y; then
        echo ">>> Using Kali mirror: $mirror"
        exit 0
    fi
    echo ">>> Mirror failed: $mirror"
    sleep 5
done

echo "All Kali mirrors failed" >&2
exit 1
EOF_APT

# Copy our bashrc script to the rootfs
COPY scripts/bashrc.sh /etc/profile.d/ds-aliases.sh

# Make scripts executable
RUN chmod +x /etc/profile.d/ds-aliases.sh

# Main installation layer for everything (Minimal + CLI + GUI + Dev tools)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    # Core utilities
    bash \
    dialog \
    coreutils \
    file \
    findutils \
    grep \
    sed \
    gawk \
    curl \
    wget \
    ca-certificates \
    locales \
    bash-completion \
    udev \
    dbus \
    systemd-sysv \
    systemd-resolved \
    # Compression tools
    zip \
    unzip \
    p7zip-full \
    bzip2 \
    xz-utils \
    tar \
    gzip \
    # System tools
    htop \
    btop \
    vim \
    nano \
    git \
    sudo \
    openssh-server \
    net-tools \
    iptables \
    iputils-ping \
    iproute2 \
    dnsutils \
    usbutils \
    pciutils \
    lsof \
    psmisc \
    procps \
    fastfetch \
    kmod \
    # Wireless networking tools
    iw \
    # Logging & Rotation
    logrotate \
    # Official Kali Zsh shell and plugins
    zsh \
    zsh-autosuggestions \
    zsh-syntax-highlighting \
    command-not-found \
    kali-defaults \
    # Development tools
    build-essential \
    gcc \
    g++ \
    gdb \
    make \
    cmake \
    autoconf \
    automake \
    libtool \
    pkg-config \
    # Additional dev tools
    clang \
    llvm \
    valgrind \
    strace \
    ltrace \
    # Python Development
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    python-is-python3 \
    # File system tools
    gparted \
    dosfstools \
    exfatprogs \
    btrfs-progs \
    ntfs-3g \
    xfsprogs \
    hfsprogs \
    cryptsetup \
    udftools \
    f2fs-tools \
    # Audio
    pulseaudio \
    pulseaudio-utils \
    pavucontrol \
    # Kali XFCE Desktop Environment and essential tools
    kali-desktop-xfce \
    xfce4 \
    desktop-base \
    xfce4-terminal \
    xfce4-session \
    xfce4-goodies \
    xfce4-taskmanager \
    mousepad \
    galculator \
    nemo-fileroller \
    ristretto \
    xfce4-screenshooter \
    catfish \
    xcursor-themes \
    xfce4-clipman-plugin \
    xinit \
    xorg \
    dbus-x11 \
    at-spi2-core \
    tumbler \
    kali-themes \
    # Icon themes
    adwaita-icon-theme \
    hicolor-icon-theme \
    gnome-icon-theme \
    tango-icon-theme \
    papirus-icon-theme \
    # Essential fonts for GUI rendering
    fonts-dejavu-core \
    fonts-liberation \
    fonts-liberation2 \
    fonts-noto-core \
    fonts-noto-ui-core \
    # File manager and GUI utilities
    thunar \
    thunar-volman \
    thunar-archive-plugin \
    thunar-media-tags-plugin \
    gvfs \
    gvfs-backends \
    gvfs-fuse \
    x11-xserver-utils \
    x11-utils \
    xclip \
    xsel \
    xfwm4 \
    xfconf \
    zenity \
    notification-daemon \
    # Browser (Firefox ESR)
    firefox-esr \
    # User directory management
    xdg-user-dirs \
    # PolicyKit for permissions
    polkitd \
    mate-polkit \
    # Docker
    docker.io \
    docker-compose \
    docker-cli \
    && apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Configure locales, environment, SSH, user setup, and official Zsh default shell
RUN sed -i '/en_US.UTF-8/s/^# //' /etc/locale.gen && \
    locale-gen && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 && \
    # Configure SSH (Disable Root Login)
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    # Set Zsh as default shell for root and future users
    chsh -s /bin/zsh root && \
    if [ -f /etc/default/useradd ]; then sed -i 's|^SHELL=.*|SHELL=/bin/zsh|' /etc/default/useradd; fi && \
    if [ -f /etc/adduser.conf ]; then sed -i 's|^DSHELL=.*|DSHELL=/bin/zsh|' /etc/adduser.conf; fi && \
    # Copy official Kali .zshrc to root
    if [ -f /etc/skel/.zshrc ]; then cp /etc/skel/.zshrc /root/.zshrc; fi && \
    # Ensure custom aliases are loaded in Zsh
    mkdir -p /etc/zsh && \
    echo '[ -f /etc/profile.d/ds-aliases.sh ] && . /etc/profile.d/ds-aliases.sh' >> /etc/zsh/zshrc && \
    # Initialize default user directories for GUI apps
    xdg-user-dirs-update && \
    # Remove default users if they exist
    deluser --remove-home kali || true && \
    deluser --remove-home debian || true

# Fix DHCP in the container
RUN mkdir -p /etc/systemd/network && \
    cat <<'EOF' > /etc/systemd/network/10-eth-dhcp.network
[Match]
Name=eth*

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCPv4]
UseDNS=yes
UseDomains=yes
RouteMetric=100
EOF

# Apply container compatibility fixes (Systemd and Udev)
RUN <<EOF_RUN

# --- 1. General Fixes ---
# Future users created with adduser get access to input, video and tty devices
if [ -f /etc/adduser.conf ]; then
    sed -i '/^EXTRA_GROUPS=/d; /^ADD_EXTRA_GROUPS=/d' /etc/adduser.conf
    echo 'ADD_EXTRA_GROUPS=1' >> /etc/adduser.conf
    echo 'EXTRA_GROUPS="input video tty"' >> /etc/adduser.conf
fi

# --- 2. Systemd-Specific Fixes ---
# Mask services that do not work inside a container
ln -sf /dev/null /etc/systemd/system/systemd-networkd-wait-online.service
ln -sf /dev/null /etc/systemd/system/systemd-journald-audit.socket

# Journald configuration (skip Audit, KMsg, etc)
cat >> /etc/systemd/journald.conf << 'EOT'
[Journal]
ReadKMsg=no
Audit=no
Storage=volatile
EOT

mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/ds-logging.conf << 'EOT'
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=200M
MaxRetentionSec=7day
MaxLevelStore=info
EOT

# Enable essential services
mkdir -p /etc/systemd/system/multi-user.target.wants
GUEST_SYSTEMD_PATH="/lib/systemd/system"
for service in dbus.service systemd-udevd.service systemd-resolved.service systemd-networkd.service NetworkManager.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$service" ]; then
        ln -sf "$GUEST_SYSTEMD_PATH/$service" "/etc/systemd/system/multi-user.target.wants/$service"
    fi
done

# Disable power button handling in systemd-logind
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/99-power-key.conf << 'EOF'
[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandlePowerKeyLongPress=ignore
HandlePowerKeyLongPressHibernate=ignore
EOF

# Apply udev overrides
# 1. Trigger override (Prevents coldplugging the host's hardware)
mkdir -p /etc/systemd/system/systemd-udev-trigger.service.d
cat > /etc/systemd/system/systemd-udev-trigger.service.d/override.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/usr/bin/udevadm trigger --subsystem-match=usb --subsystem-match=block --subsystem-match=input --subsystem-match=tty --subsystem-match=net
EOF

# 2. Read-only path overrides to prevent failures
for unit in systemd-udevd.service systemd-udev-trigger.service systemd-udev-settle.service systemd-udevd-kernel.socket systemd-udevd-control.socket; do
    mkdir -p "/etc/systemd/system/${unit}.d"
    printf "[Unit]\nConditionPathIsReadWrite=\n" > "/etc/systemd/system/${unit}.d/99-readonly-fix.conf"
done

# Keep network services out of host and none modes; every mode with its own
# network needs a DHCP client, so list the modes to skip, not the ones to run in
# Stops the container from fighting the host over its network in host network mode
for unit in NetworkManager.service dhcpcd.service systemd-resolved.service systemd-networkd.service; do
    if [ -f "$GUEST_SYSTEMD_PATH/$unit" ] || [ -f "/etc/systemd/system/multi-user.target.wants/$unit" ]; then
        mkdir -p "/etc/systemd/system/${unit}.d"
        cat > "/etc/systemd/system/${unit}.d/99-netmode-limit.conf" << 'EOF'
[Service]
ExecCondition=
ExecCondition=/bin/sh -c "grep -q '^net_mode=' /run/droidspaces/container.config && ! grep -qE '^net_mode=(host|none)$' /run/droidspaces/container.config"
EOF
    fi
done

# Configure logrotate
if [ -f /etc/logrotate.conf ]; then
    sed -i 's/^#maxsize.*/maxsize 50M/' /etc/logrotate.conf
    if ! grep -q "maxsize 50M" /etc/logrotate.conf; then
        echo "maxsize 50M" >> /etc/logrotate.conf
    fi
fi

# Mark fixes as completed
echo "Post-extraction fixes applied on $(date)" > /etc/droidspaces
EOF_RUN

# Update icon and font caches in a final setup layer
RUN gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Adwaita 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Papirus 2>/dev/null || true && \
    gtk-update-icon-cache -f /usr/share/icons/Tango 2>/dev/null || true && \
    fc-cache -fv

# GPU drivers. The container uses the host's GPU through the distro's own Mesa,
# so there is nothing to bridge: start it with --gpu or --hw-access (see README).
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    libgl1-mesa-dri libglx-mesa0 libegl-mesa0 mesa-vulkan-drivers mesa-utils libgbm1 && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Final cleanup of APT cache (also drop the build-time mirror override)
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /etc/apt/apt.conf.d/80-ds-build /etc/apt/ds-build.list

# Stage 2: Export to scratch for extraction
FROM scratch AS export
LABEL droidspaces.name="Kali Linux - XFCE" \
      droidspaces.distro="Kali" \
      droidspaces.description="Kali Linux rootfs with basic packages, development tools, Docker, and XFCE desktop environment." \
      droidspaces.author="Droidspaces developers"

# Copy the entire filesystem from the customizer stage
COPY --from=customizer / /
