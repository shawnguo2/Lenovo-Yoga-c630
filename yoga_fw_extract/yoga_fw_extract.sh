#!/bin/bash

# This script tries to extract the firmware files needed to enable the DSPs/audio/wifi on the Lenovo Yoga
# from the systems windows partion
###################################################################################################################################################

# Create a hashtable of firmware md5s
declare -A firmware_md5
firmware_md5=(\
["b073f0e9ad512f83696f68fb2ac82319"]="2019v1"\		# board-2.bin, (U.S. 02/19, includes bdwlan.b31)
["e321e669ecff5738231a2bcc6a8ecbcd"]="2019v1"\		# board-2.bin, (U.S. 02/19)
["d16e3444f68ee48c548a891b9f9279e1"]="2019v1"\		# firmware-5.bin
["cfc4461b69eca41048fe6a3f3d183579"]="2019v1"\		# qcadsp850.mbn (U.S. 03/19)
["1dedde8123594b5a0f2542c4a7574d65"]="2019v1"\		# qccdsp850.mbn (U.S. 03/19)
["a21a205d953447c6067bfd77525e3bd3"]="2019v1"\		# qcdsp1v2850.mbn (U.S. 03/19)
["af495b137bd41086887897fc4c535c99"]="2019v1"\		# qcdsp2850.mbn (U.S. 03/19)
["af495b137bd41086887897fc4c535c99"]="2019v1"\		# modem.mdt (U.S. 03/19)
["30d0887d2e1a5d856531b01a97119731"]="2019v1"\		# wlanmdsp.mbn (U.S. 03/19)
)

###################################################################################################################################################

URL_FW_FIRMWARE5BIN="https://github.com/kvalo/ath10k-firmware/raw/master/WCN3990/hw1.0/HL2.0/WLAN.HL.2.0-01387-QCAHLSWMTPLZ-1/firmware-5.bin"

TXT_UNDERLINE="\033[1m\033[4m"
TXT_NORMAL="\033[0m"

# Don't run as root to avoid doing anything monumentally stupid
if [ ${UID} -eq 0 ]; then
	echo -e "${TXT_UNDERLINE}Error: This script won't run as root.${TXT_NORMAL}"
	exit
fi

###################################################################################################################################################
# Functions
###################################################################################################################################################
function done_failedexit {
	if [ $1 -eq 0 ]; then
		echo "Done"
	else
		echo "Failed"
		exit
	fi
}

###################################################################################################################################################
# Find the relevant firmware directories, and make a working copy
###################################################################################################################################################
WIN_PART=""									# Windows partition path
# Try to automatically identify windows partition
echo -e "${TXT_UNDERLINE}Getting Windows drivers...${TXT_NORMAL}"
echo "Searching for Windows partition..."
WIN_PART_LABEL="Windows"
WIN_PART_TMP=`blkid -L "${WIN_PART_LABEL}"`
if [ $? -eq 0 ]; then
	echo "	Found Windows partition: ${WIN_PART_TMP}"
	WIN_PART=${WIN_PART_TMP}
else
	echo "	Partition not found."
	echo -n "Please enter the path of the Windows partition: "
	read WIN_PART
fi

# Check if partition exists
if [ ! -e ${WIN_PART} ]; then
	echo "Error: Windows partition path does not exist: ${WIN_PART}"
	exit
fi

WIN_MNT=""									# Windows mount path
WIN_MNT_UNMNT=""								# Whether to umount windows mount
# Check if it's already mounted
echo -n "Checking if partition already mounted: "
while read pmount
do
	if [[ "${pmount}" =~ "${WIN_PART} " ]]; then
		WIN_MNT=`echo "${pmount}"|awk '{print $2}'`
	fi
done < /proc/mounts
if [[ ${WIN_MNT} == "" ]]; then
	echo "No"
else
	echo "${WIN_MNT}"
fi

