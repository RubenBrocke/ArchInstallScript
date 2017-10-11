#! /bin/bash
# ROOT REQUIRED
# File: `curl https://ptpb.pw -F c=@PATH_TO_FILE`. Output: `COMMAND | curl https://ptpb.pw -F c=@-`.
if [[ -z $1 ]]; then
    #If previous install fucked up umount the partitions
    umount -l /mnt/boot
	umount -l /mnt
	clear && lsblk
	echo "Select the drive you want to install Linux on e.g. \"sda\" or \"sdb\" without the quotes."
	read drive && clear
	#Check if system is booted via BIOS or UEFI mode
	ls /sys/firmware/efi/efivars/
	if [[ $? = 2 ]]; then #if file not found
		ISEFI=0
	else
		ISEFI=1
	fi
	clear
	if [[ $ISEFI = 0 ]]; then
		echo "This computer is booted in BIOS mode, if this is correct press ENTER to continue. You likely have UEFI with Legacy Mode enabled, enable UEFI booting if this is the case"
	else
		echo "This computer is booted in UEFI mode, this is normal, but keep in mind that a lot of companies suck at implementing UEFI so you should make sure you're using the newest version of it. Look up your motherboard vendor page, it's likely going to be incorrectly under \"BIOS\". Press ENTER to continue."
	fi
	read && clear

	echo "How would you like to name this computer?"
	read hostname && clear
	echo "What password should the root(administrator) account have?"
	read rootpassword && clear
	echo "What username do you want? Linux only allows lower case letters and numbers by default."
	read username && clear
	echo "What password should your user have? (It is bad practice to use the root account for daily use, and some graphical programs will refuse to work under it or they'll be broken)"
	read userpassword && clear
	timezone=$(tzselect) && clear
	echo "Do you want to install a Desktop Environment? This is required if you want a graphical interface(This script uses Cinnamon). You can of course install some DE later. Answer \"yes\" without quotes if yes."
	read answerDE && clear
	echo "Do you want to install a browser(Firefox) and useful utilities(Audio control etc.)? Answer \"yes\" without quotes if yes."
	read answerUTILS && clear
	echo "Do you want to install latest Nvidia proprietary drivers? Answer \"yes\" without quotes if yes. (You likely want this if you have an Nvidia card from the last few years)"
	read answerNVIDIA && clear
	echo "Do you want to install the Intel proprietary driver? Answer \"yes\" without quotes if yes. This is only useful if you have a laptop card with integrated Intel GPU and you know the open-source driver is not good for your usage."
	read answerINTEL && clear

	#BIOS BLOCK
	if [[ $ISEFI = 0 ]]; then
		echo "Do you want to select an already created partition? If you choose not to do so, the drive $drive will be wiped(drive, NOT partition!!) and used for this Arch installation. Answer \"yes\" without quotes if yes. If you type anything else than \"yes\" it will be taken as a no and your whole drive WILL BE WIPED!!"
		read answer && clear
		if [[ $answer = "yes" ]]; then
			lsblk
			echo && echo "Which partition should be used? e.g. \"sda3\""
			read partition
			mkfs.btrfs /dev/$partition -f
			mount -o compress=lzo /dev/$partition /mnt
		else
			parted -s /dev/$drive mklabel msdos
			parted -s /dev/$drive mkpart primary btrfs 1MiB 100%
			parted -s /dev/$drive set 1 boot on
			mkfs.btrfs /dev/${drive}1 -f
			mount -o compress=lzo /dev/${drive}1 /mnt
		fi
	fi

	#UEFI BLOCK
	if [[ $ISEFI = 1 ]]; then
		clear && echo "Do you want to select already created partitions(ESP+data)? If you choose not to do so, the drive $drive will be wiped and used for this Arch installation. Answer \"yes\" without quotes if yes. If you type anything else than \"yes\" it will be taken as a no and your whole drive WILL BE WIPED!!"
		read answer && clear
		if [[ $answer = "yes" ]]; then
			lsblk
			echo &&	echo "Which partition should be used for root(data partition)? e.g. \"sda2\""
			read ROOTpartition && clear
			mkfs.btrfs /dev/${ROOTpartition} -f
			mount -o compress=lzo /dev/${ROOTpartition} /mnt
			lsblk
			echo "Which ESP(EFI) partition should be used? e.g. \"sda1\""
			read ESPpartition && clear
			mkdir -p /mnt/boot
			mount /dev/$ESPpartition /mnt/boot
			clear
		else
			parted -s /dev/$drive mklabel gpt
			parted -s /dev/$drive mkpart ESP fat32 1MiB 513MiB
			parted -s /dev/$drive set 1 boot on
			parted -s /dev/$drive mkpart primary btrfs 513MiB 100%
			mkfs.btrfs /dev/${drive}2 -f
			mkfs.fat -F32 /dev/${drive}1
			mount -o compress=lzo /dev/${drive}2 /mnt
			mkdir -p /mnt/boot
			mount /dev/${drive}1 /mnt/boot
			ESPpartition=${drive}1
			ROOTpartition=${drive}2
		fi
	fi

	#MAIN BLOCK
	pacstrap -i /mnt base base-devel --noconfirm
	genfstab -U /mnt > /mnt/etc/fstab
	cp $BASH_SOURCE /mnt/root
	arch-chroot /mnt /bin/bash -c "/root/\"$BASH_SOURCE\" \"$hostname\" \"$rootpassword\" \"$username\" \"$userpassword\" \"$timezone\" \"$ISEFI\" \"$drive\" \"$answerDE\" \"$answerUTILS\" \"$ESPpartition\" \"$ROOTpartition\" \"$answerNVIDIA\" \"$answerINTEL\""
