#!/bin/bash
#
# Install grsecurity from source, Debian version
# Rickard Andersson <rickard@0x539.se>
#
# Version 1.0, 2012-03-31
#
# Version 1.1, 2012-05-01
# * The lguest folder seems to have been moved as of kernel 3.3, changed the code to
#   try to find the directory dynamically
#
# Version 1.1.1, 2013-10-20
# * Grsecurity.net switched to two RSS feeds for the 2.6 and 3.x stable branches
# * Added gcc-plugin-dev as a requirement
# * Fixed issues with architecture in the kernel package name after creation
#
# Version 1.2, 2013-12-31
# * Switched to XZ archives, https://www.kernel.org/happy-new-year-and-good-bye-bzip2.html
#
# Version 1.3, 2014-05-26
# * Added question to remove build tools after install
# * Fix issue with re-using a downloaded Linux archive
# * Improved support for re-running a build of the same kernel version
#
# Version 1.4, 2014-12-31
# * Changed URL for detemining the latest versions of grsecurity
# * Cache latest versions
# * Verify archives even if they haven't just been downloaded
#

GCC_VERSION=`LANGUAGE=C apt-cache policy gcc | grep 'Installed:' | cut -c 16-18`
BUILDTOOLS="build-essential bin86 kernel-package libncurses5-dev zlib1g-dev gcc-${GCC_VERSION}-plugin-dev bc"

if [ `whoami` != "root" ]; then
	echo "This script needs to be run as root!"
	exit 1
fi

if [ -z /etc/debian_version ]; then
	echo "This script is made for Debian environments!"
	exit 1
fi

clear

echo "Welcome to the automagic grsecurity Debian Installer

We will be working from /usr/src so make sure to have at least
4 GB of free space on the partition where /usr/src resides.

The installation will be carried out in the following steps:
1. Fetch the current version from grsecurity.net
2. Letting you chose which version you would like to install
3. Download PGP keys for download verification (first run only)
4. Install the following debian packages if needed:
	 ${BUILDTOOLS} curl xz-utils
5. Download the kernel source from www.kernel.org
6. Download the grsecurity patch from grsecurity.net
7. Verify the downloads and extract the kernel
8. Apply the grsecurity kernel patch to the kernel source
9. Copy the current kernel configuration from /boot
10. Configure the kernel by
	a) running 'make menuconfig' if the current kernel doesn't support grsecurity
	b) running 'make oldconfig' if the current kernel supports grsecurity
11. Compile the kernel into a debian package
12. Install the debian package

"

DOWNLOAD_STABLE=1
DOWNLOAD_STABLE2=1
DOWNLOAD_TESTING=1

if [ -f latest_stable_patch ]; then
	STABLE_MTIME=`expr $(date +%s) - $(date +%s -r latest_stable_patch)`

	if [ $STABLE_MTIME -gt 3600 ]; then
		rm latest_stable_patch
	else
		DOWNLOAD_STABLE=0
	fi
fi

if [ -f latest_stable2_patch ]; then
	STABLE2_MTIME=`expr $(date +%s) - $(date +%s -r latest_stable2_patch)`

	if [ $STABLE2_MTIME -gt 3600 ]; then
		rm latest_stable2_patch
	else
		DOWNLOAD_STABLE2=0
	fi
fi

if [ -f latest_test_patch ]; then
	TESTING_MIME=`expr $(date +%s) - $(date +%s -r latest_test_patch)`

	if [ $TESTING_MIME -gt 3600 ]; then
		rm latest_test_patch
	else
		DOWNLOAD_TESTING=0
	fi
fi

if [ -z `which curl` ]; then
	echo "==> Installing curl ..."
	apt-get -y -qq install curl &> /dev/null
	if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi
fi

echo "==> Checking current versions of grsecurity ..."

if [ $DOWNLOAD_STABLE -eq 1 ]; then
	curl -O --silent https://grsecurity.net/latest_stable_patch
fi

if [ $DOWNLOAD_STABLE2 -eq 1 ]; then
	curl -O --silent https://grsecurity.net/latest_stable2_patch
fi

if [ $DOWNLOAD_TESTING -eq 1 ]; then
	curl -O --silent https://grsecurity.net/latest_test_patch