# Windows partition not mounted, so mount
if [[ $WIN_MNT == "" ]]; then
	# Check if /mnt already in use
	echo -n "Checking if /mnt in use: "
	while read pmount
	do
		if [[ "${pmount}" =~ "/mnt " ]]; then
			echo "Yes"
			echo "	Either unmount /mnt, or manually mount Windows filesystem readonly and rerun."
			exit
		fi
	done < /proc/mounts
	echo "No"

	# Mount windows partition
	echo "Mounting Windows partition: ${WIN_PART}"
	sudo mount -o ro -t ntfs ${WIN_PART} /mnt
	if [ $? -eq 0 ]; then
		WIN_MNT_UNMNT='/mnt'						# Flag that we need to umount /mnt
	else
		echo "	Error: Mount failed."
		exit
	fi
fi

# Check mounted readonly
WIN_MNT_STS_RO=""
echo -n "Checking Windows FS is read only: "
while read pmount
do
	if [[ "${pmount}" =~ "${WIN_PART} " ]]; then
		WIN_MNT_STS_RO=`echo "${pmount}"|awk '$4 ~ /^ro,/ {print "true"}; $4 ~ /^rw,/ {print "false"}'`
	fi
done < /proc/mounts
echo "${WIN_MNT_STS_RO}"
if [[ "${WIN_MNT_STS_RO}" != "true" ]]; then
	echo "	Error: Windows filesystem not mounted read-only."
	exit
fi

CWD=`pwd`
COPY_ERR=0
# Create directory to copy windows files into
PATH_WIN_DRV="${CWD}/Windows Drivers"
if [ -e "${PATH_WIN_DRV}" ]; then
	echo "Deleting existing copy of Windows drivers..."
	rm -rf "${PATH_WIN_DRV}" &> /dev/null
	done_failedexit $?
fi
echo -n "Creating directory for Windows drivers: "
mkdir "${PATH_WIN_DRV}" &> /dev/null
done_failedexit $?
# Copying Window's driver file
echo -n "Copying Window's driver files: "
# Copy DSP files
for DSP_FILE in `find /mnt/Windows/System32/DriverStore/FileRepository/ -name qcadsp850.mbn`; do
	DSP_PATH=`dirname "${DSP_FILE}"`
	cp -a "${DSP_PATH}" "${PATH_WIN_DRV}" &> /dev/null
	if [ $? -ne 0 ]; then
		COPY_ERR=$((COPY_ERR+1))
	fi
done
# Copy board files
for BRD_FILE in `find /mnt/Windows/System32/DriverStore/FileRepository/ -name bdwlan.bin`; do
	BRD_PATH=`dirname "${BRD_FILE}"`
	cp -a "${BRD_PATH}" "${PATH_WIN_DRV}" &> /dev/null
	if [ $? -ne 0 ]; then
		COPY_ERR=$((COPY_ERR+1))
	fi
done
done_failedexit ${COPY_ERR}

# Umount Windows partition if we mounted it
if [[ "${WIN_MNT_UNMNT}" != "" ]]; then
	echo "Unmounting /mnt."
	sudo umount /mnt
fi

# Process copied files
if [ ${COPY_ERR} -eq 0 ]; then
###################################################################################################################################################
# Select directories with the latest respective firmwares
###################################################################################################################################################
	echo -e "\n${TXT_UNDERLINE}Processing found drivers.${TXT_NORMAL}"
	echo -n "Scanning copied files: "
	# Get path to latest DSP files
	DSP_FILE_CUR=`find Windows\ Drivers/ -type f -name qcadsp850.mbn -exec ls -t {} +|head -n1`
	if [[ "${DSP_FILE_CUR}" == "" ]]; then
		echo "Failed to find any DSP files."
		exit
	else
		DSP_PATH=`dirname "${DSP_FILE_CUR}"`
	fi
	# Get path to latest board files
	BRD_FILE_CUR=`find Windows\ Drivers/ -type f -name bdwlan.bin -exec ls -t {} +|head -n1`
	if [[ "${BRD_FILE_CUR}" == "" ]]; then
		echo "Failed to find any board files."
		exit
	else
		BRD_PATH=`dirname "${BRD_FILE_CUR}"`
	fi
	echo "Done"

