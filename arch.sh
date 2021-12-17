#!/usr/bin/bash

# Cleaning the TTY.
clear

# Pretty print
print () {
    echo -e "\e[1m\e[93m[ \e[92m•\e[93m ] \e[4m$1\e[0m"
}

# press any key to continue ...
press_any_key () {
    print "Press any key to continue ..."
    read -n 1 -s -r
    clear
}

print "░█████╗░██████╗░░█████╗░██╗░░██╗"
print "██╔══██╗██╔══██╗██╔══██╗██║░░██║"
print "███████║██████╔╝██║░░╚═╝███████║"
print "██╔══██║██╔══██╗██║░░██╗██╔══██║"
print "██║░░██║██║░░██║╚█████╔╝██║░░██║"
print "╚═╝░░╚═╝╚═╝░░╚═╝░╚════╝░╚═╝░░╚═╝"
print "Welcome to an easy to use, open source, and free to use,"
print "install script for Arch Linux."

# Enable parallel downloading.
sed -i 's/^#Para/Para/' /etc/pacman.conf

# syncing system datetime
timedatectl set-ntp true

# updating mirrors
pacman -Syyy

# adding fzf for making disk selection easier
pacman -S fzf --noconfirm

# open dialog for disk selection
selected_disk=$(sudo fdisk -l | grep 'Disk /dev/' | awk '{print $2,$3,$4}' | sed 's/,$//' | fzf | sed -e 's/\/dev\/\(.*\):/\1/' | awk '{print $1}')

# disk prep
sgdisk -Z /dev/"${selected_disk}" # zap all on disk
sgdisk -a 2048 -o /dev/"${selected_disk}" # new gpt disk 2048 alignment

# create partitions
sgdisk -n 1::+1M --typecode=1:ef02 --change-name=1:'BIOSBOOT' /dev/"${selected_disk}" # partition 1 (BIOS Boot Partition)
sgdisk -n 2::+100M --typecode=2:ef00 --change-name=2:'EFIBOOT' /dev/"${selected_disk}" # partition 2 (UEFI Boot Partition)
sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' /dev/"${selected_disk}" # partition 3 (Root), default start, remaining
if [[ ! -d "/sys/firmware/efi" ]]; then
    sgdisk -A 1:set:2 /dev/"${selected_disk}"
fi

# make filesystems
echo -e "\nCreating Filesystems...\n$HR"
if [[ /dev/"${selected_disk}" =~ "nvme" ]]; then
    mkfs.vfat -F32 -n "EFIBOOT" "/dev/""${selected_disk}""p2"
    mkfs.btrfs -L "ROOT" "/dev/""${selected_disk}""p3" -f
    mount -t btrfs "/dev/""${selected_disk}""p3" /mnt
else
    mkfs.vfat -F32 -n "EFIBOOT" "/dev/""${selected_disk}""2"
    mkfs.btrfs -L "ROOT" "/dev/""${selected_disk}""3" -f
    mount -t btrfs "/dev/""${selected_disk}""3" /mnt
fi

find /mnt -maxdepth 1 -print0 | xargs btrfs subvolume delete
btrfs subvolume create /mnt/@
umount /mnt

# mount target
mount -t btrfs -o subvol=@ -L ROOT /mnt
mkdir /mnt/boot
mkdir /mnt/boot/efi
mount -t vfat -L EFIBOOT /mnt/boot/

base_packages=()

# Base System Installation (pacstrap)
base_packages+=(
    "base"
    "base-devel"
    "linux"
    "linux-headers"
    "linux-firmware"
)

# Install each package with pacstrap /mnt
for package in "${base_packages[@]}"; do
    print "Installing $package"
    pacstrap /mnt "$package" --noconfirm --needed
done

print "Finished installing base system."

# generating fstab
print "Generating fstab"
genfstab -U /mnt >> /mnt/etc/fstab

if [[ ! -d "/sys/firmware/efi" ]]; then # if not UEFI
    print "Detected BIOS"
    arch-chroot /mnt grub-install --boot-directory=/mnt/boot /dev/"${selected_disk}"
fi

# enabled [multilib] repo on installed system
print "Enabling [multilib] repo"
arch-chroot /mnt zsh -c 'echo "[multilib]" >> /etc/pacman.conf'
arch-chroot /mnt zsh -c 'echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf'

