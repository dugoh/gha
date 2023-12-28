#!/bin/bash
# shellcheck disable=SC2015 # if echo fails we have bigger problems
# shellcheck disable=SC2046 # intentional golfing
# shellcheck disable=SC2210 # files named 1 or 2confuses shellcheck

function check {
  echo -ne "$*\t"
}

function ok {
  echo -e "[ \e[38;5;32msuccess\e[0m ]"
}

function nok {
  echo -e "[ \e[38;5;31mfailure\e[0m ]"
}

function warn {
  echo -e "[ \e[38;5;33mwarning\e[0m ]"
}

function format {
  awk -F'\t' '{ printf "%-60s %s\n",$1,$2 }'
}

function slowcat {
[[ -z "${3}" ]] && echo usage: "$0" file chunksize waittime && return 1
  local c=0
  local b
  b=$(wc -c <"${1}")
    while [ ${c} -lt "${b}" ]; do
    dd if="${1}" bs=1 count="${2}" skip=${c} 2>/dev/null
    (( c = c + ${2} ))
    sleep "${3}"
  done
}

function index {
  echo "<HTML><HEAD><TITLE>LINKS</TITLE></HEAD><BODY><ul>" >index.html
  # shellcheck disable=SC2010
  for file in $(ls|grep -v index.html); do \
    (\
      printf '<li><a href="' ; \
      printf "%s" "${file}" ; \
      printf '">' ; \
      printf "%s" "${file}" ; \
      printf '</a></li>\n' \
    ) >>index.html ; \
  done
  echo "</ul></BODY></HTML>" >>index.html
}

# R.I.P. bochs, latest SVN, does not build anymore
# bochs_src=https://svn.code.sf.net/p/bochs/code/trunk
# R.I.P. svn2github, HEAD does not build anymore and is not being updated anymore
# 81fca4481acb6c71dfd2d9dff974bf6c36f593a1 seems to compile
bochs_src=https://github.com/svn2github/bochs.git
reset_to=81fca4481acb6c71dfd2d9dff974bf6c36f593a1

wd="$(pwd)"
ftproot=$(grep "^ftp:" /etc/passwd|cut -d ':' -f 6)
ftpconv=$(find /etc/ -name vsftpd.conf 2>/dev/null|grep -F -v init)
flop=BSD/386bsd-0.1/bootable/dist.fs
ip=$(ifconfig eth0|grep "inet "|awk '{print $2}')

echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
echo wd = "${wd}"
echo ftproot = "${ftproot}"
echo ftpconv = "${ftpconv}"
echo flop = "${flop}"
echo ip = "${ip}"
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

cat >bochsrc <<"__EOF"
config_interface: textconfig
display_library: term
romimage: file=$BXSHARE/BIOS-bochs-legacy
cpu: count=1, ips=80000000, reset_on_triple_fault=0
megs: 8
vgaromimage: file=$BXSHARE/VGABIOS-lgpl-latest
vga: extension=none
floppya: 1_44=boot.img, status=inserted
ata0: enabled=1, ioaddr1=0x1f0, ioaddr2=0x3f0, irq=14
ata0-master: type=disk, path="disk.img", mode=flat, cylinders=1024, heads=16, spt=63, translation=none, model=generic
#ata0-master: type=disk, path="disk.img", mode=flat, translation=lba, model=generic
boot: disk, floppy
floppy_bootsig_check: disabled=0
log: bochsout.txt
panic: action=ask
error: action=ignore
info: action=ignore
debug: action=ignore
#vga_update_interval: 400000
#keyboard_serial_delay: 250
#keyboard_paste_delay: 2991000
mouse: enabled=0
private_colormap: enabled=0
#keyboard_mapping: enabled=0, map=
#i440fxsupport: enabled=0
ne2k: ioaddr=0x300, irq=9, mac=fe:fd:00:00:00:01, ethmod=tuntap, ethdev=/dev/net/tun, script=./tunconfig
com1: enabled=0
#com1: enabled=1, mode=file, dev=serial.out
clock: time0=740756888
__EOF


# usr/src/sys.386bsd/i386/isa/clock.c suffers from a Y2K bug.
# Setting the time to the current date results in timestamps set to to 1970.
#
# If you want sensible timestamps you can set time0 in bochsrc.
#
# reasonable values are:
#
# - 711244800 - release date
# - 735327993 - first patch kit
# - 740756888 - second patch kit