###################################################################################################################################################
# Merged board file
###################################################################################################################################################
	# Create merged board file
	echo -e "\n${TXT_UNDERLINE}Merged board file:${TXT_NORMAL}"
	PATH_BRD_MAKE="${CWD}/creating-board-2.bin"
	PATH_BRD_SRC="${CWD}/creating-board-2.bin/bdf"
	PATH_BRD_MFILE="board-2.bin"
	if [ -e "${PATH_BRD_MAKE}" ]; then
		echo "Deleting existing board file directory..."
		rm -rf "${PATH_BRD_MAKE}" &> /dev/null
		done_failedexit $?
	fi
	echo -n "Creating directory for merging board files: "
	mkdir -p "${PATH_BRD_SRC}" &> /dev/null
	done_failedexit $?
	echo -n "Copying individual board files: "
	cp -a "${BRD_PATH}"/bdwlan.b* "${PATH_BRD_SRC}" &> /dev/null
	done_failedexit $?

	cd "${PATH_BRD_MAKE}"
###################################################################################################################################################
# This section copied from: https://github.com/aarch64-laptops/build/blob/master/misc/lenovo-yoga-c630/wifi/create-board-2.bin/make-board-2.bin.sh
###################################################################################################################################################
	echo "Creating JSON board file...."

	JSON="bdf/board-2.json"
	iter=0
	echo "[" > "${JSON}"
	for file in bdf/bdwlan.*; do
		[[ $file == *.txt ]] && continue

		iter=$((iter+1))
		[ $iter -ne 1 ] && echo "  }," >> "${JSON}"

		echo "  {" >> "${JSON}"
		echo "          \"data\": \"$file\"," >> "${JSON}"
		if [[ $file == */bdwlan.bin ]]; then
#			file_ext="0"
			file_ext="ff"				# This was required for my install, don't know if this applies to everyone
		else
			file_ext="$(printf '%x\n' "$(basename "${file}" | sed -E 's:^.*\.b?([0-9a-f]*)$:0x\1:')")"
		fi
		echo "          \"names\": [\"bus=snoc,qmi-board-id=${file_ext}\"]" >> "${JSON}"
	done

	echo "  }" >> "${JSON}"
	echo "]" >> "${JSON}"

	echo -n "Fetching Qualcomm Atheros tools: "
	git clone https://github.com/qca/qca-swiss-army-knife.git &> /dev/null
	done_failedexit $?

	echo -n "Creating merged board file: "
	python2 qca-swiss-army-knife/tools/scripts/ath10k/ath10k-bdencoder -c "${JSON}" -o "${PATH_BRD_MFILE}" &> /dev/null
	done_failedexit $?
###################################################################################################################################################
	cd "${CWD}"

###################################################################################################################################################
# Atheros ath10k firmware
###################################################################################################################################################
	# Create ath10k fw directory
	echo -e "\n${TXT_UNDERLINE}Atheros ath10k firmware${TXT_NORMAL}"
	PATH_FW_ATH10K="${CWD}/WCN3990"
	PATH_FW_ATH10K_HW="${PATH_FW_ATH10K}/hw1.0"
	if [ -e "${PATH_FW_ATH10K_HW}" ]; then
		echo "Deleting existing copy of ath10k firmware files..."
		rm -rf "${PATH_FW_ATH10K_HW}" &> /dev/null
		done_failedexit $?
	fi
	echo -n "Creating directory for ath10k firmware files: "
	mkdir -p "${PATH_FW_ATH10K_HW}" &> /dev/null
	done_failedexit $?
	echo -n "Copying merged board file: "
	cp "${PATH_BRD_MAKE}"/"${PATH_BRD_MFILE}" "${PATH_FW_ATH10K_HW}" &> /dev/null
	done_failedexit $?
	cd "${PATH_FW_ATH10K_HW}"
	echo -n "Fetching firmware-5.bin: "
	wget "${URL_FW_FIRMWARE5BIN}" &> /dev/null
	done_failedexit $?
	cd "${CWD}"