# adding makepkg optimizations
print "Adding makepkg optimizations"
arch-chroot /mnt sed -i -e 's/#MAKEFLAGS="-j2"/MAKEFLAGS=-j'"$(nproc --ignore 1)"'/' -e 's/-march=x86-64 -mtune=generic/-march=native/' -e 's/xz -c -z/xz -c -z -T '"$(nproc --ignore 1)"'/' /etc/makepkg.conf
arch-chroot /mnt sed -i -e 's/!ccache/ccache/g' /etc/makepkg.conf

# updating repo status
print "Updating repo status"
arch-chroot /mnt pacman -Sy --noconfirm

# Essential Packages (pacman)
packages=()

# Display manager
packages+=(
    "xorg"
    "xorg-server"
    "xorg-drivers"
    "xorg-xkill"
    "xorg-xrandr"
    "xorg-xinit"
)

# Desktop environment
packages+=(
    "xfce4"
    "xfce4-goodies"
    "lightdm"
    "lightdm-gtk-greeter"
    "accountsservice"
)

# KDE + Plasma
# "plasma-desktop"
# "plasma-meta"
# "plasma-nm"
# "sddm"
# "sddm-kcm"
# "kdeplasma-addons"
# "i3-gaps"
# "i3status"
# "dmenu"
# "rofi"
# "compton"
# "feh"

# Base system installation
packages+=(
    "base"
    "base-devel"
    "networkmanager"
    "linux"
    "linux-headers"
    "linux-firmware"
    "os-prober"
    "efibootmgr"
    "dosftools"
    "grub"
    "grub-customizer"
    "sudo"
    "automake"
    "autoconf"
    "ccache"
    "git"
    "zsh"
    "cpupower"
    "htop"
    "cronie"
    "pulseaudio"
    "pulseaudio-alsa"
    "pulseaudio-bluetooth"
    "pamixer"
    "wget"
    "openssh"
    "zip"
    "unzip"
    "unrar"
    "man"
    "man-pages"
    "tree"
    "fzf"
    "mesa"
    "lvm2"
    "libva-mesa-driver"
    "mesa-vdpau"
    "dunst"
    "gcc"
    "make"
    "neovim"
    "nano"
    "nano-syntax-highlighting"
    "ntfs-3g"
    "kitty"
    "maim"
    "playerctl"
    "p7zip"
    "ufw"
    "bash-completion"
    "which"
    "konsole"
    "dolphin"
    "neofetch" # very essential
    "hwinfo"
    
)

# Fonts
packages+=(
    "ttf-dejavu"
    "ttf-liberation"
    "ttf-inconsolata"
    "noto-fonts"
    "gucharmap"
    "noto-fonts-emoji"
    "ttf-roboto"
    "ttf-cascadia-code"
    "ttf-opensans"
    "capitaine-cursors"
)

# Microcode
CPU=$(grep vendor_id /proc/cpuinfo)
if [[ $CPU == *"AuthenticAMD"* ]]; then
    print "An AMD CPU has been detected, the AMD microcode will be installed."
    microcode="amd-ucode"
else
    print "An Intel CPU has been detected, the Intel microcode will be installed."
    microcode="intel-ucode"
fi

arch-chroot /mnt pacman -S $microcode

# Graphics Drivers find and install
if lspci | grep -E "NVIDIA|GeForce"; then
    arch-chroot /mnt pacman -S nvidia nvidia-utils --noconfirm --needed
    nvidia-xconfig
    elif lspci | grep -E "Radeon"; then
    arch-chroot /mnt pacman -S xf86-video-amdgpu --noconfirm --needed
    elif lspci | grep -E "Integrated Graphics Controller"; then
    arch-chroot /mnt pacman -S libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils --noconfirm --needed
fi

# Virtualization Check
hypervisor=$(systemd-detect-virt)
case $hypervisor in
    kvm )   print "KVM has been detected."
        print "Installing guest tools."
        pacstrap /mnt qemu-guest-agent
        print "Enabling specific services for the guest tools."
        systemctl enable qemu-guest-agent --root=/mnt &>/dev/null
    ;;
    vmware  )   print "VMWare Workstation/ESXi has been detected."
        print "Installing guest tools."
        pacstrap /mnt open-vm-tools xf86-input-libinput xf86-video-vmware xf86-input-vmmouse
        print "Enabling specific services for the guest tools."
        systemctl enable vmtoolsd --root=/mnt &>/dev/null
        systemctl enable vmware-vmblock-fuse --root=/mnt &>/dev/null
    ;;
    oracle )    print "VirtualBox has been detected."
        print "Installing guest tools."
        pacstrap /mnt virtualbox-guest-utils
        print "Enabling specific services for the guest tools."
        systemctl enable vboxservice --root=/mnt &>/dev/null
    ;;
    microsoft ) print "Hyper-V has been detected."
        print "Installing guest tools."
        pacstrap /mnt hyperv
        print "Enabling specific services for the guest tools."
        systemctl enable hv_fcopy_daemon --root=/mnt &>/dev/null
        systemctl enable hv_kvp_daemon --root=/mnt &>/dev/null
        systemctl enable hv_vss_daemon --root=/mnt &>/dev/null
    ;;
    * ) ;;
