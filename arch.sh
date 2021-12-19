#!/usr/bin/bash

# cleaning the TTY.
clear

# pretty print
print () {
    echo -e "\e[1m\e[93m[ \e[92m•\e[93m ] \e[4m$1\e[0m"
}

# press any key to continue ...
press_any_key () {
    print "Press any key to continue ..."
    read -n 1 -s -r
    clear
}

# username prompt
username_prompt () {
    print "Enter your username: "
    read -r username
    # check if the username is a valid username
    if ! [[ $username =~ ^[a-z_][a-z0-9_-]*$ ]]
    then
        print "The username you entered is not a valid username."
        username_prompt
    fi
}

print "░█████╗░██████╗░░█████╗░██╗░░██╗"
print "██╔══██╗██╔══██╗██╔══██╗██║░░██║"
print "███████║██████╔╝██║░░╚═╝███████║"
print "██╔══██║██╔══██╗██║░░██╗██╔══██║"
print "██║░░██║██║░░██║╚█████╔╝██║░░██║"
print "╚═╝░░╚═╝╚═╝░░╚═╝░╚════╝░╚═╝░░╚═╝"
print "Welcome to an easy to use, open source, and free to use,"
print "install script for Arch Linux."

# enable parallel downloading.
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

# base system installation (pacstrap)
base_packages+=(
    "base"
    "base-devel"
    "linux"
    "linux-headers"
    "linux-firmware"
)

# install each package with pacstrap /mnt
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

# ask the user for their desired desktop environment
print "Please select your desired desktop environment:"
print "1. KDE Plasma"
print "2. XFCE"
print "3. None (you want an install without a desktop environment)"

# set the user's choice of desktop environment
read -rp "Enter your choice [1-3]: " de_choice

# essential packages (pacman)
packages=()

# display manager
packages+=(
    "xorg"
    "xorg-server"
    "xorg-drivers"
    "xorg-xkill"
    "xorg-xrandr"
    "xorg-xinit"
)

case "${de_choice}" in
    1)
        # install kde plasma
        print "Installing KDE Plasma"
        packages+=(
            "plasma-meta"
            "plasma-desktop"
            "plasma-nm"
        )
        desktop_env="kde"
        ;;
    # case 2: xfce
    2)
        # install xfce
        print "Installing XFCE"
        packages+=(
            "xfce4"
            "xfce4-goodies"
        )
        desktop_env="xfce"
        ;;
    3)
        # no desktop environment
        desktop_env="none"
        ;;
    *)
        # default to kde plasma
        packages+=(
            "plasma-meta"
            "plasma-desktop"
            "plasma-nm"
        )
        ;;
esac

# greeter and display manager
# "lightdm"
#     "lightdm-gtk-greeter"
#     "lightdm-gtk-greeter-settings"
#     "accountsservice"

# if desktop_env is not equal to "none"
if [[ "${desktop_env}" != "none" ]]; then
    packages+=(
        "sddm"
        "picom"
    )
fi

# base system installation
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

languages
packages+=(
    "ruby"
    "nodejs"
    "python"
    "python-pip"
    "go"
    "crystal"
    "php"
    "jre-openjdk-headless"
)

# fonts
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

# microcode
CPU=$(grep vendor_id /proc/cpuinfo)
if [[ $CPU == *"AuthenticAMD"* ]]; then
    print "An AMD CPU has been detected, the AMD microcode will be installed."
    microcode="amd-ucode"
else
    print "An Intel CPU has been detected, the Intel microcode will be installed."
    microcode="intel-ucode"
fi

arch-chroot /mnt pacman -S $microcode --noconfirm --needed

# graphics drivers find and install
if lspci | grep -E "NVIDIA|GeForce"; then
    arch-chroot /mnt pacman -S nvidia nvidia-utils --noconfirm --needed
    nvidia-xconfig
    elif lspci | grep -E "Radeon"; then
    arch-chroot /mnt pacman -S xf86-video-amdgpu --noconfirm --needed
    elif lspci | grep -E "Integrated Graphics Controller"; then
    arch-chroot /mnt pacman -S libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils --noconfirm --needed
fi

# virtualization check
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

# install each package with pacstrap /mnt
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
arch-chroot /mnt zsh -c 'echo "export FREETYPE_PROPERTIES='truetype:interpreter-version=38'" >> /etc/profile.d/freetype2.sh)'

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
# print "Setting hosts file"
# arch-chroot /mnt echo "127.0.0.1 localhost" >> /mnt/etc/hosts
# arch-chroot /mnt echo "::1 localhost" >> /mnt/etc/hosts
# arch-chroot /mnt echo "127.0.1.1 archvm.localdomain archvm" >> /mnt/etc/hosts
{
    arch-chroot /mnt echo "127.0.0.1 localhost" 
    arch-chroot /mnt echo "::1 localhost"
    arch-chroot /mnt echo "127.0.1.1 archvm.localdomain archvm"
} >> /mnt/etc/hosts

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
print "Enter root password: "
read -r root_password
arch-chroot /mnt sudo -u root /bin/zsh -c "echo -e ""$root_password$(printf '\n')$root_password"" | passwd root"

# prompt the user for a username
username_prompt

