#!/usr/bin/env bash
set -euo pipefail

echo "MÜKEMMEL NIXOS FLAKE SİSTEMİ KURULUYOR..."
echo "=========================================="

# Root kontrol
if [[ $EUID -ne 0 ]]; then
   echo "Root gerekli: sudo $0"
   exit 1
fi

# Renkler
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# 1. SİSTEM BİLGİSİ (MÜKEMMEL)
echo -e "${GREEN}SİSTEM ANALİZİ${NC}"
echo "================"
echo -e "${YELLOW}NixOS Sürümü:${NC} $(nixos-version)"
echo -e "${YELLOW}Hostname:${NC} $(hostname)"
echo -e "${YELLOW}Kernel:${NC} $(uname -r)"
echo -e "${YELLOW}CPU:${NC} $(lscpu | grep "Model name" | awk -F: '{print $2}' | xargs)"
echo -e "${YELLOW}RAM:${NC} $(free -h | awk '/^Mem:/ {print $2}') toplam"
echo -e "${YELLOW}GPU:${NC} $(lspci | grep -i vga || echo "Tespit edilemedi")"

echo -e "\n${YELLOW}DİSKLER (lsblk):${NC}"
lsblk -f

echo -e "\n${YELLOW}DİSK KULLANIMI (df -h):${NC}"
df -h

echo -e "\n${YELLOW}AĞ BAĞLANTILARI:${NC}"
ip -br a

echo -e "\n${YELLOW}ÇALIŞAN SERVİSLER (docker, sshd, gnome):${NC}"
systemctl is-active docker sshd gdm || true