esac

# Install each package with pacstrap /mnt
for package in "${packages[@]}"; do
    print "Installing $package"
    arch-chroot /mnt pacman -S "$package" --noconfirm --needed
done
print "Finished installing essential packages"

# setting right timezone based off location
print "Setting timezone"
arch-chroot /mnt ln -sf /usr/share/zoneinfo/"$(curl -s http://ip-api.com/line?fields=timezone)" /etc/localtime &>/dev/null

# enabling font presets for better font rendering
print "Enabling font presets"
arch-chroot /mnt ln -s /etc/fonts/conf.avail/70-no-bitmaps.conf /etc/fonts/conf.d
arch-chroot /mnt ln -s /etc/fonts/conf.avail/10-sub-pixel-rgb.conf /etc/fonts/conf.d
arch-chroot /mnt ln -s /etc/fonts/conf.avail/11-lcdfilter-default.conf /etc/fonts/conf.d
arch-chroot /mnt zsh -c "$(echo 'export FREETYPE_PROPERTIES="truetype:interpreter-version=38"' >> /etc/profile.d/freetype2.sh)"

# synchronizing timer
print "Synchronizing system clock"
arch-chroot /mnt hwclock --systohc

# localizing system
print "Localizing system"
arch-chroot /mnt sed -i -e 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/g' /etc/locale.gen
arch-chroot /mnt sed -i -e 's/#en_US ISO-8859-1/en_US ISO-8859-1/g' /etc/locale.gen

# generating locale
print "Generating locale"
arch-chroot /mnt locale-gen

# setting system language
print "Setting system language"
arch-chroot /mnt echo "LANG=en_US.UTF-8" >> /mnt/etc/locale.conf

# setting machine name
print "Setting machine name"
arch-chroot /mnt echo "archvm" >> /mnt/etc/hostname

# setting hosts file
print "Setting hosts file"
arch-chroot /mnt echo "127.0.0.1 localhost" >> /mnt/etc/hosts
arch-chroot /mnt echo "::1 localhost" >> /mnt/etc/hosts
arch-chroot /mnt echo "127.0.1.1 archvm.localdomain archvm" >> /mnt/etc/hosts

# Configuring /etc/mkinitcpio.conf.
print "Configuring /etc/mkinitcpio.conf."
arch-chroot /mnt cat > /mnt/etc/mkinitcpio.conf <<EOF
HOOKS=(base systemd autodetect keyboard sd-vconsole modconf block sd-encrypt filesystems)
COMPRESSION=(zstd)
EOF

# making sudoers do sudo stuff without requiring password typing
print "Making sudoers do sudo stuff without requiring password typing"
arch-chroot /mnt sed -i -e 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/g' /etc/sudoers

# Generating a new initramfs.
print "Creating a new initramfs."
arch-chroot /mnt sed -i -e 's/base udev/base systemd udev/g' /etc/mkinitcpio.conf
arch-chroot /mnt sed -i -e 's/block filesystems/block lvm2 filesystems/g' /etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -p linux

# setting root password
print "Setting root password"
arch-chroot /mnt sudo -u root /bin/zsh -c 'echo "Insert root password: " && read root_password && echo -e "$root_password\n$root_password" | passwd root'

# making user xminent
print "Making user xminent"
arch-chroot /mnt useradd -m -G wheel -s /bin/zsh xminent

# setting xminent password
print "Setting xminent password"
arch-chroot /mnt sudo -u root /bin/zsh -c 'echo "Insert xminent password: " && read xminent_password && echo -e "$xminent_password\n$xminent_password" | passwd xminent'


# installing grub
print "Installing grub"
if [[ -d "/sys/firmware/efi" ]]; then # if UEFI
    print "UEFI detected"
    arch-chroot /mnt grub-install --efi-directory=/boot /dev/"${selected_disk}"
fi