fi
if [[ -z $1 ]]; then #If we're in chroot then... $1 is only set after chrooting
	echo
else
	#CHROOT PART
	hostname="$1"
	rootpassword="$2"
	username="$3"
	userpassword="$4"
	timezone="$5"
	ISEFI="$6"
	drive="$7"
	answerDE="$8"
	answerUTILS="$9"
	ESPpartition="${10}"
	ROOTpartition="${11}"
	answerNVIDIA="${12}"
	answerINTEL="${13}"


	echo "Assuming you want English language..."
	echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
	locale-gen
	echo "LANG=en_US.UTF-8" > /etc/locale.conf && clear
	ln -sf /usr/share/zoneinfo/$timezone /etc/localtime 
	hwclock --systohc --utc
	echo $hostname > /etc/hostname
	systemctl enable dhcpcd
	echo "root:$rootpassword" | chpasswd

	#ADD USER
	useradd -m -G wheel -s /bin/zsh $username
	echo "$username:$userpassword" | chpasswd
	echo "$username ALL=(ALL) ALL" >> /etc/sudoers

	#Enable multilib #TODO oneliner
	cp /etc/pacman.conf /etc/pacman.confbackup
	perl -0pe 's/#\[multilib]\n#/[multilib]\n/' /etc/pacman.confbackup > /etc/pacman.conf
	rm /etc/pacman.confbackup
	#sed -i s/"#\[multilib\]\\n#"/"\[multilib\]\n"/g /etc/pacman.conf

	#UEFI BLOCK
	if [[ $ISEFI = 1 ]]; then
		#pacman -Syu refind-efi --noconfirm
		#refind-install
		# EDIT: was it just my stupidity... or does Refind just suck with Windows already preinstalled.

		#using systemd-boot instead of rEFInd...
		bootctl install
		echo "default arch" > /boot/loader/loader.conf
		echo "timeout 5" >> /boot/loader/loader.conf
		echo "editor 0" >> /boot/loader/loader.conf

		echo "title Arch Linux" >  /boot/loader/entries/arch.conf
		echo "linux /vmlinuz-linux" >> /boot/loader/entries/arch.conf
		echo "initrd /initramfs-linux.img" >> /boot/loader/entries/arch.conf
		echo "options root=PARTUUID=$(blkid -s PARTUUID -o value /dev/${ROOTpartition}) rw" >> /boot/loader/entries/arch.conf
	fi

	#BIOS BLOCK
	if [[ $ISEFI = 0 ]]; then
		pacman -Syu grub os-prober --noconfirm
		grub-install --target=i386-pc /dev/$drive
		grub-mkconfig -o /boot/grub/grub.cfg
	fi

	#WI-FI SUPPORT
	pacman -Syu iw wpa_supplicant dialog --noconfirm

	#HEADLESS SETUP
	pacman -Syu screenfetch openssh htop git zsh wget noto-fonts noto-fonts-cjk noto-fonts-emoji bmon rsync unrar p7zip mc dmidecode nmap dnsutils lshw testdisk ncdu bridge-utils sane --noconfirm
	#set makeflags to number of threads - speeds up compiling PKGBUILDs
	sed -i s/"\#MAKEFLAGS=\"-j2\""/"MAKEFLAGS=\"-j\$(nproc)\""/g /etc/makepkg.conf

	#Setup cower for pacaur
	cd /tmp
	pacman -Syu yajl expac --noconfirm
	source /etc/profile
	sudo -u $username gpg --recv-keys --keyserver hkp://pgp.mit.edu 1EB2638FF56C0C53
	wget https://aur.archlinux.org/cgit/aur.git/snapshot/cower.tar.gz
	gunzip cower.tar.gz && tar xvf cower.tar &&	cd cower
	chown $username:$username ./ -R
	sudo -u $username makepkg
	pacman -U *.tar.xz --noconfirm
	#Setup pacaur
	wget https://aur.archlinux.org/cgit/aur.git/snapshot/pacaur.tar.gz
	gunzip pacaur.tar.gz &&	tar xvf pacaur.tar && cd pacaur
	chown $username:$username ./ -R
	sudo -u $username makepkg
	pacman -U *.tar.xz --noconfirm
	
	#Setup Oh-my-zsh
	wget https://github.com/robbyrussell/oh-my-zsh/raw/master/tools/install.sh -O - | zsh #Install for root
	#Set theme to classyTouch
	sed -i s/robbyrussell/"classyTouch"/g /root/.zshrc 
	#Install Oh-my-zsh for the regular user
	cp -r /root/.oh-my-zsh /home/$username/.oh-my-zsh
	echo "source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" >> /root/.zshrc
	cp /root/.zshrc /home/$username/.zshrc
	chown $username:$username /home/$username/.oh-my-zsh
	chown $username:$username /home/$username/.zshrc
	sed -i s/root/"home\/$username"/g /home/$username/.zshrc
  git clone https://github.com/yarisgutierrez/classyTouch_oh-my-zsh.git /home/$username/.oh-my-zsh/themes

	if [[ $answerDE = "yes" ]]; then
		pacman -Syu xorg xorg-xinit networkmanager --noconfirm
    pacaur -Syu i3-gaps-next-git --noconfirm 

		echo "exec cinnamon-session" > /home/$username/.xinitrc
		#systemctl enable gdm #TODO add some DM
		systemctl enable NetworkManager
	fi

	#Install Nvidia proprietary drivers 
	if [[ $answerNVIDIA = "yes" ]]; then
		pacman -Syu nvidia nvidia-libgl lib32-nvidia-libgl nvidia-settings opencl-nvidia --noconfirm
	fi

	#Install Intel proprietary drivers 
	if [[ $answerINTEL = "yes" ]]; then
		pacman -Syu xf86-video-intel --noconfirm
	fi

	if [[ $answerUTILS = "yes" ]]; then
		#PERSONAL BLOAT SETUP
		pacman -Syu --noconfirm urxvt aircrack-ng amarok btrfs-progs calibre chromium dnsmasq dosfstools ebtables fcron fdupes file-roller gedit gnome-calculator gnome-disk-utility gnome-keyring gnome-terminal gparted iotop jre8-openjdk kdeconnect keepassxc krita lib32-mpg123 libreoffice-fresh nautilus nfs-utils nmon nomacs ntfs-3g obs-studio ovmf pavucontrol python2-nautilus python-pip qbittorrent qemu redshift rfkill riot-desktop smartmontools smplayer spectacle sshfs steam steam-native-runtime ttf-hack ttf-liberation virt-manager wine_gecko wireshark-qt wol xterm youtube-dl
    systemctl enable fcron
		#Setup virtualization
		usermod -G libvirt $username
		systemctl enable libvirtd
		#Setup UEFI virtualization
		echo "nvram = [" >> /etc/libvirt/qemu.conf 
		echo "\/usr/share/ovmf/ovmf_code_x64.bin:/usr/share/ovmf/ovmf_vars_x64.bin\"" >> /etc/libvirt/qemu.conf 
		echo "]" >> /etc/libvirt/qemu.conf 

		##Create archfinish.sh - script meant to be executed on first boot
		echo "#!/bin/bash" > /home/$username/archfinish.sh
		#enable NTP time syncing
		echo "timedatectl set-ntp true" >> /home/$username/archfinish.sh
		echo "pacaur -Syu polybar-git angrysearch charles mumble-git nextcloud-client pamac-aur qdirstat reaver-wps-fork-t6x-git rpcs3-git sc-controller visual-studio-code-git zsh-autosuggestions --noconfirm --noedit" >> /home/$username/archfinish.sh
		chmod +x /home/$username/archfinish.sh
	fi
	exit
fi
echo "Now you should reboot with 'reboot'."
echo "If you selected to install utilities, there's a script - /home/$username/archfinish.sh  - that you should run after the reboot to finish the installation"
