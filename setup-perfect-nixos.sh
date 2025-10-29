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
echo -e "${YELLOW}GPU:${NC} $(lspci | grep -i vga || echo "Tespit edilemedi (lspci için pciutils gerekebilir)")"
echo -e "\n${YELLOW}DİSKLER (lsblk):${NC}"; lsblk -f
echo -e "\n${YELLOW}DİSK KULLANIMI (df -h):${NC}"; df -h
echo -e "\n${YELLOW}AĞ BAĞLANTILARI:${NC}"; ip -br a
echo -e "\n${YELLOW}ÇALIŞAN SERVİSLER (docker, sshd, gnome):${NC}"; systemctl is-active docker sshd gdm || true

# 2. Flake dizini ve Yedekleme
FLAKE_DIR="/etc/nixos"
BACKUP_DIR="$FLAKE_DIR.backup.$(date +%s)"
mkdir -p "$BACKUP_DIR"
# Mevcut çalışan (belki bozuk) yapılandırmayı yedekle
if [ -d "$FLAKE_DIR" ] && [ "$(ls -A $FLAKE_DIR)" ]; then
    cp -r "$FLAKE_DIR"/* "$BACKUP_DIR"/ 2>/dev/null || true
    echo -e "${GREEN}Yedek alındı → $BACKUP_DIR${NC}"
else
    echo -e "${YELLOW}Uyarı: $FLAKE_DIR boş veya yok. Yedek alınmadı.${NC}"
    mkdir -p "$FLAKE_DIR"
fi

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
    # hardware-configuration.nix'in var olduğundan emin olun!
    # Eğer yoksa, 'sudo nixos-generate-config --root /' çalıştırın
    # ve oluşan hardware-configuration.nix'i /etc/nixos/ içine kopyalayın.
    ./hardware-configuration.nix

    ./modules/base.nix
    ./modules/desktop.nix
    ./modules/user.nix
    ./modules/nix.nix
    ./modules/nvidia.nix
    ./modules/hibernation.nix
  ];
  # özgür olmayan paketlere izin ver
  nixpkgs.config.allowUnfree = true;

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
    pciutils      # DÜZELTME: lspci komutu için eklendi
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

# DÜZELTME: docker.nix modülü gereksiz olduğu için kaldırıldı.
# 'docker-compose' paketini systemPackages'e eklemek yeterlidir.

# nvidia.nix
cat > "$FLAKE_DIR/modules/nvidia.nix" << 'EOF'
{ config, pkgs, ... }:

{
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
  services.xserver.videoDrivers = [ "nvidia" ];

  # DÜZELTME: Bu ayar 25.05 sürümüyle zorunlu hale geldi.
  #
  # Eğer Turing (RTX serisi, GTX 16xx) veya DAHA YENİ bir kartınız varsa 'true' yapın.
  # Daha ESKİ bir kartsa veya emin değilseniz 'false' (kapalı kaynak) olarak bırakın.
  #
  hardware.nvidia.open = false;

  # Örnek: (Eğer yeni bir kartınız varsa 'false' satırını silip bu satırın başındaki # işaretini kaldırın)
  # hardware.nvidia.open = true;
}
EOF

# hibernation.nix
cat > "$FLAKE_DIR/modules/hibernation.nix" << 'EOF'
{ lib, pkgs, ... }: # DÜZELTME: 'pkgs' eklendi

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
find "$FLAKE_DIR" -type f -name "*.nix" -exec chmod 644 {} \;

# 5. Yeniden derle
echo -e "${GREEN}NixOS yeniden derleniyor...${NC}"

# ÖNEMLİ: Eğer hardware-configuration.nix yoksa bu adım başarısız olur.
if [ ! -f "$FLAKE_DIR/hardware-configuration.nix" ]; then
    echo -e "${RED}HATA: /etc/nixos/hardware-configuration.nix bulunamadı!${NC}"
    echo -e "${YELLOW}Lütfen önce 'sudo nixos-generate-config --root /' çalıştırın,"
    echo -e "ve oluşan hardware-configuration.nix'i /etc/nixos/ dizinine taşıyın.${NC}"
    exit 1
fi

nixos-rebuild switch --flake "$FLAKE_DIR#nixos-acb" --show-trace

# 6. dev-env setup.sh düzelt
# DÜZELTME: Step 6 (docker plugin) gereksiz olduğu için kaldırıldı. Bu artık Step 6.
# DÜZELTME: $HOME yerine /home/acb kullanıldı.
DEV_ENV="/home/acb/Masaüstü/Docker-havuz/dev-env"
if [ -f "$DEV_ENV/setup.sh" ]; then
  sed -i 's/docker-compose up/docker compose up/g' "$DEV_ENV/setup.sh"
  chown acb:users "$DEV_ENV/setup.sh" # İzinlerin doğru olduğundan emin ol
  chmod +x "$DEV_ENV/setup.sh"
  echo -e "${GREEN}setup.sh güncellendi ($DEV_ENV/setup.sh)${NC}"
else
  echo -e "${YELLOW}Uyarı: $DEV_ENV/setup.sh bulunamadı. Atlantı.${NC}"
fi

# 7. TAMAM!
echo -e "${GREEN}
MÜKEMMEL NIXOS HAZIR!
====================
Sistem: $(nixos-version)
Docker: $(docker --version)
Compose: $(docker compose version 2>/dev/null || echo "docker compose plugin aktif")
Disk: lsblk ile gösterildi

ŞİMDİ:
  1. sudo reboot
  2. cd /home/acb/Masaüstü/Docker-havuz/dev-env
  3. ./setup.sh → dev-env BAŞLASIN!

http://localhost:8080 → Code Server
http://localhost:8081 → Nexus
http://localhost:3000 → Forgejo
${NC}"