# In this build 386bsd 0.1 as released is installed and the 2 patch kits
# are placed on the filesystem for later use, hence the choice for 740756888.
# After every boot this is incremented with 2 hours. This is done so the
# arrow of time doesn't look broken.

cat >tunconfig <<"__EOF"
#!/bin/bash
(
sudo /sbin/ifconfig ${1##/*0/} 192.168.1.1
# carnival, put your masks on and go
sudo /sbin/iptables -D POSTROUTING -t nat -s 192.168.1.0/24 ! -d 192.168.1.0/24 -j MASQUERADE >& /dev/null
sudo /sbin/iptables -t nat -s 192.168.1.0/24 ! -d 192.168.1.0/24 -A POSTROUTING -j MASQUERADE
#echo 1 > /proc/sys/net/ipv4/ip_forward
)>tunconfig.log 2>&1
__EOF
chmod +x tunconfig

(
check checking wget;                   wget --help                                      >/dev/null 2>&1 && ok || nok
check checking gcc;                    gcc --version                                    >/dev/null 2>&1 && ok || nok
check checking gcc-c++;                g++ --version                                    >/dev/null 2>&1 && ok || nok
check checking ncurses;                ls -l /usr/include/ncurses.h                     >/dev/null 2>&1 && ok || nok
check checking vsftpd;                 pgrep vsftpd                                     >/dev/null 2>&1 && ok || nok
check checking 386BSD 0.1;             ls -l BSD.tar.bz2                                >/dev/null 2>&1 && ok || nok
check getting bochs sources;           git clone "${bochs_src}"                         >/dev/null 2>&1 && ok || nok
check checking bochs sources;          cd bochs                                         >/dev/null 2>&1 && ok || nok
check reverting to last known good;    git reset --hard "${reset_to}"                   >/dev/null 2>&1 && ok || nok
cd bochs || exit
                                       ./configure --help                               >d.out
                                       find ./ -name cksum.cc                           >>d.out
                                       cat "$(find ./ -name cksum.cc)"                  >>d.out
check patching bochs;                  sed  -i '1i #include <stdint.h>' "$(find ./ -name cksum.cc)"     && ok || nok
check configuring bochs;               ./configure                                      \
                                         --enable-cpu-level=3                           \
                                         --enable-fpu                                   \
                                         --enable-ne2000                                \
                                         --with-term                                    \
                                         --with-nogui                                   \
                                         --enable-all-optimizations                     \
                                         --enable-docbook=no                            >/dev/null 2>&1 && ok || nok
check building bochs;                  make                                             >>d.out    2>&1 && ok || nok
check installing bochs;                sudo make install                                >/dev/null 2>&1 && ok || nok
cd ..
check tarring up bochs;                tar -cvf bochs.tar ./bochs                       >/dev/null 2>&1 && ok || nok
check compressing bochs tarball;       bzip2 --best bochs.tar                           >/dev/null 2>&1 && ok || nok
check setting capabilities;            sudo setcap                                      \
                                         CAP_NET_ADMIN,CAP_NET_RAW=eip                  \
                                         /usr/local/bin/bochs                           >/dev/null 2>&1 && ok || nok
check opening anon ftp and rate limit; printf "anonymous_enable=Yes\n"                  \
                                         |sudo tee -a "${ftpconv}"                      >/dev/null 2>&1 && ok || nok
check checking ftproot;                cd "${ftproot}"                                  >/dev/null 2>&1 && ok || nok
check extracting distribution/patches; bunzip2 -c "${wd}/BSD.tar.bz2" |sudo tar -xf -   >/dev/null 2>&1 && ok || nok
check correct ownership;               sudo chown -R ftp:ftp "${ftproot}"               >/dev/null 2>&1 && ok || nok
check correct ftproot permissions;     sudo chmod -R a-w "${ftproot}"                   >/dev/null 2>&1 && ok || nok
check correct file permissions;        sudo chmod 644 $(sudo find "${ftproot}" -type f) >/dev/null 2>&1 && ok || nok
check correct directory permissions;   sudo chmod 555 $(sudo find "${ftproot}" -type d) >/dev/null 2>&1 && ok || nok
check restarting vsftpd;               sudo service vsftpd restart                      >/dev/null 2>&1 && ok || nok
check re-checking vsftpd;              pgrep vsftpd                                     >/dev/null 2>&1 && ok || nok
check tunconfig script present;        cd "$wd" && ls tunconfig                         >/dev/null 2>&1 && ok || nok
check checking for free range;         sudo ifconfig| grep -F -q                        \
                                         "$(grep iptables tunconfig                     \
                                          |head -1                                      \
                                          |sed -e's/.*-d //'                            \
                                          |awk -F'.' '{print ":"$1"."$2"."}')"          2>/dev/null && warn || ok
check bochs config present;            ls bochsrc                                       >/dev/null 2>&1 && ok || nok
check boot floppy;                     ( sudo cat "${ftproot}/${flop}";                 \
                                         dd if=/dev/zero bs=1 count=245760              \
                                       )>boot.img 2>/dev/null; ls boot.img              >/dev/null 2>&1 && ok || nok
check creating empty disk;             dd if=/dev/zero of=disk.img bs=1048576 count=504 >/dev/null 2>&1 && ok || nok
# build qemu
check getting qemu source;       git clone https://github.com/qemu/qemu.git                   >/dev/null 2>&1 && ok || nok
cd qemu || exit
check going back to 0.11;        git reset --hard 08fd2f30bd3ee5d04596da8293689af4d4f7eb6c    >/dev/null 2>&1 && ok || nok
check remove definition of BIT;  sed -i -e 's/#define BIT.n. .1 << .n../\/\/&/' hw/eepro100.c >/dev/null 2>&1 && ok || nok
check define BIT properly;       printf "#ifndef BIT\n#define BIT(n) (1 << (n))\n#endif\n" >> qemu-common.h   && ok || nok
check configure qemu;            ./configure --target-list=i386-softmmu \
                                             --disable-sdl \
                                             --disable-vnc-tls \
                                             --disable-vnc-sasl \
                                             --disable-vde                                    >/dev/null 2>&1 && ok || nok
check make qemu;                 make                                                         >/dev/null 2>&1 && ok || warn
cd i386-softmmu || exit
check build where make fails;    gcc -g -Wl,--warn-common  -m64  -o qemu \
                                     vl.o osdep.o monitor.o pci.o loader.o \
                                     isa_mmio.o machine.o gdbstub.o gdbstub-xml.o \
                                     msix.o ioport.o virtio-blk.o \
                                     virtio-balloon.o virtio-net.o virtio-console.o \
                                     kvm.o kvm-all.o usb-ohci.o eepro100.o ne2000.o \
                                     pcnet.o rtl8139.o e1000.o wdt_ib700.o \
                                     wdt_i6300esb.o ide.o pckbd.o vga.o  sb16.o es1370.o \
                                     ac97.o dma.o fdc.o mc146818rtc.o serial.o i8259.o \
                                     i8254.o pcspk.o pc.o cirrus_vga.o apic.o ioapic.o \
                                     parallel.o acpi.o piix_pci.o usb-uhci.o vmmouse.o \
                                     vmport.o vmware_vga.o hpet.o device-hotplug.o \
                                     pci-hotplug.o smbios.o \
                                     -Wl,--whole-archive ../libqemu_common.a libqemu.a ../libhw64/libqemuhw64.a \
                                     -Wl,--no-whole-archive \
                                     -lm -lrt -lpthread -lz -lutil -lncurses -ltinfo          >/dev/null 2>&1 && ok || nok
cd ..
check continue make qemu;        make                                                         >/dev/null 2>&1 && ok || nok
check make install qemu;         sudo make install                                            >/dev/null 2>&1 && ok || nok
check remove git tracking;       rm -rf .git                                                  >/dev/null 2>&1 && ok || nok
check test qemu;                 qemu --help                                                  >/dev/null 2>&1 && ok || nok
check setting qemu capabilities;       sudo setcap                                            \
                                         CAP_NET_ADMIN,CAP_NET_RAW=eip                        \
                                         /usr/local/bin/qemu                                  >/dev/null 2>&1 && ok || nok
cd ..
)|format

# first boot ##########################
cat >1 <<__EOF
(echo y; echo y)|install
__EOF

echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
echo first boot
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
(
  until grep -E -q '#|werase' out ; do
    sleep 5
  done
  sleep 5
  slowcat ./1 2 .3
)| TERM=vt100 bochs -q -f bochsrc |tee -a out
mv out out_1.txt
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
echo

(
check add 2 hours to clock;           sed -i -e "s/740756888/740764088/" bochsrc              >/dev/null 2>&1 && ok || nok
)|format
echo
######################################

# second boot ########################
cat >2 <<__EOF
echo "machine ${ip}" >.netrc
echo "login ftp" >>.netrc
echo "password ftp@oldbsd.org" >>.netrc
echo "macdef init" >>.netrc
echo "#" >>.netrc
echo "prompt" >>.netrc
echo "bin" >>.netrc
echo "lcd /tmp" >>.netrc
echo "cd BSD/386bsd-0.1/bindist/" >>.netrc
echo "mget *" >>.netrc
echo "cd ../etcdist/" >>.netrc
echo "mget *" >>.netrc
echo "cd ../srcdist/" >>.netrc
echo "mget *" >>.netrc
echo "cd ../../386bsd-patchkits" >>.netrc
echo "mget *tar" >>.netrc
echo "!echo odin |extract bin01" >>.netrc
echo "!csh -c \"limit openfiles 512; extract src01 ; extract etc01 ; tar -cf /dist.tar /tmp/ ; cp pk023.tar /pk023.tar ; cp pk023024.tar /pk023024.tar ; sync ; sync ; sync ; /sbin/shutdown -r now\"" >>.netrc
echo "quit" >>.netrc
echo "#newl" >>.netrc
echo "" >>.netrc
chmod 400 .netrc
cat .netrc
ifconfig ne0 192.168.1.2 netmask 255.255.255.0 up
route add default 192.168.1.1
ftp ${ip}
__EOF

echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
echo second boot
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
touch out
(
  until grep -E -q '#|werase' out ; do
    sleep 5
  done
  sleep 5
  slowcat ./2 4 1.2
)| TERM=vt100 bochs -q -f bochsrc |tee -a out |sed -e's/startart//g'|sed -e's/startart//g'
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
echo
mv out out_2.txt

(
check add 2 hours to clock;           sed -i -e "s/740764088/740771288/" bochsrc      >/dev/null 2>&1 && ok || nok
)|format
######################################


# third boot #########################
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
echo third boot
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
touch out
(sleep 70; echo)|TERM=vt100 bochs -q -f bochsrc |tee -a out
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
echo
mv out out_3.txt

(
check add 2 hours to clock;           sed -i -e "s/740771288/740778488/" bochsrc        >/dev/null 2>&1 && ok || nok
#check creating gh-pages;              mkdir gh-pages ; cd gh-pages                      >/dev/null 2>&1 && ok || nok
#check add bochs;                      mv ../bochs/bochs.tar.bz2 ./                      >/dev/null 2>&1 && ok || nok
#check add the hard disk;              mv ../disk.img ./                                 >/dev/null 2>&1 && ok || nok
#check compress the disk;              bzip2 --best disk.img                             >/dev/null 2>&1 && ok || nok
#check split the disk in parts;        split -b 50m "disk.img.bz2" "disk.part-"          >/dev/null 2>&1 && ok || nok
#check remove the unsplit disk;        rm disk.img.bz2                                   >/dev/null 2>&1 && ok || nok
#check add the floppy disk;            mv ../boot.img ./                                 >/dev/null 2>&1 && ok || nok
#check add the bochs config;           mv ../bochsrc ./                                  >/dev/null 2>&1 && ok || nok
#check add the TUN config;             mv ../tunconfig ./                                >/dev/null 2>&1 && ok || nok
#check add the screen output;          mv ../out_* ./                                    >/dev/null 2>&1 && ok || nok
#check add intentionally blank file;   touch ./out_4.txt                                 >/dev/null 2>&1 && ok || nok
#check create an index page;           index                                             >/dev/null 2>&1 && ok || nok
#check push to gh-pages;               push                                              >../outf 2>&1 && ok || nok
)|format

# # a second third boot (fsck due to clock shift) #############
# echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# echo a second third boot
# echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# touch out
# (sleep 30; echo)|TERM=vt100 bochs -q -f bochsrc |tee -a out
# echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
# echo
# mv out out_3b.txt
###########################################################

# fourth boot #############################################
cat >4 <<"__EOF4__"
root

exec sh
cat >/to_pk023.sh <<"__EOF"
#!/bin/sh
cd /
tar -xvf pk023.tar
mv patch dist
cd dist/bin
./mkpatchdirs
(echo y; echo; echo; echo IALL; echo y ; echo ; echo q)|./patches
./afterinstall.sh
rm -r /sys/compile/*
cd /sys/i386/conf
config GENERICISA
cd /sys/compile/GENERICISA
make depend
make
mv /386bsd /386bsd.old
cp 386bsd /386bsd
sync; sync; sync
shutdown -rf now
__EOF
chmod +x /to_pk023.sh
/to_pk023.sh
__EOF4__

echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
echo fourth boot
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
touch out
(
  until egrep -q 'login:|console' out ; do
    sleep 5;
  done
  sleep 5
  slowcat ./4 4 1
)| TERM=vt100 bochs -q -f bochsrc |tee -a out 
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
echo
mv out out_4.txt
###########################################################

(
check add 2 hours to clock;           sed -i -e's/time0=.*/time0=735335193/' bochsrc    >/dev/null 2>&1 && ok || nok
)|format