# creating grub config
print "Creating grub config"
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# changing governor to performance
# print "Changing governor to performance"
# arch-chroot /mnt echo "governor='performance'" >> /mnt/etc/default/cpupower

# print "Installing yay"
# arch-chroot /mnt sudo -u xminent git clone https://aur.archlinux.org/yay.git /home/xminent/yay_tmp_install
# arch-chroot /mnt sudo -u xminent /bin/zsh -c "cd /home/xminent/yay_tmp_install && yes | makepkg -si"
# arch-chroot /mnt rm -rf /home/xminent/yay_tmp_install

# userpackages=()

# userpackages+=(
#     "sddm-nordic-theme-git"
#     "kwin-bismuth"
# )

# # installing user packages
# for package in "${userpackages[@]}"; do
#     print "Installing $package"
#     arch-chroot /mnt yay -S "$package" --noconfirm --needed
# done



# making services start at boot
print "Making services start at boot"
arch-chroot /mnt systemctl enable cpupower.service

# disable dhcpd if it's installed
if [[ -f "/mnt/etc/dhcpcd.conf" ]]; then
    print "Disabling dhcpd"
    arch-chroot /mnt systemctl disable dhcpcd.service
fi

arch-chroot /mnt systemctl enable NetworkManager.service
arch-chroot /mnt systemctl enable lightdm.service
# arch-chroot /mnt systemctl enable sddm.service

# print "Setting up SDDM Theme"
# arch-chroot /mnt sudo /bin/zsh -c "cat <<EOF > /etc/sddm.conf
# [Theme]
# Current=Nordic
# EOF
# "
# press_any_key

arch-chroot /mnt systemctl enable cronie.service
arch-chroot /mnt systemctl enable sshd.service
arch-chroot /mnt systemctl enable fstrim.timer
arch-chroot /mnt systemctl enable ufw.service

# installing oh-my-zsh
# print "Installing oh-my-zsh"
# arch-chroot /mnt sudo -u xminent /bin/zsh -c 'cd ~ && curl -O https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh && chmod +x install.sh && RUNZSH=no ./install.sh && rm ./install.sh'

# create folder for screenshots
print "Creating folder for screenshots"
arch-chroot /mnt sudo -u xminent mkdir /home/xminent/Screenshots

# create pictures folder, secrets folder and moving default wallpaper
print "Creating pictures folder, secrets folder and moving default wallpaper"
arch-chroot /mnt sudo -u xminent mkdir /home/xminent/Pictures/
arch-chroot /mnt sudo -u xminent mkdir /home/xminent/.secrets/
arch-chroot /mnt sudo -u xminent mkdir /home/xminent/Pictures/wallpapers/

# Create a new file called plasma-i3.desktop in the /usr/share/xsessions directory as su.
# print "Setting up i3 and plasma to work together"
# arch-chroot /mnt sudo /bin/zsh -c "mkdir -p /usr/share/xsessions"
# arch-chroot /mnt sudo /bin/zsh -c "cat <<EOF > /usr/share/xsessions/plasma-i3.desktop
# [Desktop Entry]
# Type=XSession
# Exec=env KDEWM=/usr/bin/i3 /usr/bin/startplasma-x11 kde-splash-screen --disable
# DesktopNames=KDE
# Name=plasma-i3
# Comment=Plasma with i3
# EOF
# "
# press_any_key

# setup autologin for sddm using new session
# print "Setting up autologin for sddm"
# arch-chroot /mnt sudo /bin/zsh -c "mkdir -p /etc/sddm.conf.d"
# arch-chroot /mnt sudo /bin/zsh -c "cat <<EOF > /etc/sddm.conf.d/autologin.conf
# [Autologin]
# User=xminent
# Session=plasma-i3
# EOF
# "


# enable features on /etc/pacman.conf file
print "Enable features on /etc/pacman.conf file"
arch-chroot /mnt sed -i -e 's/#UseSyslog/UseSyslog/g' /etc/pacman.conf
arch-chroot /mnt sed -i -e 's/#Color/Color/g' /etc/pacman.conf
arch-chroot /mnt sed -i -e 's/#TotalDownload/TotalDownload/g' /etc/pacman.conf
arch-chroot /mnt sed -i -e 's/#VerbosePkgLists/VerbosePkgLists/g' /etc/pacman.conf

# unmounting all mounted partitions
print "Unmounting all mounted partitions"
umount -R /mnt

# syncing disks
print "Syncing disks"
sync

echo ""
echo "INSTALLATION COMPLETE! enjoy :)"
echo ""

sleep 3
