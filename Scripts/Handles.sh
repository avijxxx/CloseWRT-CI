#!/bin/bash

PKG_PATH="$GITHUB_WORKSPACE/wrt/package/"

#预置HomeProxy数据
if [ -d *"homeproxy"* ]; then
	echo " "

	HP_RULE="surge"
	HP_PATH="homeproxy/root/etc/homeproxy"

	rm -rf ./$HP_PATH/resources/*

	git clone -q --depth=1 --single-branch --branch "release" "https://github.com/Loyalsoldier/surge-rules.git" ./$HP_RULE/
	cd ./$HP_RULE/ && RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*")

	echo $RES_VER | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver
	awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
	sed 's/^\.//g' direct.txt > china_list.txt ; sed 's/^\.//g' gfw.txt > gfw_list.txt
	mv -f ./{china_*,gfw_list}.{ver,txt} ../$HP_PATH/resources/

	cd .. && rm -rf ./$HP_RULE/

	cd $PKG_PATH && echo "homeproxy date has been updated!"
fi

#修改argon主题字体和颜色
if [ -d *"luci-theme-argon"* ]; then
	echo " "

	cd ./luci-theme-argon/

	sed -i "s/primary '.*'/primary '#31a1a1'/; s/'0.2'/'0.5'/; s/'none'/'bing'/; s/'600'/'normal'/" ./luci-app-argon-config/root/etc/config/argon

	cd $PKG_PATH && echo "theme-argon has been fixed!"
fi

#修改aurora菜单式样
if [ -d *"luci-app-aurora-config"* ]; then
	echo " "

	cd ./luci-app-aurora-config/

	sed -i "s/nav_submenu_type '.*'/nav_submenu_type 'boxed-dropdown'/g" $(find ./root/ -type f -name "*aurora")

	cd $PKG_PATH && echo "theme-aurora has been fixed!"
fi

#修改qca-nss-drv启动顺序
NSS_DRV="../feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
if [ -f "$NSS_DRV" ]; then
	echo " "

	sed -i 's/START=.*/START=85/g' $NSS_DRV

	cd $PKG_PATH && echo "qca-nss-drv has been fixed!"
fi

#修改qca-nss-pbuf启动顺序
NSS_PBUF="./kernel/mac80211/files/qca-nss-pbuf.init"
if [ -f "$NSS_PBUF" ]; then
	echo " "

	sed -i 's/START=.*/START=86/g' $NSS_PBUF

	cd $PKG_PATH && echo "qca-nss-pbuf has been fixed!"
fi

#修复TailScale配置文件冲突
TS_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/tailscale/Makefile")
if [ -f "$TS_FILE" ]; then
	echo " "

	sed -i '/\/files/d' $TS_FILE

	cd $PKG_PATH && echo "tailscale has been fixed!"
fi

#修复patch-kernel.sh删除.orig文件导致Rust校验失败
PK_FILE="$GITHUB_WORKSPACE/wrt/scripts/patch-kernel.sh"
if [ -f "$PK_FILE" ]; then
	echo " "

	sed -i '/Check for rejects/,/^fi$/d; /Remove backup files/,/\.orig.*-exec rm/d' "$PK_FILE"

	cd $PKG_PATH && echo "patch-kernel.sh has been fixed!"
fi

#修复DiskMan编译失败
DM_FILE="./luci-app-diskman/applications/luci-app-diskman/Makefile"
if [ -f "$DM_FILE" ]; then
	echo " "

	sed -i '/ntfs-3g-utils /d' $DM_FILE

	cd $PKG_PATH && echo "diskman has been fixed!"
fi

#修复luci-app-netspeedtest相关问题
if [ -d *"luci-app-netspeedtest"* ]; then
	echo " "

	cd ./luci-app-netspeedtest/

	sed -i '$a\exit 0' ./netspeedtest/files/99_netspeedtest.defaults
	sed -i 's/ca-certificates/ca-bundle/g' ./speedtest-cli/Makefile

	cd $PKG_PATH && echo "netspeedtest has been fixed!"
fi