###################################################################################################################################################
# Qualcomm DSP files
###################################################################################################################################################
	# Create linux dsp directory
	echo -e "\n${TXT_UNDERLINE}Qualcomm DSP firmware${TXT_NORMAL}"
	PATH_FW_C630="${CWD}/c630"
	if [ -e "${PATH_FW_C630}" ]; then
		echo "Deleting existing copy of linux DSP files..."
		rm -rf "${PATH_FW_C630}" &> /dev/null
		done_failedexit $?
	fi
	echo -n "Creating directory for linux DSP files: "
	mkdir "${PATH_FW_C630}" &> /dev/null
	done_failedexit $?
	echo -n "Copying linux DSP files: "
	cp -a "${DSP_PATH}"/*.mbn "${PATH_FW_C630}" &> /dev/null
	done_failedexit $?
	cd "${PATH_FW_C630}"
	echo -n "Creating symlink qcdsp2850.mbn -> modem.mdt: "
	ln -s qcdsp2850.mbn modem.mdt &> /dev/null
	done_failedexit $?
	cd "${CWD}"

###################################################################################################################################################
# Check files
###################################################################################################################################################
	echo -e "\n${TXT_UNDERLINE}Checking firmware...${TXT_NORMAL}"
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
	echo "!!!This checks your generated firmware directories against known MD5 hashes!!!"
	echo "!!!If it passes great!                                                     !!!"
	echo "!!!If it fails, well, there could be regional differences... I don't know  !!!"
	echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

	echo -n "Checking ${PATH_FW_ATH10K_HW}/board-2.bin: "
	MD5_BOARD2=`md5sum "${PATH_FW_ATH10K_HW}"/board-2.bin |awk '{print $1}'`
	if [ -z "${firmware_md5[${MD5_BOARD2}]}" ]; then
		echo "Failed"
	else
		echo "Passed"
	fi

	echo -n "Checking ${PATH_FW_ATH10K_HW}/firmware-5.bin: "
	MD5_FIRMWARE5=`md5sum "${PATH_FW_ATH10K_HW}"/firmware-5.bin |awk '{print $1}'`
	if [ -z "${firmware_md5[${MD5_FIRMWARE5}]}" ]; then
		echo "Failed"
	else
		echo "Passed"
	fi

	echo -n "Checking ${PATH_FW_C630}/qcadsp850.mbn: "
	MD5_QCADSP850=`md5sum "${PATH_FW_C630}"/qcadsp850.mbn |awk '{print $1}'`
	if [ -z "${firmware_md5[${MD5_QCADSP850}]}" ]; then
		echo "Failed"
	else
		echo "Passed"
	fi

	echo -n "Checking ${PATH_FW_C630}/qccdsp850.mbn: "
	MD5_QCCDSP850=`md5sum "${PATH_FW_C630}"/qccdsp850.mbn |awk '{print $1}'`
	if [ -z "${firmware_md5[${MD5_QCCDSP850}]}" ]; then
		echo "Failed"
	else
		echo "Passed"
	fi

	echo -n "Checking ${PATH_FW_C630}/qcdsp1v2850.mbn: "
	MD5_QCDSP1V2850=`md5sum "${PATH_FW_C630}"/qcdsp1v2850.mbn |awk '{print $1}'`
	if [ -z "${firmware_md5[${MD5_QCDSP1V2850}]}" ]; then
		echo "Failed"
	else
		echo "Passed"
	fi

	echo -n "Checking ${PATH_FW_C630}/qcdsp2850.mbn: "
	MD5_QCDSP2850=`md5sum "${PATH_FW_C630}"/qcdsp2850.mbn |awk '{print $1}'`
	if [ -z "${firmware_md5[${MD5_QCDSP2850}]}" ]; then
		echo "Failed"
	else
		echo "Passed"
	fi

	echo -n "Checking ${PATH_FW_C630}/modem.mdt: "
	MD5_MODEM=`md5sum "${PATH_FW_C630}"/modem.mdt |awk '{print $1}'`
	if [ -z "${firmware_md5[${MD5_MODEM}]}" ]; then
		echo "Failed"
	else
		echo "Passed"
	fi

	echo -n "Checking ${PATH_FW_C630}/wlanmdsp.mbn: "
	MD5_WLANMDSP=`md5sum "${PATH_FW_C630}"/wlanmdsp.mbn |awk '{print $1}'`
	if [ -z "${firmware_md5[${MD5_WLANMDSP}]}" ]; then
		echo "Failed"
	else
		echo "Passed"
	fi

###################################################################################################################################################
# INSTALL
###################################################################################################################################################
	BKUP_DATETIME=`date +'%Y%m%dT%H%M%S'`
	PATH_LIBFW_ATH10K="/lib/firmware/ath10k"
	echo -e "\n${TXT_UNDERLINE}Install firmware...${TXT_NORMAL}"
	if [ -e "${PATH_LIBFW_ATH10K}/WCN3990" ]; then
		echo -n "Backup existing ath10k firmware (Y/N): "
		read BKUP_FW_ATH10K
		if [[ "${BKUP_FW_ATH10K}" == "Y" ]] || [[ "${BKUP_FW_ATH10K}" == "y" ]]; then
			echo -n "Moving ${PATH_LIBFW_ATH10K}/WCN3990 to ${PATH_LIBFW_ATH10K}/WCN3990.${BKUP_DATETIME}: "
			sudo mv "${PATH_LIBFW_ATH10K}/WCN3990" "${PATH_LIBFW_ATH10K}/WCN3990.${BKUP_DATETIME}" &> /dev/null
			done_failedexit $?
		else
			echo -n "Deleting old Atheros firmware: "
			sudo rm -rf ${PATH_LIBFW_ATH10K}/WCN3990 &> /dev/null
			done_failedexit $?
		fi
	fi
	echo -n "Copying new Atheros ath10k firmware: "
	sudo cp -r "${PATH_FW_ATH10K}" "${PATH_LIBFW_ATH10K}" &> /dev/null
	done_failedexit $?
	sudo chown -R root:root "${PATH_LIBFW_ATH10K}"				# Reset ownership

	PATH_LIBFW_QCOM="/lib/firmware/qcom"
	if [ -e "${PATH_LIBFW_QCOM}/c630" ]; then
		echo -n "Backup existing Qualcomm DSP firmware (Y/N): "
		read BKUP_FW_QCDSP
		if [[ "${BKUP_FW_QCDSP}" == "Y" ]] || [[ "${BKUP_FW_ATH10K}" == "y" ]]; then
			echo -n "Moving ${PATH_LIBFW_QCOM}/c630 to ${PATH_LIBFW_QCOM}/c630.${BKUP_DATETIME}: "
			sudo mv "${PATH_LIBFW_QCOM}/c630" "${PATH_LIBFW_QCOM}/c630.${BKUP_DATETIME}" &> /dev/null
			done_failedexit $?
		else
			echo -n "Deleting old Qualcomm DSP firmware: "
			sudo rm -rf ${PATH_LIBFW_QCOM}/c630 &> /dev/null
			done_failedexit $?
		fi
	fi
	echo -n "Copying new Qualcomm DSP firmware: "
	sudo cp -r "${PATH_FW_C630}" "${PATH_LIBFW_QCOM}" &> /dev/null
	done_failedexit $?
	sudo chown -R root:root "${PATH_LIBFW_QCOM}"				# Reset ownership
fi