# 2. Flake dizini
FLAKE_DIR="/etc/nixos"
BACKUP_DIR="$FLAKE_DIR.backup.$(date +%s)"
mkdir -p "$BACKUP_DIR"
cp -r "$FLAKE_DIR"/* "$BACKUP_DIR"/ 2>/dev/null || true
echo -e "${GREEN}Yedek alındı → $BACKUP_DIR${NC}"

# 3. MÜKEMMEL FLAKE YAPISI OLUŞTUR
echo -e "${GREEN}MÜKEMMEL FLAKE YAPISI KURULUYOR...${NC}"

cat > "$FLAKE_DIR/flake.nix" << 'EOF'
{
  description = "nixos-acb - Mükemmel Docker + dev-env";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs, ... }:
    let system = "x86_64-linux"; in
    {
      nixosConfigurations.nixos-acb = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ ./configuration.nix ];
      };
    };
}
EOF

cat > "$FLAKE_DIR/configuration.nix" << 'EOF'
{ config, pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./modules/base.nix
    ./modules/desktop.nix
    ./modules/docker.nix
    ./modules/user.nix
    ./modules/nix.nix
    ./modules/nvidia.nix
    ./modules/hibernation.nix
  ];

  system.stateVersion = "25.05";
}
EOF

mkdir -p "$FLAKE_DIR/modules"

# base.nix
cat > "$FLAKE_DIR/modules/base.nix" << 'EOF'
{ pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    curl wget git vim htop tree unzip
    docker-compose  # v2
    lazydocker
  ];

  virtualisation.docker.enable = true;

  networking.hostName = "nixos-acb";
  time.timeZone = "Europe/Istanbul";
  i18n.defaultLocale = "tr_TR.UTF-8";

  # Sistem genelinde font cache
  fonts.fontconfig.defaultFonts = {
    serif = [ "Noto Serif" ];
    sansSerif = [ "Noto Sans" ];
    monospace = [ "Fira Code" ];
  };
}
EOF

# desktop.nix
cat > "$FLAKE_DIR/modules/desktop.nix" << 'EOF'
{ pkgs, ... }:

{
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
}
EOF

# user.nix
cat > "$FLAKE_DIR/modules/user.nix" << 'EOF'
{ pkgs, ... }:

{
  users.users.acb = {
    isNormalUser = true;
    home = "/home/acb";
    description = "Ana kullanıcı";
    extraGroups = [ "wheel" "dbus" "docker" "networkmanager" "video" ];

    # KULLANICIYA ÖZEL PAKETLER (senin eskiden kullandıkların)
    packages = with pkgs; [
      # Tarayıcılar
      brave
      firefox

      # GNOME eklentileri
      gnome-tweaks
      gnomeExtensions.dash-to-dock
      gnomeExtensions.appindicator

      # Dosya yöneticisi eklentileri
      file-roller
      nautilus

      # Medya
      vlc
      eog
      gedit

      # Geliştirme & Yardımcı
      git
      wget
      curl
      unzip
      htop
      tree
      ntfs3g
      anydesk
      lazydocker

      # Python (code-server için)
      python3
      python3Packages.pip
    ];
  };

  # YAZI TİPLERİ (kullanıcıya özel, ama sistem genelinde de görünür)
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-emoji
    liberation_ttf
    fira-code
    fira-code-symbols
    corefonts
    font-awesome
  ];
}
EOF

# docker.nix (SADECE PLUGIN)
cat > "$FLAKE_DIR/modules/docker.nix" << 'EOF'
{ pkgs, ... }:

{
  systemd.services.setup-docker-compose-plugin = {
    description = "Docker Compose CLI Plugin";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.User = "acb";
    script = ''
      mkdir -p "$HOME/.docker/cli-plugins"
      [ ! -f "$HOME/.docker/cli-plugins/docker-compose" ] && \
        ln -sf ${pkgs.docker-compose}/bin/docker-compose "$HOME/.docker/cli-plugins/docker-compose"
    '';
  };
}
EOF

# nvidia.nix
cat > "$FLAKE_DIR/modules/nvidia.nix" << 'EOF'
{ pkgs, ... }:

{
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
  services.xserver.videoDrivers = [ "nvidia" ];
}
EOF

# hibernation.nix
cat > "$FLAKE_DIR/modules/hibernation.nix" << 'EOF'
{ lib, ... }:

{
  powerManagement.resumeCommands = "${lib.getBin pkgs.systemd}/bin/systemctl --no-block restart display-manager.service";
}
EOF

# nix.nix
cat > "$FLAKE_DIR/modules/nix.nix" << 'EOF'
{ ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
EOF

# 4. Dosya izinleri
chown -R root:root "$FLAKE_DIR"
find "$FLAKE_DIR" -name "*.nix" -exec chmod 644 {} \;

# 5. Yeniden derle
echo -e "${GREEN}NixOS yeniden derleniyor...${NC}"
nixos-rebuild switch --flake "$FLAKE_DIR#nixos-acb" --show-trace || {
  echo -e "${RED}HATA! Geri alınıyor...${NC}"
  cp -r "$BACKUP_DIR"/* "$FLAKE_DIR"/
  nixos-rebuild switch --rollback
  exit 1
}

# 6. Docker plugin’i kullanıcıya kur
echo -e "${GREEN}Docker Compose plugin'i kuruluyor...${NC}"
sudo -u acb bash -c '
  mkdir -p ~/.docker/cli-plugins
  ln -sf $(which docker-compose) ~/.docker/cli-plugins/docker-compose 2>/dev/null || true
'

# 7. dev-env setup.sh düzelt
DEV_ENV="$HOME/acb/Masaüstü/Docker-havuz/dev-env"
if [ -f "$DEV_ENV/setup.sh" ]; then
  sed -i 's/docker-compose up/docker compose up/g' "$DEV_ENV/setup.sh"
  chmod +x "$DEV_ENV/setup.sh"
  echo -e "${GREEN}setup.sh güncellendi${NC}"
fi

# 8. TAMAM!
echo -e "${GREEN}
MÜKEMMEL NIXOS HAZIR!
====================
Sistem: $(nixos-version)
Docker: $(docker --version)
Compose: $(docker compose version 2>/dev/null || echo "kuruluyor...")
Disk: lsblk ile gösterildi

ŞİMDİ:
  1. sudo reboot
  2. cd ~/Masaüstü/Docker-havuz/dev-env
  3. ./setup.sh → dev-env BAŞLASIN!

http://localhost:8080 → Code Server
http://localhost:8081 → Nexus
http://localhost:3000 → Forgejo
${NC}"