# making user $username
print "Making user $username"
arch-chroot /mnt useradd -m -G wheel -s /bin/zsh "$username"

# setting $username password
print "Enter password for $username: "
read -r user_password
arch-chroot /mnt sudo -u root /bin/zsh -c "echo -e ""$user_password$(printf '\n')$user_password"" | passwd $username"

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

print "Installing yay"
arch-chroot /mnt sudo -u "$username" git clone https://aur.archlinux.org/yay.git /home/"$username"/yay_tmp_install
arch-chroot /mnt sudo -u "$username" /bin/zsh -c "cd /home/$username/yay_tmp_install && yes | makepkg -si"
arch-chroot /mnt rm -rf /home/"$username"/yay_tmp_install

userpackages=()

userpackages+=(
    "papirus-icon-theme-git"
    "nerd-fonts-fira-code"
    "shell-color-scripts"
)

# installing user packages
for package in "${userpackages[@]}"; do
    print "Installing $package"
    arch-chroot /mnt sudo -u "$username" /bin/zsh -c "yay -S $package --noconfirm --needed"
    press_any_key
done

# making services start at boot
print "Making services start at boot"
arch-chroot /mnt systemctl enable cpupower.service

# disable dhcpd if it's installed
if [[ -f "/mnt/etc/dhcpcd.conf" ]]; then
    print "Disabling dhcpd"
    arch-chroot /mnt systemctl disable dhcpcd.service
fi

arch-chroot /mnt systemctl enable NetworkManager.service

# check if desktop_env is not "none"
if [[ $desktop_env != "none" ]]; then
    # arch-chroot /mnt systemctl enable lightdm.service
    arch-chroot /mnt systemctl enable sddm.service
fi

arch-chroot /mnt systemctl enable cronie.service
arch-chroot /mnt systemctl enable sshd.service
arch-chroot /mnt systemctl enable fstrim.timer
arch-chroot /mnt systemctl enable ufw.service

# installing oh-my-zsh
print "Installing oh-my-zsh"
arch-chroot /mnt sudo -u "$username" /bin/zsh -c 'cd ~ && curl -O https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh && chmod +x install.sh && RUNZSH=no ./install.sh && rm ./install.sh'

# installing powerlevel10k
print "Installing powerlevel10k"
arch-chroot /mnt sudo -u "$username" /bin/zsh -c "cd ~ && git clone https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k"

press_any_key

# install zsh-autosuggestions
print "Installing zsh-autosuggestions"

arch-chroot /mnt sudo -u "$username" /bin/zsh -c "cd ~ && git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"

# install zsh-syntax-highlighting
print "Installing zsh-syntax-highlighting"
arch-chroot /mnt sudo -u "$username" /bin/zsh -c "cd ~ && git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"

# install colorls with ruby
print "Installing colorls with ruby"

# install colorls
arch-chroot /mnt sudo -u "$username" /bin/zsh -c "cd ~ && gem install colorls"

# git clone the dotfiles
print "Cloning dotfiles"
arch-chroot /mnt sudo -u "$username" /bin/zsh -c "cd ~ && git clone https://github.com/$username/arch.git"
# copy dotfiles to home directory
print "Copying dotfiles to home directory"
arch-chroot /mnt sudo -u "$username" /bin/zsh -c "cd ~ && cp -r arch/. ~/"

# create folder for screenshots
print "Creating folder for screenshots"
arch-chroot /mnt sudo -u "$username" mkdir /home/"$username"/Screenshots

# create pictures folder, secrets folder, and wallpapers folder
print "Creating pictures folder, secrets folder and wallpaper folder"
arch-chroot /mnt sudo -u "$username" mkdir /home/"$username"/Pictures/
arch-chroot /mnt sudo -u "$username" mkdir /home/"$username"/.secrets/
arch-chroot /mnt sudo -u "$username" mkdir /home/"$username"/Pictures/wallpapers/

# enable features on /etc/pacman.conf file
print "Enable features on /etc/pacman.conf file"
arch-chroot /mnt sed -i -e 's/#UseSyslog/UseSyslog/g' /etc/pacman.conf
arch-chroot /mnt sed -i -e 's/#Color/Color/g' /etc/pacman.conf
arch-chroot /mnt sed -i -e 's/#TotalDownload/TotalDownload/g' /etc/pacman.conf
arch-chroot /mnt sed -i -e 's/#VerbosePkgLists/VerbosePkgLists/g' /etc/pacman.conf

# unload the pcspkr module
print "Blacklist the pcspkr module"
arch-chroot /mnt sudo /bin/zsh -c 'echo "blacklist pcspkr" >> /etc/modprobe.d/nobeep.conf'

if [ $desktop_env == "kde" ]; then
    # install konsave using pip
    print "Installing konsave using pip"
    arch-chroot /mnt sudo -u "$username" /bin/zsh -c 'pip install konsave'
    # import konsave profile
    print "Importing konsave profile"
    arch-chroot /mnt sudo -u "$username" /bin/zsh -c "konsave -i ~/$username.knsv"
    sleep 1
    # apply the profile
    print "Applying the profile"
    arch-chroot /mnt sudo -u "$username" /bin/zsh -c "konsave -a $username"
fi

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