cat >5 <<"__EOF5__"
root

exec sh
cat >/buildworld_pk023.sh <<"__EOF"
#!/bin/sh
cd /patch/bin
./buildworld.sh
sync; sync; sync
shutdown -rf now
__EOF
chmod +x /buildworld_pk023.sh
/buildworld_pk023.sh
__EOF5__

(
check convert disk;                   qemu-img convert \
                                              -f raw -O qcow2 disk.img qdisk.img        >/dev/null 2>&1 && ok || nok
)|format

ls -l
which script
type script
script --help
echo
qemu --help
exit
# fifth boot ##############################################
#touch out
#(
#  until egrep -q 'login:|console' out ; do
#    sleep 5;
#  done
#  sleep 5
#  slowcat ./5 1 .5
#)| TERM=vt100 script -f -c 'qemu          \
#                -L /usr/local/share/qemu/ \
#                -curses                   \
#                -hda qdisk.img            \
#                -M isapc                  \
#                -net user                  \
#                -no-reboot                \
#                -m 64                     \
#                -startdate "1994-04-21"'  \
# |tee -a out  #                            \
# #|tr -cd 'c'                              \
# #|fold -w 120
#mv out out_5.txt
###########################################################

echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
echo "fifth boot (takes hours on bochs)"
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
touch out
(
  until egrep -q 'login:|console' out ; do
    sleep 5;
  done
  sleep 5
  slowcat ./5 4 1
)| TERM=vt100 bochs -q -f bochsrc |tee -a out 
mv out out_5.txt
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

