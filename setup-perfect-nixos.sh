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

# 2. SİSTEM TEMİZLEME (hardware-configuration.nix korunur)
echo -e "\n${GREEN}SİSTEM TEMİZLENİYOR (hardware-configuration.nix korunacak)...${NC}"
FLAKE_DIR="/etc/nixos"

# En önemli dosyanın (hardware-configuration.nix) var olduğundan emin olalım.
if [ ! -f "$FLAKE_DIR/hardware-configuration.nix" ]; then
    echo -e "${RED}HATA: $FLAKE_DIR/hardware-configuration.nix bulunamadı!${NC}"
    echo -e "${YELLOW}Lütfen önce 'sudo nixos-generate-config --root /' ile bu dosyayı oluşturun.${NC}"
    echo -e "${YELLOW}Dosya yoksa, bu script /etc/nixos dizinini temizleyemez veya kuramaz.${NC}"
    
    # Eğer dizin hiç yoksa, oluşturalım
    mkdir -p "$FLAKE_DIR"
    exit 1
else
    echo "Temizleme işlemi başlıyor..."
    
    # 1. Tüm eski yapılandırmayı .ESKI dizinine taşı
    # (Script zaten root, 'sudo' gereksiz)
    mv "$FLAKE_DIR" /etc/nixos.ESKI
    
    # 2. Temiz bir /etc/nixos dizini oluştur
    mkdir "$FLAKE_DIR"
    
    # 3. Sadece hayati önem taşıyan donanım dosyasını geri taşı
    mv /etc/nixos.ESKI/hardware-configuration.nix "$FLAKE_DIR/"
    
    # 4. Artık ihtiyaç duyulmayan .ESKI dizinini sil
    rm -rf /etc/nixos.ESKI
    
    # 5. Soruna neden olan tüm eski .backup dizinlerini sil
    rm -rf /etc/nixos.backup.*
    
    echo -e "\n${GREEN}TEMİZLİK BAŞARILI!${NC}"
    echo "$FLAKE_DIR dizini temizlendi ve sadece 'hardware-configuration.nix' korundu."
fi


# 3. MÜKEMMEL FLAKE YAPISI OLUŞTUR
echo -e "\n${GREEN}MÜKEMMEL FLAKE YAPISI KURULUYOR...${NC}"

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
    # (Temizleme adımı bu dosyayı korudu)
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

  # --- YENİ EKLENEN UEFI AYARLARI ---
  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;           # UEFI modunu etkinleştir
  boot.loader.grub.efiInstallAsRemovable = true; # Çıkarılabilir medya yolu kullan (/EFI/BOOT/BOOTX64.EFI)
  boot.loader.grub.devices = [ "nodev" ];        # UEFI için diski belirtme ("nodev" kullan)
  boot.loader.efi.canTouchEfiVariables = false;  # UEFI NVRAM'a dokunma (efiInstallAsRemovable=true ile uyumlu)
  boot.loader.systemd-boot.enable = false;        # GRUB kullanıyorsak systemd-boot'u kapat
  # ------------------------------------

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

# nvidia.nix
cat > "$FLAKE_DIR/modules/nvidia.nix" << 'EOF'
{ config, pkgs, ... }:

{
  hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.stable;
  services.xserver.videoDrivers = [ "nvidia" ];

  # DÜZELTME: Bu ayar 25.05 sürümüyle zorunlu hale geldi.
  hardware.nvidia.open = false;
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
echo -e "\n${GREEN}NixOS yeniden derleniyor...${NC}"

# (Bu kontrol artık gereksiz çünkü Adım 2'de yapıldı, ama zararı yok)
if [ ! -f "$FLAKE_DIR/hardware-configuration.nix" ]; then
    echo -e "${RED}HATA: $FLAKE_DIR/hardware-configuration.nix bulunamadı!${NC}"
    exit 1
fi

nixos-rebuild switch --flake "$FLAKE_DIR#nixos-acb" --show-trace

# 6. dev-env setup.sh düzelt
echo -e "\n${GREEN}Geliştirici ortamı ayarlanıyor...${NC}"
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
echo -e "\n${GREEN}
MÜKEMMEL NIXOS HAZIR!
====================
Sistem: $(nixos-version)
Docker: $(docker --version)
Compose: $(docker compose version 2>/dev/null || echo "docker compose plugin aktif")

ŞİMDİ:
  1. sudo reboot
  2. cd /home/acb/Masaüstü/Docker-havuz/dev-env
  3. ./setup.sh → dev-env BAŞLASIN!

http://localhost:8080 → Code Server
http://localhost:8081 → Nexus
http://localhost:3000 → Forgejo
${NC}"