fi

STABLE_VERSIONS=`cat latest_stable_patch | sed -e 's/\.patch//g' | sed -e 's/grsecurity-//g'`
STABLE2_VERSIONS=`cat latest_stable2_patch | sed -e 's/\.patch//g' | sed -e 's/grsecurity-//g'`
TESTING_VERSIONS=`cat latest_test_patch | sed -e 's/\.patch//g' | sed -e 's/grsecurity-//g'`

COUNTER=0

for x in ${STABLE_VERSIONS} ${STABLE2_VERSIONS}; do

	let COUNTER=COUNTER+1

	GRSEC=`echo ${x} | sed -e 's/-/ /g' | awk '{print $1}'`
	KERNEL=`echo ${x} | sed -e 's/-/ /g' | awk '{print $2}'`
	REVISION=`echo ${x} | sed -e 's/-/ /g' | awk '{print $3}'`

	VERSIONS[$COUNTER]=${x}-stable

	echo "==> $COUNTER. grsecurity version ${GRSEC} for kernel ${KERNEL}, revision ${REVISION} (stable version)"
done

for x in ${TESTING_VERSIONS}; do

	let COUNTER=COUNTER+1

	GRSEC=`echo ${x} | sed -e 's/-/ /g' | awk '{print $1}'`
	KERNEL=`echo ${x} | sed -e 's/-/ /g' | awk '{print $2}'`
	REVISION=`echo ${x} | sed -e 's/-/ /g' | awk '{print $3}'`

	VERSIONS[$COUNTER]=${x}-testing

	echo "==> $COUNTER. grsecurity version ${GRSEC} for kernel ${KERNEL}, revision ${REVISION} (testing version)"
done


echo -n "==> Please make your selection: [1-$COUNTER]: "

read SELECTION

DATA=${VERSIONS[$SELECTION]}
VERSION=`echo $DATA | sed -e 's/-/ /g' | awk '{print $1}'`
KERNEL=`echo $DATA | sed -e 's/-/ /g' | awk '{print $2}'`
REVISION=`echo $DATA | sed -e 's/-/ /g' | awk '{print $3}'`
BRANCH=`echo $DATA | sed -e 's/-/ /g' | awk '{print $4}'`
GRSEC=`echo $VERSION-${KERNEL}-${REVISION}`
KERNEL_BRANCH=`echo ${KERNEL} | cut -c 1`

if [ "${BRANCH}" == "testing" ]; then
	TESTING=y
else
	TESTING=n
fi


echo -n "==> Remove build tools after install? (${BUILDTOOLS}): [y/N] "
read UNINSTALL


echo "==> Installing grsecurity ${BRANCH} version $VERSION using kernel version ${KERNEL} ... "

if [ ! -f spender-gpg-key.asc ]; then
	echo "==> Downloading grsecurity GPG keys for package verification ... "
	curl --progress-bar --remote-name https://grsecurity.net/spender-gpg-key.asc

	echo -n "==> Importing grsecurity GPG key ... "
	gpg --import spender-gpg-key.asc &> /dev/null
	if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi
fi

if [ `gpg --list-keys | grep 6092693E | wc -l` -eq 0 ]; then
	echo -n "==> Fetching kernel GPG key ... "
	gpg --recv-keys 6092693E &> /dev/null
	if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi
fi


echo -n "==> Installing packages needed for building the kernel ... ";
apt-get -y -qq install ${BUILDTOOLS} xz-utils &> /dev/null
if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi

cd /usr/src

if [ -h linux ]; then
	rm linux
fi

if [ ! -f linux-${KERNEL}.tar.xz ] && [ ! -f linux-${KERNEL}.tar ]; then
	echo "==> Downloading kernel version ${KERNEL} ... "

	if [ ${KERNEL_BRANCH} -eq 2 ]; then
		curl --progress-bar --remote-name https://www.kernel.org/pub/linux/kernel/v2.6/longterm/v2.6.32/linux-${KERNEL}.tar.xz
		curl --silent --remote-name https://www.kernel.org/pub/linux/kernel/v2.6/longterm/v2.6.32/linux-${KERNEL}.tar.sign
	elif [ ${KERNEL_BRANCH} -eq 3 ]; then
		curl --progress-bar --remote-name https://www.kernel.org/pub/linux/kernel/v3.0/linux-${KERNEL}.tar.xz
		curl --silent --remote-name https://www.kernel.org/pub/linux/kernel/v3.0/linux-${KERNEL}.tar.sign
	fi

		echo -n "==> Extracting linux-${KERNEL}.tar ... "
		unxz linux-${KERNEL}.tar.xz
	if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi
fi

echo -n "==> Verifying linux-${KERNEL}.tar ... "
gpg --verify linux-${KERNEL}.tar.sign &> /dev/null
if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi

if [ ! -f grsecurity-${GRSEC}.patch ]; then
	echo "==> Downloading grsecurity patch version ${GRSEC} ... "

	if [ "${TESTING}" == "y" ]; then
		curl --progress-bar --remote-name https://grsecurity.net/test/grsecurity-${GRSEC}.patch
		curl --silent --remote-name https://grsecurity.net/test/grsecurity-${GRSEC}.patch.sig
	else
		curl --progress-bar --remote-name https://grsecurity.net/stable/grsecurity-${GRSEC}.patch
		curl --silent --remote-name https://grsecurity.net/stable/grsecurity-${GRSEC}.patch.sig
	fi
fi

echo -n "==> Verifying grsecurity-${GRSEC}.patch ... "
gpg --verify grsecurity-${GRSEC}.patch.sig &> /dev/null
if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi

if [ ! -d linux-${KERNEL} ]; then
	echo -n "==> Unarchiving linux-${KERNEL}.tar ... "
	tar xf linux-${KERNEL}.tar
	if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi
fi

if [ ! -d linux-${KERNEL}-grsec ]; then
	mv linux-${KERNEL} linux-${KERNEL}-grsec
fi

ln -s linux-${KERNEL}-grsec linux
cd linux

patch --silent -p1 --forward --dry-run < ../grsecurity-${GRSEC}.patch &> /dev/null

if [ $? -eq 0 ]; then
	echo -n "==> Applying patch ... "
	patch --silent -p1 --forward < ../grsecurity-${GRSEC}.patch
	if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi
else
	echo "==> Patch seems to already been applied, skipping ..."
fi


# Fix http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=638012
#
# the lguest directory seems to be moving around quite a bit, as of 3.3.something
# it resides under the tools directory. The best approach should be to just search for it 
if [ ${KERNEL_BRANCH} -eq 3 ] && [ ! -s Documentation/lguest ]; then
	cd Documentation
	find .. -name lguest.c | xargs dirname | xargs ln -s
	cd ..
fi

cp /boot/config-`uname -r` .config
if [ -z `grep "CONFIG_GRKERNSEC=y" .config` ]; then
	echo "==> Current kernel doesn't seem to be running grsecurity. Running 'make menuconfig'"
	make menuconfig
else
	echo -n "==> Current kernel seems to be running grsecurity. Running 'make oldconfig' ... "
	yes "" | make oldconfig &> /dev/null
	if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi
fi

echo -n "==> Building kernel ... "

NUM_CORES = `grep -c ^processor /proc/cpuinfo`

make-kpkg clean &> /dev/null
if [ $? -eq 0 ]; then echo -n "phase 1 OK ... "; else echo "Failed"; exit 1; fi

make-kpkg --jobs=${NUM_CORES} --initrd --revision=${REVISION} kernel_image &> /dev/null
if [ $? -eq 0 ]; then echo "phase 2 OK ... "; else echo "Failed"; exit 1; fi

cd ..

echo -n "==> Installing kernel ... "
dpkg -i linux-image-${KERNEL}-grsec_`echo ${REVISION}`_*.deb &> /dev/null
if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi


echo -n "==> Cleaning up ... "
rm linux-${KERNEL}.tar linux-${KERNEL}.tar.sign grsecurity-${GRSEC}.patch grsecurity-${GRSEC}.patch.sig
if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi

if [ "${UNINSTALL}" == "y" ]; then
	echo -n "==> Removing build tools ... "
	apt-get -y -qq remove ${BUILDTOOLS} &> /dev/null
	if [ $? -eq 0 ]; then echo "OK"; else echo "Failed"; exit 1; fi
fi