#通用函数：从GitHub Releases下载文件到固件文件系统
DOWNLOAD_RELEASE_FILE() {
	local PKG_REPO=$1
	local FILE_KEYWORD=$2
	local TARGET_DIR=${3:-"/usr/bin"}
	local COPY_FILES=$4

	echo "======================="
	echo "Downloading from $PKG_REPO releases..."

	local API_URL="https://api.github.com/repos/$PKG_REPO/releases/latest"
	local DOWNLOAD_URL=$(curl -sL $API_URL | grep "browser_download_url.*$FILE_KEYWORD" | cut -d '"' -f 4 | head -1)

	if [ -z "$DOWNLOAD_URL" ]; then
		echo "✗ Error: File matching '$FILE_KEYWORD' not found in latest release"
		return 1
	fi

	local FILE_NAME=$(basename $DOWNLOAD_URL)
	local TEMP_DIR="/tmp/release_download_$$"
	mkdir -p $TEMP_DIR

	echo "Downloading: $DOWNLOAD_URL"
	wget -q -O "$TEMP_DIR/$FILE_NAME" "$DOWNLOAD_URL"

	if [ $? -ne 0 ]; then
		echo "✗ Error: Download failed"
		rm -rf $TEMP_DIR
		return 1
	fi

	local FILES_DIR="$GITHUB_WORKSPACE/wrt/files$TARGET_DIR"
	mkdir -p "$FILES_DIR"

	# 根据文件后缀自动判断是否需要解压
	case "$FILE_NAME" in
		*.zip)
			echo "Extracting ZIP archive..."
			local EXTRACT_DIR="$TEMP_DIR/extracted"
			mkdir -p "$EXTRACT_DIR"
			unzip -q "$TEMP_DIR/$FILE_NAME" -d "$EXTRACT_DIR"

			if [ -n "$COPY_FILES" ]; then
				echo "Copying specified files: $COPY_FILES"
				for FILE_SPEC in $COPY_FILES; do
					find "$EXTRACT_DIR" -type f -name "$FILE_SPEC" -exec cp {} "$FILES_DIR/" \;
				done
			else
				echo "Copying all extracted files..."
				find "$EXTRACT_DIR" -type f -exec cp {} "$FILES_DIR/" \;
			fi
			;;
		*.tar.gz|*.tgz)
			echo "Extracting TAR.GZ archive..."
			local EXTRACT_DIR="$TEMP_DIR/extracted"
			mkdir -p "$EXTRACT_DIR"
			tar -xzf "$TEMP_DIR/$FILE_NAME" -C "$EXTRACT_DIR"

			if [ -n "$COPY_FILES" ]; then
				echo "Copying specified files: $COPY_FILES"
				for FILE_SPEC in $COPY_FILES; do
					find "$EXTRACT_DIR" -type f -name "$FILE_SPEC" -exec cp {} "$FILES_DIR/" \;
				done
			else
				echo "Copying all extracted files..."
				find "$EXTRACT_DIR" -type f -exec cp {} "$FILES_DIR/" \;
			fi
			;;
		*.tar.bz2|*.tbz2)
			echo "Extracting TAR.BZ2 archive..."
			local EXTRACT_DIR="$TEMP_DIR/extracted"
			mkdir -p "$EXTRACT_DIR"
			tar -xjf "$TEMP_DIR/$FILE_NAME" -C "$EXTRACT_DIR"

			if [ -n "$COPY_FILES" ]; then
				echo "Copying specified files: $COPY_FILES"
				for FILE_SPEC in $COPY_FILES; do
					find "$EXTRACT_DIR" -type f -name "$FILE_SPEC" -exec cp {} "$FILES_DIR/" \;
				done
			else
				echo "Copying all extracted files..."
				find "$EXTRACT_DIR" -type f -exec cp {} "$FILES_DIR/" \;
			fi
			;;
		*)
			echo "Copying file directly (no extraction needed)..."
			cp "$TEMP_DIR/$FILE_NAME" "$FILES_DIR/"
			;;
	esac

	chmod +x "$FILES_DIR"/* 2>/dev/null
	rm -rf $TEMP_DIR

	echo "✓ Files installed to: $FILES_DIR"
	ls -lh "$FILES_DIR"
	echo "======================="
}

# 调用示例
# DOWNLOAD_RELEASE_FILE "项目地址" "文件关键字" "目标路径(可选,默认/usr/bin)" "需要复制的文件名(空格分隔,留空则全部)"
#
# 注意：函数会根据文件后缀自动判断是否解压
# - 压缩包格式：.zip / .tar.gz / .tgz / .tar.bz2 / .tbz2 → 自动解压
# - 非压缩格式：.sh / .bin / .json / .conf 等 → 直接复制
#
# === 压缩包示例（自动解压） ===
# 复制部分文件（第4参数指定文件名）：
# DOWNLOAD_RELEASE_FILE "EasyTier/EasyTier" "easytier-linux-aarch64" "/usr/bin" "easytier-core easytier-cli"
# 复制全部文件（第4参数留空）：
# DOWNLOAD_RELEASE_FILE "SagerNet/sing-box" "sing-box-.*-linux-arm64.tar.gz" "/usr/bin" ""
#
# === 非压缩文件示例（直接复制） ===
# DOWNLOAD_RELEASE_FILE "user/scripts" "install.sh" "/usr/sbin" ""
DOWNLOAD_RELEASE_FILE "EasyTier/EasyTier" "easytier-linux-aarch64" "/usr/bin" "easytier-core easytier-cli"