echo;echo ====;echo;echo
fold out_5.txt|head -150
echo;echo ====;echo;echo
fold out_5.txt|tail -150
echo;echo ====;echo;echo
echo %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

(
check creating gh-pages;              mkdir gh-pages ; cd gh-pages                      >/dev/null 2>&1 && ok || nok
check add the hard disk;              mv ../qdisk.img ./                                >/dev/null 2>&1 && ok || nok
check compress the disk;              bzip2 --best qdisk.img                            >/dev/null 2>&1 && ok || nok
check split the disk in parts;        split -b 50m "qdisk.img.bz2" "qdisk.part-"        >/dev/null 2>&1 && ok || nok
check remove the unsplit disk;        rm qdisk.img.bz2                                  >/dev/null 2>&1 && ok || nok
check add the floppy disk;            mv ../boot.img ./                                 >/dev/null 2>&1 && ok || nok
check add the bochs config;           mv ../bochsrc ./                                  >/dev/null 2>&1 && ok || nok
check add the TUN config;             mv ../tunconfig ./                                >/dev/null 2>&1 && ok || nok
check add the screen output;          mv ../out_* ./                                    >/dev/null 2>&1 && ok || nok
check create an index page;           index                                             >/dev/null 2>&1 && ok || nok
#check push to gh-pages;               push                                              >/dev/null 2>&1 && ok || nok
)|format
