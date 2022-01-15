#!/bin/sh

: <<-'EOF'
Copyright 2017-2019 Xingwang Liao <kuoruan@gmail.com>
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
	http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
EOF

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# �汾��Ϣ�������޸�
# =================
SHELL_VERSION=25
CONFIG_VERSION=6
INIT_VERSION=3
# =================

KCPTUN_INSTALL_DIR='/usr/local/kcptun'
KCPTUN_LOG_DIR='/var/log/kcptun'
KCPTUN_RELEASES_URL='https://api.github.com/repos/xtaci/kcptun/releases'
KCPTUN_LATEST_RELEASE_URL="${KCPTUN_RELEASES_URL}/latest"
KCPTUN_TAGS_URL='https://github.com/xtaci/kcptun/tags'

BASE_URL='https://github.com/kuoruan/shell-scripts/raw/master/kcptun'
SHELL_VERSION_INFO_URL="${BASE_URL}/version.json"

JQ_DOWNLOAD_URL="https://github.com/stedolan/jq/releases/download/jq-1.5/"
JQ_LINUX32_URL="${JQ_DOWNLOAD_URL}/jq-linux32"
JQ_LINUX64_URL="${JQ_DOWNLOAD_URL}/jq-linux64"
JQ_LINUX32_HASH='ab440affb9e3f546cf0d794c0058543eeac920b0cd5dff660a2948b970beb632'
JQ_LINUX64_HASH='c6b3a7d7d3e7b70c6f51b706a3b90bd01833846c54d32ca32f0027f00226ff6d'
JQ_BIN="${KCPTUN_INSTALL_DIR}/bin/jq"

SUPERVISOR_SERVICE_FILE_DEBIAN_URL="${BASE_URL}/startup/supervisord.init.debain"
SUPERVISOR_SERVICE_FILE_REDHAT_URL="${BASE_URL}/startup/supervisord.init.redhat"
SUPERVISOR_SYSTEMD_FILE_URL="${BASE_URL}/startup/supervisord.systemd"

# Ĭ�ϲ���
# =======================
D_LISTEN_PORT=29900
D_TARGET_ADDR='127.0.0.1'
D_TARGET_PORT=12984
D_KEY="very fast"
D_CRYPT='aes'
D_MODE='fast'
D_MTU=1350
D_SNDWND=512
D_RCVWND=512
D_DATASHARD=10
D_PARITYSHARD=3
D_DSCP=0
D_NOCOMP='false'
D_QUIET='false'
D_TCP='false'
D_SNMPPERIOD=60
D_PPROF='false'

# ���ز���
D_ACKNODELAY='false'
D_NODELAY=1
D_INTERVAL=20
D_RESEND=2
D_NC=1
D_SOCKBUF=4194304
D_SMUXBUF=4194304
D_KEEPALIVE=10
# ======================

# ��ǰѡ���ʵ�� ID
current_instance_id=""
run_user='kcptun'

clear

cat >&1 <<-'EOF'
#########################################################
# Kcptun �����һ����װ�ű�                             #
# �ýű�֧�� Kcptun ����˵İ�װ�����¡�ж�ؼ�����      #
# �ű�����: Index <kuoruan@gmail.com>                   #
# ���߲���: https://blog.kuoruan.com/                   #
# Github: https://github.com/kuoruan/shell-scripts      #
# QQ����Ⱥ: 43391448, 68133628                          #
#           633945405                                   #
#########################################################
EOF

# ��ӡ������Ϣ
usage() {
	cat >&1 <<-EOF

	��ʹ��: $0 <option>

	��ʹ�õĲ��� <option> ����:

	    install          ��װ
	    uninstall        ж��
	    update           ������
	    manual           �Զ��� Kcptun �汾��װ
	    help             �鿴�ű�ʹ��˵��
	    add              ���һ��ʵ��, ��˿ڼ���
	    reconfig <id>    ��������ʵ��
	    show <id>        ��ʾʵ����ϸ����
	    log <id>         ��ʾʵ����־
	    del <id>         ɾ��һ��ʵ��

	ע: ���������е� <id> ��ѡ, �������ʵ����ID
	    ��ʹ�� 1, 2, 3 ... �ֱ��Ӧʵ�� kcptun, kcptun2, kcptun3 ...
	    ����ָ�� <id>, ��Ĭ��Ϊ 1

	Supervisor ����:
	    service supervisord {start|stop|restart|status}
	                        {����|�ر�|����|�鿴״̬}
	Kcptun �������:
	    supervisorctl {start|stop|restart|status} kcptun<id>
	                  {����|�ر�|����|�鿴״̬}
	EOF

	exit $1
}

# �ж������Ƿ����
command_exists() {
	command -v "$@" >/dev/null 2>&1
}

# �ж����������Ƿ�Ϊ����
is_number() {
	expr "$1" + 1 >/dev/null 2>&1
}

# �����������
any_key_to_continue() {
	echo "�밴����������� Ctrl + C �˳�"
	local saved=""
	saved="$(stty -g)"
	stty -echo
	stty cbreak
	dd if=/dev/tty bs=1 count=1 2>/dev/null
	stty -raw
	stty echo
	stty $saved
}

first_character() {
	if [ -n "$1" ]; then
		echo "$1" | cut -c1
	fi
}

# ����Ƿ���� root Ȩ��
check_root() {
	local user=""
	user="$(id -un 2>/dev/null || true)"
	if [ "$user" != "root" ]; then
		cat >&2 <<-'EOF'
		Ȩ�޴���, ��ʹ�� root �û����д˽ű�!
		EOF
		exit 1
	fi
}

# ��ȡ��������IP��ַ
get_server_ip() {
	local server_ip=""
	local interface_info=""

	if command_exists ip; then
		interface_info="$(ip addr)"
	elif command_exists ifconfig; then
		interface_info="$(ifconfig)"
	fi

	server_ip=$(echo "$interface_info" | \
		grep -oE "[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}" | \
		grep -vE "^192\.168|^172\.1[6-9]\.|^172\.2[0-9]\.|^172\.3[0-2]\.|^10\.|^127\.|^255\.|^0\." | \
		head -n 1)

	# �Զ���ȡʧ��ʱ��ͨ����վ�ṩ�� API ��ȡ������ַ
	if [ -z "$server_ip" ]; then
		 server_ip="$(wget -qO- --no-check-certificate https://ipv4.icanhazip.com)"
	fi

	echo "$server_ip"
}

# ���� selinux
disable_selinux() {
	local selinux_config='/etc/selinux/config'
	if [ -s "$selinux_config" ]; then
		if grep -q "SELINUX=enforcing" "$selinux_config"; then
			sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' "$selinux_config"
			setenforce 0
		fi
	fi
}

# ��ȡ��ǰ����ϵͳ��Ϣ
get_os_info() {
	lsb_dist=""
	dist_version=""
	if command_exists lsb_release; then
		lsb_dist="$(lsb_release -si)"
	fi

	if [ -z "$lsb_dist" ]; then
		[ -r /etc/lsb-release ] && lsb_dist="$(. /etc/lsb-release && echo "$DISTRIB_ID")"
		[ -r /etc/debian_version ] && lsb_dist='debian'
		[ -r /etc/fedora-release ] && lsb_dist='fedora'
		[ -r /etc/oracle-release ] && lsb_dist='oracleserver'
		[ -r /etc/centos-release ] && lsb_dist='centos'
		[ -r /etc/redhat-release ] && lsb_dist='redhat'
		[ -r /etc/photon-release ] && lsb_dist='photon'
		[ -r /etc/os-release ] && lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi
	

	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"

	if [ "${lsb_dist}" = "redhatenterpriseserver" ]; then
		lsb_dist='redhat'
	fi

	case "$lsb_dist" in
		ubuntu)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/lsb-release ]; then
				dist_version="$(. /etc/lsb-release && echo "$DISTRIB_CODENAME")"
			fi
			;;

		debian|raspbian)
			dist_version="$(cat /etc/debian_version | sed 's/\/.*//' | sed 's/\..*//')"
			case "$dist_version" in
				9)
					dist_version="stretch"
					;;
				8)
					dist_version="jessie"
					;;
				7)
					dist_version="wheezy"
					;;
			esac
			;;

		oracleserver)
			lsb_dist="oraclelinux"
			dist_version="$(rpm -q --whatprovides redhat-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//')"
			;;

		fedora|centos|redhat)
			dist_version="$(rpm -q --whatprovides ${lsb_dist}-release --queryformat "%{VERSION}\n" | sed 's/\/.*//' | sed 's/\..*//' | sed 's/Server*//' | sort | tail -1)"
			;;

		"vmware photon")
			lsb_dist="photon"
			dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			;;

		*)
			if command_exists lsb_release; then
				dist_version="$(lsb_release --codename | cut -f2)"
			fi
			if [ -z "$dist_version" ] && [ -r /etc/os-release ]; then
				dist_version="$(. /etc/os-release && echo "$VERSION_ID")"
			fi
			;;
	esac

	if [ -z "$lsb_dist" ] || [ -z "$dist_version" ]; then
		cat >&2 <<-EOF
		�޷�ȷ��������ϵͳ�汾��Ϣ��
		����ϵ�ű����ߡ�
		EOF
		exit 1
	fi
}

# ��ȡ�������ܹ��� Kcptun ������ļ���׺��
get_arch() {
	architecture="$(uname -m)"
	case "$architecture" in
		amd64|x86_64)
			spruce_type='linux-amd64'
			file_suffix='linux_amd64'
			;;
		i386|i486|i586|i686|x86)
			spruce_type='linux-386'
			file_suffix='linux_386'
			;;
		*)
			cat 1>&2 <<-EOF
			��ǰ�ű���֧�� 32 λ �� 64 λϵͳ
			���ϵͳΪ: $architecture
			EOF
			exit 1
			;;
	esac
}

# ��ȡ API ����
get_content() {
	local url="$1"
	local retry=0

	local content=""
	get_network_content() {
		if [ $retry -ge 3 ]; then
			cat >&2 <<-EOF
			��ȡ������Ϣʧ��!
			URL: ${url}
			��װ�ű���Ҫ�ܷ��ʵ� github.com��������������硣
			ע��: һЩ���ڷ����������޷��������� github.com��
			EOF
			exit 1
		fi

		# �����еĻ��з��滻Ϊ�Զ����ǩ����ֹ jq ����ʧ��
		content="$(wget -qO- --no-check-certificate "$url" | sed -r 's/(\\r)?\\n/#br#/g')"

		if [ "$?" != "0" ] || [ -z "$content" ]; then
			retry=$(expr $retry + 1)
			get_network_content
		fi
	}

	get_network_content
	echo "$content"
}

# �����ļ��� Ĭ������ 3 ��
download_file() {
	local url="$1"
	local file="$2"
	local verify="$3"
	local retry=0
	local verify_cmd=""

	verify_file() {
		if [ -z "$verify_cmd" ] && [ -n "$verify" ]; then
			if [ "${#verify}" = "32" ]; then
				verify_cmd="md5sum"
			elif [ "${#verify}" = "40" ]; then
				verify_cmd="sha1sum"
			elif [ "${#verify}" = "64" ]; then
				verify_cmd="sha256sum"
			elif [ "${#verify}" = "128" ]; then
				verify_cmd="sha512sum"
			fi

			if [ -n "$verify_cmd" ] && ! command_exists "$verify_cmd"; then
				verify_cmd=""
			fi
		fi

		if [ -s "$file" ] && [ -n "$verify_cmd" ]; then
			(
				set -x
				echo "${verify}  ${file}" | $verify_cmd -c
			)
			return $?
		fi

		return 1
	}

	download_file_to_path() {
		if verify_file; then
			return 0
		fi

		if [ $retry -ge 3 ]; then
			rm -f "$file"
			cat >&2 <<-EOF
			�ļ����ػ�У��ʧ��! �����ԡ�
			URL: ${url}
			EOF

			if [ -n "$verify_cmd" ]; then
				cat >&2 <<-EOF
				������ض��ʧ�ܣ�������ֶ������ļ�:
				1. �����ļ� ${url}
				2. ���ļ�������Ϊ $(basename "$file")
				3. �ϴ��ļ���Ŀ¼ $(dirname "$file")
				4. �������а�װ�ű�

				ע: �ļ�Ŀ¼ . ��ʾ��ǰĿ¼��.. ��ʾ��ǰĿ¼���ϼ�Ŀ¼
				EOF
			fi
			exit 1
		fi

		( set -x; wget -O "$file" --no-check-certificate "$url" )
		if [ "$?" != "0" ] || [ -n "$verify_cmd" ] && ! verify_file; then
			retry=$(expr $retry + 1)
			download_file_to_path
		fi
	}

	download_file_to_path
}

# ��װ jq ���ڽ��������� json �ļ�
# jq �ѽ���󲿷� Linux ���а������ֿ⣬
#  	URL: https://stedolan.github.io/jq/download/
# ��Ϊ�˷�ֹ��Щϵͳ��װʧ�ܣ�����ͨ���ű����ṩ�ˡ�
install_jq() {
	check_jq() {
		if [ ! -f "$JQ_BIN" ]; then
			return 1
		fi

		[ ! -x "$JQ_BIN" ] && chmod a+x "$JQ_BIN"

		if ( $JQ_BIN --help 2>/dev/null | grep -q "JSON" ); then
			is_checked_jq="true"
			return 0
		else
			rm -f "$JQ_BIN"
			return 1
		fi
	}

	if [ -z "$is_checked_jq" ] && ! check_jq; then
		local dir=""
		dir="$(dirname "$JQ_BIN")"
		if [ ! -d "$dir" ]; then
			(
				set -x
				mkdir -p "$dir"
			)
		fi

		if [ -z "$architecture" ]; then
			get_arch
		fi

		case "$architecture" in
			amd64|x86_64)
				download_file "$JQ_LINUX64_URL" "$JQ_BIN" "$JQ_LINUX64_HASH"
				;;
			i386|i486|i586|i686|x86)
				download_file "$JQ_LINUX32_URL" "$JQ_BIN" "$JQ_LINUX32_HASH"
				;;
		esac

		if ! check_jq; then
			cat >&2 <<-EOF
			δ�ҵ������ڵ�ǰϵͳ�� JSON ������� jq
			EOF
			exit 1
		fi

		return 0
	fi
}

# ��ȡ json �ļ���ĳһ���ֵ
get_json_string() {
	install_jq

	local content="$1"
	local selector="$2"
	local regex="$3"

	local str=""
	if [ -n "$content" ]; then
		str="$(echo "$content" | $JQ_BIN -r "$selector" 2>/dev/null)"

		if [ -n "$str" ] && [ -n "$regex" ]; then
			str="$(echo "$str" | grep -oE "$regex")"
		fi
	fi
	echo "$str"
}

# ��ȡ��ǰʵ���������ļ�·�������������
# * config: kcptun ����������ļ�
# * log: kcptun ��־�ļ�·��
# * snmp: kcptun snmp ��־�ļ�·��
# * supervisor: ʵ���� supervisor �ļ�·��
get_current_file() {
	case "$1" in
		config)
			printf '%s/server-config%s.json' "$KCPTUN_INSTALL_DIR" "$current_instance_id"
			;;
		log)
			printf '%s/server%s.log' "$KCPTUN_LOG_DIR" "$current_instance_id"
			;;
		snmp)
			printf '%s/snmplog%s.log' "$KCPTUN_LOG_DIR" "$current_instance_id"
			;;
		supervisor)
			printf '/etc/supervisor/conf.d/kcptun%s.conf' "$current_instance_id"
			;;
	esac
}

# ��ȡʵ������
get_instance_count() {
	if [ -d '/etc/supervisor/conf.d/' ]; then
		ls -l '/etc/supervisor/conf.d/' | grep "^-" | awk '{print $9}' | grep -cP "^kcptun\d*\.conf$"
	else
		echo "0"
	fi
}

# ͨ�� API ��ȡ��Ӧ�汾�� Kcptun �� release ��Ϣ
# ���� Kcptun �汾��
get_kcptun_version_info() {
	local request_version="$1"

	local version_content=""
	if [ -n "$request_version" ]; then
		local json_content=""
		json_content="$(get_content "$KCPTUN_RELEASES_URL")"
		local version_selector=".[] | select(.tag_name == \"${request_version}\")"
		version_content="$(get_json_string "$json_content" "$version_selector")"
	else
		version_content="$(get_content "$KCPTUN_LATEST_RELEASE_URL")"
	fi

	if [ -z "$version_content" ]; then
		return 1
	fi

	if [ -z "$spruce_type" ]; then
		get_arch
	fi

	local url_selector=".assets[] | select(.name | contains(\"${spruce_type}\")) | .browser_download_url"
	kcptun_release_download_url="$(get_json_string "$version_content" "$url_selector")"

	if [ -z "$kcptun_release_download_url" ]; then
		return 1
	fi

	kcptun_release_tag_name="$(get_json_string "$version_content" '.tag_name')"
	kcptun_release_name="$(get_json_string "$version_content" '.name')"
	kcptun_release_prerelease="$(get_json_string "$version_content" '.prerelease')"
	kcptun_release_publish_time="$(get_json_string "$version_content" '.published_at')"
	kcptun_release_html_url="$(get_json_string "$version_content" '.html_url')"

	local body_content="$(get_json_string "$version_content" '.body')"
	local body="$(echo "$body_content" | sed 's/#br#/\n/g' | grep -vE '(^```)|(^>)|(^[[:space:]]*$)|(SUM$)')"

	kcptun_release_body="$(echo "$body" | grep -vE "[0-9a-zA-Z]{32,}")"

	local file_verify=""
	file_verify="$(echo "$body" | grep "$spruce_type")"

	if [ -n "$file_verify" ]; then
		local i="1"
		local split=""
		while true
		do
			split="$(echo "$file_verify" | cut -d ' ' -f$i)"

			if [ -n "$split" ] && ( echo "$split" | grep -qE "^[0-9a-zA-Z]{32,}$" ); then
				kcptun_release_verify="$split"
				break
			elif [ -z "$split" ]; then
				break
			fi

			i=$(expr $i + 1)
		done
	fi

	return 0
}

# ��ȡ�ű��汾��Ϣ
get_shell_version_info() {
	local shell_version_content=""
	shell_version_content="$(get_content "$SHELL_VERSION_INFO_URL")"
	if [ -z "$shell_version_content" ]; then
		return 1
	fi

	new_shell_version="$(get_json_string "$shell_version_content" '.shell_version' '[0-9]+')"
	new_config_version="$(get_json_string "$shell_version_content" '.config_version' '[0-9]+')"
	new_init_version="$(get_json_string "$shell_version_content" '.init_version' '[0-9]+')"

	shell_change_log="$(get_json_string "$shell_version_content" '.change_log')"
	config_change_log="$(get_json_string "$shell_version_content" '.config_change_log')"
	init_change_log="$(get_json_string "$shell_version_content" '.init_change_log')"
	new_shell_url="$(get_json_string "$shell_version_content" '.shell_url')"


	if [ -z "$new_shell_version" ]; then
		new_shell_version="0"
	fi
	if [ -z "$new_config_version" ]; then
		new_config_version="0"
	fi
	if [ -z "$new_init_version" ]; then
		new_init_version="0"
	fi

	return 0
}

# ���ز���װ Kcptun
install_kcptun() {
	if [ -z "$kcptun_release_download_url" ]; then
		get_kcptun_version_info "$1"

		if [ "$?" != "0" ]; then
			cat >&2 <<-'EOF'
			��ȡ Kcptun �汾��Ϣ�����ص�ַʧ��!
			������ GitHub �İ棬���ߴ������ȡ�������ݲ���ȷ��
			����ϵ�ű����ߡ�
			EOF
			exit 1
		fi
	fi

	local kcptun_file_name="kcptun-${kcptun_release_tag_name}.tar.gz"
	download_file "$kcptun_release_download_url" "$kcptun_file_name" "$kcptun_release_verify"

	if [ ! -d "$KCPTUN_INSTALL_DIR" ]; then
		(
			set -x
			mkdir -p "$KCPTUN_INSTALL_DIR"
		)
	fi

	if [ ! -d "$KCPTUN_LOG_DIR" ]; then
		(
			set -x
			mkdir -p "$KCPTUN_LOG_DIR"
			chmod a+w "$KCPTUN_LOG_DIR"
		)
	fi

	(
		set -x
		tar -zxf "$kcptun_file_name" -C "$KCPTUN_INSTALL_DIR"
		sleep 3
	)

	local kcptun_server_file=""
	kcptun_server_file="$(get_kcptun_server_file)"

	if [ ! -f "$kcptun_server_file" ]; then
		cat >&2 <<-'EOF'
		δ�ڽ�ѹ�ļ����ҵ� Kcptun �����ִ���ļ�!
		ͨ���ⲻ�ᷢ�������ܵ�ԭ���� Kcptun ���ߴ���ļ���ʱ��������ļ�����
		����Գ������°�װ��������ϵ�ű����ߡ�
		EOF
		exit 1
	fi

	chmod a+x "$kcptun_server_file"

	if [ -z "$(get_installed_version)" ]; then
		cat >&2 <<-'EOF'
		�޷��ҵ��ʺϵ�ǰ�������� kcptun ��ִ���ļ�
		����Գ��Դ�Դ����롣
		EOF
		exit 1
	fi

	rm -f "$kcptun_file_name" "${KCPTUN_INSTALL_DIR}/client_$file_suffix"
}

# ��װ�������
install_deps() {
	if [ -z "$lsb_dist" ]; then
		get_os_info
	fi

	case "$lsb_dist" in
		ubuntu|debian|raspbian)
			local did_apt_get_update=""
			apt_get_update() {
				if [ -z "$did_apt_get_update" ]; then
					( set -x; sleep 3; apt-get update )
					did_apt_get_update=1
				fi
			}

			if ! command_exists wget; then
				apt_get_update
				( set -x; sleep 3; apt-get install -y -q wget ca-certificates )
			fi

			if ! command_exists awk; then
				apt_get_update
				( set -x; sleep 3; apt-get install -y -q gawk )
			fi

			if ! command_exists tar; then
				apt_get_update
				( set -x; sleep 3; apt-get install -y -q tar )
			fi

			if ! command_exists pip; then
				apt_get_update
				( set -x; sleep 3; apt-get install -y -q python-pip || true )
			fi

			if ! command_exists python; then
				apt_get_update
				( set -x; sleep 3; apt-get install -y -q python )
			fi
			;;
		fedora|centos|redhat|oraclelinux|photon)
			if [ "$lsb_dist" = "fedora" ] && [ "$dist_version" -ge "22" ]; then
				if ! command_exists wget; then
					( set -x; sleep 3; dnf -y -q install wget ca-certificates )
				fi

				if ! command_exists awk; then
					( set -x; sleep 3; dnf -y -q install gawk )
				fi

				if ! command_exists tar; then
					( set -x; sleep 3; dnf -y -q install tar )
				fi

				if ! command_exists pip; then
					( set -x; sleep 3; dnf -y -q install python-pip || true )
				fi

				if ! command_exists python; then
					( set -x; sleep 3; dnf -y -q install python )
				fi
			elif [ "$lsb_dist" = "photon" ]; then
				if ! command_exists wget; then
					( set -x; sleep 3; tdnf -y install wget ca-certificates )
				fi

				if ! command_exists awk; then
					( set -x; sleep 3; tdnf -y install gawk )
				fi

				if ! command_exists tar; then
					( set -x; sleep 3; tdnf -y install tar )
				fi

				if ! command_exists pip; then
					( set -x; sleep 3; tdnf -y install python-pip || true )
				fi

				if ! command_exists python; then
					( set -x; sleep 3; tdnf -y install python )
				fi
			else
				if ! command_exists wget; then
					( set -x; sleep 3; yum -y -q install wget ca-certificates )
				fi

				if ! command_exists awk; then
					( set -x; sleep 3; yum -y -q install gawk )
				fi

				if ! command_exists tar; then
					( set -x; sleep 3; yum -y -q install tar )
				fi

				# CentOS �Ⱥ�ñϵ����ϵͳ��������п��ܲ����� python-pip
				# �����Ȱ�װ epel-release
				if ! command_exists pip; then
					( set -x; sleep 3; yum -y -q install python-pip || true )
				fi

				# ��� python-pip ��װʧ�ܣ�����Ƿ��Ѱ�װ python ����
				if ! command_exists python; then
					( set -x; sleep 3; yum -y -q install python )
				fi
			fi
			;;
		*)
			cat >&2 <<-EOF
			��ʱ��֧�ֵ�ǰϵͳ��${lsb_dist} ${dist_version}
			EOF

			exit 1
			;;
	esac

	# �����ж����Ƿ���ڰ�װʧ�ܵ������������Ĭ�ϲ����� python-pip �İ�װʧ�ܣ�
	# ��������ͳһ��Ⲣ�ٴΰ�װ pip ����
	if [ "$?" != 0 ]; then
		cat >&2 <<-'EOF'
		һЩ���������װʧ�ܣ�
		��鿴��־������
		EOF
		exit 1
	fi

	install_jq
}

# ��װ supervisor
install_supervisor() {
	if [ -s /etc/supervisord.conf ] && command_exists supervisord; then
		cat >&2 <<-EOF
		��⵽������ͨ��������ʽ��װ�� Supervisor , ���ͱ��ű���װ�� Supervisor ������ͻ
		�Ƽ��㱸�ݵ�ǰ Supervisor ���ú�ж��ԭ�а汾
		�Ѱ�װ�� Supervisor �����ļ�·��Ϊ: /etc/supervisord.conf
		ͨ�����ű���װ�� Supervisor �����ļ�·��Ϊ: /etc/supervisor/supervisord.conf
		�����ʹ����������������ԭ�������ļ�:

		    mv /etc/supervisord.conf /etc/supervisord.conf.bak
		EOF

		exit 1
	fi

	if ! command_exists python; then
		cat >&2 <<-'EOF'
		python ����δ��װ�������Զ���װʧ�ܣ����ֶ���װ python ������
		EOF

		exit 1
	fi

	local python_version="$(python -V 2>&1)"

	if [ "$?" != "0" ] || [ -z "$python_version" ]; then
		cat >&2 <<-'EOF'
		python �������𻵣��޷�ͨ�� python -V ����ȡ�汾�š�
		���ֶ���װ python ������
		EOF

		exit 1
	fi

	local version_string="$(echo "$python_version" | cut -d' ' -f2 | head -n1)"
	local major_version="$(echo "$version_string" | cut -d'.' -f1)"
	local minor_version="$(echo "$version_string" | cut -d'.' -f2)"

	if [ -z "$major_version" ] || [ -z "$minor_version" ] || \
		! ( is_number "$major_version" ); then
		cat >&2 <<-EOF
		��ȡ python ��С�汾��ʧ�ܣ�${python_version}
		EOF

		exit 1
	fi

	local is_python_26="false"

	if [ "$major_version" -lt "2" ] || ( \
		[ "$major_version" = "2" ] && [ "$minor_version" -lt "6" ] ); then
		cat >&2 <<-EOF
		��֧�ֵ� python �汾 ${version_string}����ǰ��֧�� python 2.6 �����ϰ汾�İ�װ��
		EOF

		exit 1
	elif [ "$major_version" = "2" ] && [ "$minor_version" = "6" ]; then
		is_python_26="true"

		cat >&1 <<-EOF
		ע�⣺��ǰ�������� python �汾Ϊ ${version_string},
		�ű��� python 2.6 �����°汾��֧�ֿ��ܻ�ʧЧ��
		�뾡������ python �汾�� >= 2.7.9 �� >= 3.4��
		EOF

		any_key_to_continue
	fi

	if ! command_exists pip; then
		# ���û�м�⵽ pip �������ǰ�������Ѿ���װ python
		# ʹ�� get-pip.py �ű�����װ pip ����
		if [ "$is_python_26" = "true" ]; then
			(
				set -x
				wget -qO- --no-check-certificate https://bootstrap.pypa.io/2.6/get-pip.py | python
			)
		else
			(
				set -x
				wget -qO- --no-check-certificate https://bootstrap.pypa.io/get-pip.py | python
			)
		fi
	fi

	# ���ʹ�ýű���װ��Ȼʧ�ܣ���ʾ�ֶ���װ
	if ! command_exists pip; then
		cat >&2 <<-EOF
		δ�ҵ��Ѱ�װ�� pip ��������ֶ���װ python-pip
		���ű��� v21 �濪ʼʹ�� pip ����װ Supervisior��

		1. ���� Debian ϵ�� Linux ϵͳ�����Գ���ʹ�ã�
		  sudo apt-get install -y python-pip �����а�װ

		2. ���� Redhat ϵ�� Linux ϵͳ�����Գ���ʹ�ã�
		  sudo yum install -y python-pip �����а�װ
		  * �����ʾδ�ҵ��������ȳ��԰�װ��epel-release ��չ�����

		3. ������Ϸ�����ʧ���ˣ���ʹ�������������ֶ���װ��
		  wget -qO- --no-check-certificate https://bootstrap.pypa.io/get-pip.py | python
		  * python 2.6 ���û���ʹ�ã�
		    wget -qO- --no-check-certificate https://bootstrap.pypa.io/2.6/get-pip.py | python

		4. pip ��װ���֮��������һ�¸������
		  pip install --upgrade pip

		  �ټ��һ�� pip �İ汾��
		  pip -V

		һ����������������а�װ�ű���
		EOF
		exit 1
	fi

	if ! ( pip --version >/dev/null 2>&1 ); then
		cat >&2 <<-EOF
		��⵽��ǰ������ pip �������𻵣�
		������� python ������
		EOF

		exit 1
	fi

	if [ "$is_python_26" != "true" ]; then
		# �Ѱ�װ pip ʱ�ȳ��Ը���һ�£�
		# ����� python 2.6���Ͳ�Ҫ�����ˣ����»ᵼ�� pip ��
		# pip ֻ֧�� python 2 >= 2.7.9
		# https://pip.pypa.io/en/stable/installing/
		(
			set -x
			pip install --upgrade pip || true
		)
	fi

	if [ "$is_python_26" = "true" ]; then
		(
			set -x
			pip install 'supervisor>=3.0.0,<4.0.0'
		)
	else
		(
			set -x
			#pip install --upgrade supervisor
		)
	fi

	if [ "$?" != "0" ]; then
		cat >&2 <<-EOF
		����: ��װ Supervisor ʧ�ܣ�
		�볢��ʹ��
		  pip install supervisor
		���ֶ���װ��
		Supervisor �� 4.0 ��ʼ�Ѳ�֧�� python 2.6 �����°汾
		python 2.6 ���û���ʹ�ã�
		  pip install 'supervisor>=3.0.0,<4.0.0'
		EOF

		exit 1
	fi

	[ ! -d /etc/supervisor/conf.d ] && (
		set -x
		mkdir -p /etc/supervisor/conf.d
	)

	if [ ! -f '/usr/local/bin/supervisord' ]; then
		(
			set -x
			ln -s "$(command -v supervisord)" '/usr/local/bin/supervisord' 2>/dev/null
		)
	fi

	if [ ! -f '/usr/local/bin/supervisorctl' ]; then
		(
			set -x
			ln -s "$(command -v supervisorctl)" '/usr/local/bin/supervisorctl' 2>/dev/null
		)
	fi

	if [ ! -f '/usr/local/bin/pidproxy' ]; then
		(
			set -x
			ln -s "$(command -v pidproxy)" '/usr/local/bin/pidproxy' 2>/dev/null
		)
	fi

	local cfg_file='/etc/supervisor/supervisord.conf'

	local rvt="0"

	if [ ! -s "$cfg_file" ]; then
		if ! command_exists echo_supervisord_conf; then
			cat >&2 <<-'EOF'
			δ�ҵ� echo_supervisord_conf, �޷��Զ����� Supervisor �����ļ�!
			�����ǵ�ǰ��װ�� supervisor �汾���͡�
			EOF
			exit 1
		fi

		(
			set -x
			echo_supervisord_conf >"$cfg_file" 2>&1
		)
		rvt="$?"
	fi

	local cfg_content="$(cat "$cfg_file")"

	# Error with supervisor config file
	if ( echo "$cfg_content" | grep -q "Traceback (most recent call last)" ) ; then
		rvt="1"

		if ( echo "$cfg_content" | grep -q "DistributionNotFound: meld3" ); then
			# https://github.com/Supervisor/meld3/issues/23
			(
				set -x
				local temp="$(mktemp -d)"
				local pwd="$(pwd)"

				download_file 'https://pypi.python.org/packages/source/m/meld3/meld3-1.0.2.tar.gz' \
					"$temp/meld3.tar.gz"

				cd "$temp"
				tar -zxf "$temp/meld3.tar.gz" --strip=1
				python setup.py install
				cd "$pwd"
			)

			if [ "$?" = "0" ] ; then
				(
					set -x
					echo_supervisord_conf >"$cfg_file" 2>/dev/null
				)
				rvt="$?"
			fi
		fi
	fi

	if [ "$rvt" != "0" ]; then
		rm -f "$cfg_file"
		echo "���� Supervisor �����ļ�ʧ��!"
		exit 1
	fi

	if ! grep -q '^files[[:space:]]*=[[:space:]]*/etc/supervisor/conf.d/\*\.conf$' "$cfg_file"; then
		if grep -q '^\[include\]$' "$cfg_file"; then
			sed -i '/^\[include\]$/a files = \/etc\/supervisor\/conf.d\/\*\.conf' "$cfg_file"
		else
			sed -i '$a [include]\nfiles = /etc/supervisor/conf.d/*.conf' "$cfg_file"
		fi
	fi

	download_startup_file
}

download_startup_file() {
	local supervisor_startup_file=""
	local supervisor_startup_file_url=""

	if command_exists systemctl; then
		supervisor_startup_file="/etc/systemd/system/supervisord.service"
		supervisor_startup_file_url="$SUPERVISOR_SYSTEMD_FILE_URL"

		download_file "$supervisor_startup_file_url" "$supervisor_startup_file"
		(
			set -x
			# ɾ���ɰ� service �ļ�

			local old_service_file="/lib/systemd/system/supervisord.service"
			if [ -f "$old_service_file" ]; then
				rm -f "$old_service_file"
			fi
			systemctl daemon-reload >/dev/null 2>&1
		)
	elif command_exists service; then
		supervisor_startup_file='/etc/init.d/supervisord'

		if [ -z "$lsb_dist" ]; then
			get_os_info
		fi

		case "$lsb_dist" in
			ubuntu|debian|raspbian)
				supervisor_startup_file_url="$SUPERVISOR_SERVICE_FILE_DEBIAN_URL"
				;;
			fedora|centos|redhat|oraclelinux|photon)
				supervisor_startup_file_url="$SUPERVISOR_SERVICE_FILE_REDHAT_URL"
				;;
			*)
				echo "û���ʺϵ�ǰϵͳ�ķ��������ű��ļ���"
				exit 1
				;;
		esac

		download_file "$supervisor_startup_file_url" "$supervisor_startup_file"
		(
			set -x
			chmod a+x "$supervisor_startup_file"
		)
	else
		cat >&2 <<-'EOF'
		��ǰ������δ��װ systemctl ���� service ����޷����÷���
		�����ֶ���װ systemd ���� service ֮�������нű���
		EOF

		exit 1
	fi
}

start_supervisor() {
	( set -x; sleep 3 )
	if command_exists systemctl; then
		if systemctl status supervisord.service >/dev/null 2>&1; then
			systemctl restart supervisord.service
		else
			systemctl start supervisord.service
		fi
	elif command_exists service; then
		if service supervisord status >/dev/null 2>&1; then
			service supervisord restart
		else
			service supervisord start
		fi
	fi

	if [ "$?" != "0" ]; then
		cat >&2 <<-'EOF'
		���� Supervisor ʧ��, Kcptun �޷���������!
		�뷴�����ű����ߡ�
		EOF
		exit 1
	fi
}

enable_supervisor() {
	if command_exists systemctl; then
		(
			set -x
			systemctl enable "supervisord.service"
		)
	elif command_exists service; then
		if [ -z "$lsb_dist" ]; then
			get_os_info
		fi

		case "$lsb_dist" in
			ubuntu|debian|raspbian)
				(
					set -x
					update-rc.d -f supervisord defaults
				)
				;;
			fedora|centos|redhat|oraclelinux|photon)
				(
					set -x
					chkconfig --add supervisord
					chkconfig supervisord on
				)
				;;
			esac
	fi
}

set_kcptun_config() {
	is_port() {
		local port="$1"
		is_number "$port" && \
			[ $port -ge 1 ] && [ $port -le 65535 ]
	}

	port_using() {
		local port="$1"

		if command_exists netstat; then
			( netstat -ntul | grep -qE "[0-9:*]:${port}\s" )
		elif command_exists ss; then
			( ss -ntul | grep -qE "[0-9:*]:${port}\s" )
		else
			return 0
		fi

		return $?
	}

	local input=""
	local yn=""

	# ���÷������ж˿�
	[ -z "$listen_port" ] && listen_port="$D_LISTEN_PORT"
	while true
	do
		cat >&1 <<-'EOF'
		������ Kcptun ��������ж˿� [1~65535]
		����˿ھ��� Kcptun �ͻ������ӵĶ˿�
		EOF
		read -p "(Ĭ��: ${listen_port}): " input
		if [ -n "$input" ]; then
			if is_port "$input"; then
				listen_port="$input"
			else
				echo "��������, ������ 1~65535 ֮�������!"
				continue
			fi
		fi

		if port_using "$listen_port" && \
			[ "$listen_port" != "$current_listen_port" ]; then
			echo "�˿��ѱ�ռ��, ����������!"
			continue
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	�˿� = ${listen_port}
	---------------------------
	EOF

	[ -z "$target_addr" ] && target_addr="$D_TARGET_ADDR"
	cat >&1 <<-'EOF'
	��������Ҫ���ٵĵ�ַ
	���������������ơ�IPv4 ��ַ���� IPv6 ��ַ
	EOF
	read -p "(Ĭ��: ${target_addr}): " input
	if [ -n "$input" ]; then
		target_addr="$input"
	fi

	input=""
	cat >&1 <<-EOF
	---------------------------
	���ٵ�ַ = ${target_addr}
	---------------------------
	EOF

	[ -z "$target_port" ] && target_port="$D_TARGET_PORT"
	while true
	do
		cat >&1 <<-'EOF'
		��������Ҫ���ٵĶ˿� [1~65535]
		EOF
		read -p "(Ĭ��: ${target_port}): " input
		if [ -n "$input" ]; then
			if is_port "$input"; then
				if [ "$input" = "$listen_port" ]; then
					echo "���ٶ˿ڲ��ܺ� Kcptun �˿�һ��!"
					continue
				fi

				target_port="$input"
			else
				echo "��������, ������ 1~65535 ֮�������!"
				continue
			fi
		fi

		if [ "$target_addr" = "127.0.0.1" ] && ! port_using "$target_port"; then
			read -p "��ǰû�����ʹ�ô˶˿�, ȷ�����ٴ˶˿�? [y/n]: " yn
			if [ -n "$yn" ]; then
				case "$(first_character "$yn")" in
					y|Y)
						;;
					*)
						continue
						;;
				esac
			fi
		fi

		break
	done

	input=""
	yn=""
	cat >&1 <<-EOF
	---------------------------
	���ٶ˿� = ${target_port}
	---------------------------
	EOF

	[ -z "$key" ] && key="$D_KEY"
	cat >&1 <<-'EOF'
	������ Kcptun ����(key)
	�ò�����������һ��
	EOF
	read -p "(Ĭ������: ${key}): " input
	[ -n "$input" ] && key="$input"

	input=""
	cat >&1 <<-EOF
	---------------------------
	���� = ${key}
	---------------------------
	EOF

	[ -z "$crypt" ] && crypt="$D_CRYPT"
	local crypt_list="aes aes-128 aes-192 salsa20 blowfish twofish cast5 3des tea xtea xor none"
	local i=0
	cat >&1 <<-'EOF'
	��ѡ����ܷ�ʽ(crypt)
	ǿ���ܶ� CPU Ҫ��ϸߣ�
	�������·���������ÿͻ��ˣ�
	�뾡��ѡ�������ܻ��߲����ܡ�
	�ò�����������һ��
	EOF
	while true
	do

		for c in $crypt_list; do
			i=$(expr $i + 1)
			echo "(${i}) ${c}"
		done

		read -p "(Ĭ��: ${crypt}) ��ѡ�� [1~$i]: " input
		if [ -n "$input" ]; then
			if is_number "$input" && [ $input -ge 1 ] && [ $input -le $i ]; then
				crypt=$(echo "$crypt_list" | cut -d' ' -f ${input})
			else
				echo "��������Ч���� 1~$i!"
				i=0
				continue
			fi
		fi
		break
	done

	input=""
	i=0
	cat >&1 <<-EOF
	-----------------------------
	���ܷ�ʽ = ${crypt}
	-----------------------------
	EOF

	[ -z "$mode" ] && mode="$D_MODE"
	local mode_list="normal fast fast2 fast3 manual"
	i=0
	cat >&1 <<-'EOF'
	��ѡ�����ģʽ(mode)
	����ģʽ�ͷ��ʹ��ڴ�С��ͬ��������������Ĵ�С
	�������ģʽѡ���ֶ�(manual)����
	�������ֶ������ز��������á�
	EOF
	while true
	do

		for m in $mode_list; do
			i=$(expr $i + 1)
			echo "(${i}) ${m}"
		done

		read -p "(Ĭ��: ${mode}) ��ѡ�� [1~$i]: " input
		if [ -n "$input" ]; then
			if is_number "$input" && [ $input -ge 1 ] && [ $input -le $i ]; then
				mode=$(echo "$mode_list" | cut -d ' ' -f ${input})
			else
				echo "��������Ч���� 1~$i!"
				i=0
				continue
			fi
		fi
		break
	done

	input=""
	i=0
	cat >&1 <<-EOF
	---------------------------
	����ģʽ = ${mode}
	---------------------------
	EOF

	if [ "$mode" = "manual" ]; then
		set_manual_parameters
	else
		nodelay=""
		interval=""
		resend=""
		nc=""
	fi

	[ -z "$mtu" ] && mtu="$D_MTU"
	while true
	do
		cat >&1 <<-'EOF'
		������ UDP ���ݰ��� MTU (����䵥Ԫ)ֵ
		EOF
		read -p "(Ĭ��: ${mtu}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "��������, ���������0������!"
				continue
			fi

			mtu=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	MTU = ${mtu}
	---------------------------
	EOF

	[ -z "$sndwnd" ] && sndwnd="$D_SNDWND"
	while true
	do
		cat >&1 <<-'EOF'
		�����÷��ʹ��ڴ�С(sndwnd)
		���ʹ��ڹ�����˷ѹ�������
		EOF
		read -p "(���ݰ�����, Ĭ��: ${sndwnd}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "��������, ���������0������!"
				continue
			fi

			sndwnd=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	sndwnd = ${sndwnd}
	---------------------------
	EOF

	[ -z "$rcvwnd" ] && rcvwnd="$D_RCVWND"
	while true
	do
		cat >&1 <<-'EOF'
		�����ý��մ��ڴ�С(rcvwnd)
		EOF
		read -p "(���ݰ�����, Ĭ��: ${rcvwnd}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "��������, ���������0������!"
				continue
			fi

			rcvwnd=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	rcvwnd = ${rcvwnd}
	---------------------------
	EOF

	[ -z "$datashard" ] && datashard="$D_DATASHARD"
	while true
	do
		cat >&1 <<-'EOF'
		������ǰ����� datashard
		�ò�����������һ��
		EOF
		read -p "(Ĭ��: ${datashard}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -lt 0 ]; then
				echo "��������, ��������ڵ���0������!"
				continue
			fi

			datashard=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	datashard = ${datashard}
	---------------------------
	EOF

	[ -z "$parityshard" ] && parityshard="$D_PARITYSHARD"
	while true
	do
		cat >&1 <<-'EOF'
		������ǰ����� parityshard
		�ò�����������һ��
		EOF
		read -p "(Ĭ��: ${parityshard}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -lt 0 ]; then
				echo "��������, ��������ڵ���0������!"
				continue
			fi

			parityshard=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	parityshard = ${parityshard}
	---------------------------
	EOF

	[ -z "$dscp" ] && dscp="$D_DSCP"
	while true
	do
		cat >&1 <<-'EOF'
		�����ò�ַ�������(DSCP)
		EOF
		read -p "(Ĭ��: ${dscp}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -lt 0 ]; then
				echo "��������, ��������ڵ���0������!"
				continue
			fi

			dscp=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	DSCP = ${dscp}
	---------------------------
	EOF

	[ -z "$nocomp" ] && nocomp="$D_NOCOMP"
	while true
	do
		cat >&1 <<-'EOF'
		�Ƿ�ر�����ѹ��?
		EOF
		read -p "(Ĭ��: ${nocomp}) [y/n]: " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					nocomp='true'
					;;
				n|N)
					nocomp='false'
					;;
				*)
					echo "������������������!"
					continue
					;;
			esac
		fi
		break
	done

	yn=""
	cat >&1 <<-EOF
	---------------------------
	nocomp = ${nocomp}
	---------------------------
	EOF

	[ -z "$quiet" ] && quiet="$D_QUIET"
	while true
	do
		cat >&1 <<-'EOF'
		�Ƿ����� open/close ��־���?
		EOF
		read -p "(Ĭ��: ${quiet}) [y/n]: " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					quiet='true'
					;;
				n|N)
					quiet='false'
					;;
				*)
					echo "������������������!"
					continue
					;;
			esac
		fi
		break
	done

	yn=""
	cat >&1 <<-EOF
	---------------------------
	quiet = ${quiet}
	---------------------------
	EOF

	[ -z "$tcp" ] && tcp="$D_TCP"
	while true
	do
		cat >&1 <<-'EOF'
		�Ƿ�ʹ�� TCP ����
		EOF
		read -p "(Ĭ��: ${tcp}) [y/n]: " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					tcp='true'
					;;
				n|N)
					tcp='false'
					;;
				*)
					echo "������������������!"
					continue
					;;
			esac
		fi
		break
	done

	if [ "$tcp" = "true" ]; then
		run_user="root"
	fi

	yn=""
	cat >&1 <<-EOF
	---------------------------
	tcp = ${tcp}
	---------------------------
	EOF

	unset_snmp() {
		snmplog=""
		snmpperiod=""
		cat >&1 <<-EOF
		---------------------------
		����¼ SNMP ��־
		---------------------------
		EOF
	}

	cat >&1 <<-EOF
	�Ƿ��¼ SNMP ��־?
	EOF
	read -p "(Ĭ��: ��) [y/n]: " yn
	if [ -n "$yn" ]; then
		case "$(first_character "$yn")" in
			y|Y)
				set_snmp
				;;
			n|N|*)
				unset_snmp
				;;
		esac
		yn=""
	else
		unset_snmp
	fi

	[ -z "$pprof" ] && pprof="$D_PPROF"
	while true
	do
		cat >&1 <<-'EOF'
		�Ƿ��� pprof ���ܼ��?
		��ַ: http://IP:6060/debug/pprof/
		EOF
		read -p "(Ĭ��: ${pprof}) [y/n]: " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					pprof='true'
					;;
				n|N)
					pprof='false'
					;;
				*)
					echo "������������������!"
					continue
					;;
			esac
		fi
		break
	done

	yn=""
	cat >&1 <<-EOF
	---------------------------
	pprof = ${pprof}
	---------------------------
	EOF

	unset_hidden_parameters() {
		acknodelay=""
		sockbuf=""
		smuxbuf=""
		keepalive=""
		cat >&1 <<-EOF
		---------------------------
		���������ز���
		---------------------------
		EOF
	}

	cat >&1 <<-'EOF'
	��������������ɣ��Ƿ����ö�������ز���?
	ͨ������±���Ĭ�ϼ��ɣ����ö�������
	EOF
	read -p "(Ĭ��: ��) [y/n]: " yn
	if [ -n "$yn" ]; then
		case "$(first_character "$yn")" in
			y|Y)
				set_hidden_parameters
				;;
			n|N|*)
				unset_hidden_parameters
				;;
		esac
	else
		unset_hidden_parameters
	fi

	if [ $listen_port -le 1024 ]; then
		run_user="root"
	fi

	echo "������ɡ�"
	any_key_to_continue
}

set_snmp() {
	snmplog="$(get_current_file 'snmp')"

	local input=""
	[ -z "$snmpperiod" ] && snmpperiod="$D_SNMPPERIOD"
	while true
	do
		cat >&1 <<-'EOF'
		������ SNMP ��¼���ʱ�� snmpperiod
		EOF
		read -p "(Ĭ��: ${snmpperiod}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -lt 0 ]; then
				echo "��������, ��������ڵ���0������!"
				continue
			fi

			snmpperiod=$input
		fi
		break
	done

	cat >&1 <<-EOF
	---------------------------
	snmplog = ${snmplog}
	snmpperiod = ${snmpperiod}
	---------------------------
	EOF
}

set_manual_parameters() {
	echo "��ʼ�����ֶ�����..."
	local input=""
	local yn=""

	[ -z "$nodelay" ] && nodelay="$D_NODELAY"
	while true
	do
		cat >&1 <<-'EOF'
		�Ƿ����� nodelay ģʽ?
		(0) ������
		(1) ����
		EOF
		read -p "(Ĭ��: ${nodelay}) [0/1]: " input
		if [ -n "$input" ]; then
			case "$(first_character "$input")" in
				1)
					nodelay=1
					;;
				0|*)
					nodelay=0
					;;
				*)
					echo "������������������!"
					continue
					;;
			esac
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	nodelay = ${nodelay}
	---------------------------
	EOF

	[ -z "$interval" ] && interval="$D_INTERVAL"
	while true
	do
		cat >&1 <<-'EOF'
		������Э���ڲ������� interval
		EOF
		read -p "(��λ: ms, Ĭ��: ${interval}): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "��������, ���������0������!"
				continue
			fi

			interval=$input
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	interval = ${interval}
	---------------------------
	EOF

	[ -z "$resend" ] && resend="$D_RESEND"
	while true
	do
		cat >&1 <<-'EOF'
		�Ƿ����ÿ����ش�ģʽ(resend)?
		(0) ������
		(1) ����
		(2) 2��ACK��Խ����ֱ���ش�
		EOF
		read -p "(Ĭ��: ${resend}) ��ѡ�� [0~2]: " input
		if [ -n "$input" ]; then
			case "$(first_character "$input")" in
				0)
					resend=0
					;;
				1)
					resend=1
					;;
				2)
					resend=2
					;;
				*)
					echo "������������������!"
					continue
					;;
			esac
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	resend = ${resend}
	---------------------------
	EOF

	[ -z "$nc" ] && nc="$D_NC"
	while true
	do
		cat >&1 <<-'EOF'
		�Ƿ�ر�����(nc)?
		(0) �ر�
		(1) ����
		EOF
		read -p "(Ĭ��: ${nc}) [0/1]: " input
		if [ -n "$input" ]; then
			case "$(first_character "$input")" in
				0)
					nc=0
					;;
				1)
					nc=1
					;;
				*)
					echo "������������������!"
					continue
					;;
			esac
		fi
		break
	done
	cat >&1 <<-EOF
	---------------------------
	nc = ${nc}
	---------------------------
	EOF
}

set_hidden_parameters() {
	echo "��ʼ�������ز���..."
	local input=""
	local yn=""

	[ -z "$acknodelay" ] && acknodelay="$D_ACKNODELAY"
	while true
	do
		cat >&1 <<-'EOF'
		�Ƿ����� acknodelay ģʽ?
		EOF
		read -p "(Ĭ��: ${acknodelay}) [y/n]: " yn
		if [ -n "$yn" ]; then
			case "$(first_character "$yn")" in
				y|Y)
					acknodelay="true"
					;;
				n|N)
					acknodelay="false"
					;;
				*)
					echo "������������������!"
					continue
					;;
			esac
		fi
		break
	done

	yn=""
	cat >&1 <<-EOF
	---------------------------
	acknodelay = ${acknodelay}
	---------------------------
	EOF

	[ -z "$sockbuf" ] && sockbuf="$D_SOCKBUF"
	while true
	do
		cat >&1 <<-'EOF'
		������ UDP �շ���������С(sockbuf)
		EOF
		read -p "(��λ: MB, Ĭ��: $(expr ${sockbuf} / 1024 / 1024)): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "��������, ���������0������!"
				continue
			fi

			sockbuf=$(expr $input * 1024 * 1024)
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	sockbuf = ${sockbuf}
	---------------------------
	EOF

	[ -z "$smuxbuf" ] && smuxbuf="$D_SMUXBUF"
	while true
	do
		cat >&1 <<-'EOF'
		������ de-mux ��������С(smuxbuf)
		EOF
		read -p "(��λ: MB, Ĭ��: $(expr ${smuxbuf} / 1024 / 1024)): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "��������, ���������0������!"
				continue
			fi

			smuxbuf=$(expr $input * 1024 * 1024)
		fi
		break
	done

	input=""
	cat >&1 <<-EOF
	---------------------------
	smuxbuf = ${smuxbuf}
	---------------------------
	EOF

	[ -z "$keepalive" ] && keepalive="$D_KEEPALIVE"
	while true
	do
		cat >&1 <<-'EOF'
		������ Keepalive �ļ��ʱ��
		EOF
		read -p "(��λ: s, Ĭ��ֵ: ${keepalive}, ǰֵ: 5): " input
		if [ -n "$input" ]; then
			if ! is_number "$input" || [ $input -le 0 ]; then
				echo "��������, ���������0������!"
				continue
			fi

			keepalive=$input
		fi
		break
	done

	cat >&1 <<-EOF
	---------------------------
	keepalive = ${keepalive}
	---------------------------
	EOF
}

# ���� Kcptun ����������ļ�
gen_kcptun_config() {
	mk_file_dir() {
		local dir=""
		dir="$(dirname "$1")"
		local mod=$2

		if [ ! -d "$dir" ]; then
			(
				set -x
				mkdir -p "$dir"
			)
		fi

		if [ -n "$mod" ]; then
			chmod $mod "$dir"
		fi
	}

	local config_file=""
	config_file="$(get_current_file 'config')"
	local supervisor_config_file=""
	supervisor_config_file="$(get_current_file 'supervisor')"

	mk_file_dir "$config_file"
	mk_file_dir "$supervisor_config_file"

	if [ -n "$snmplog" ]; then
		mk_file_dir "$snmplog" '777'
	fi

	if ( echo "$listen_addr" | grep -q ":" ); then
		listen_addr="[${listen_addr}]"
	fi

	if ( echo "$target_addr" | grep -q ":" ); then
		target_addr="[${target_addr}]"
	fi

	cat > "$config_file"<<-EOF
	{
	  "listen": "${listen_addr}:${listen_port}",
	  "target": "${target_addr}:${target_port}",
	  "key": "${key}",
	  "crypt": "${crypt}",
	  "mode": "${mode}",
	  "mtu": ${mtu},
	  "sndwnd": ${sndwnd},
	  "rcvwnd": ${rcvwnd},
	  "datashard": ${datashard},
	  "parityshard": ${parityshard},
	  "dscp": ${dscp},
	  "nocomp": ${nocomp},
	  "quiet": ${quiet},
	  "tcp": ${tcp}
	}
	EOF

	write_configs_to_file() {
		install_jq
		local k; local v

		local json=""
		json="$(cat "$config_file")"
		for k in "$@"; do
			v="$(eval echo "\$$k")"

			if [ -n "$v" ]; then
				if is_number "$v" || [ "$v" = "false" ] || [ "$v" = "true" ]; then
					json="$(echo "$json" | $JQ_BIN ".$k=$v")"
				else
					json="$(echo "$json" | $JQ_BIN ".$k=\"$v\"")"
				fi
			fi
		done

		if [ -n "$json" ] && [ "$json" != "$(cat "$config_file")" ]; then
			echo "$json" >"$config_file"
		fi
	}

	write_configs_to_file "snmplog" "snmpperiod" "pprof" "acknodelay" "nodelay" \
		"interval" "resend" "nc" "sockbuf" "smuxbuf" "keepalive"

	if ! grep -q "^${run_user}:" '/etc/passwd'; then
		(
			set -x
			useradd -U -s '/usr/sbin/nologin' -d '/nonexistent' "$run_user" 2>/dev/null
		)
	fi

	cat > "$supervisor_config_file"<<-EOF
	[program:kcptun${current_instance_id}]
	user=${run_user}
	directory=${KCPTUN_INSTALL_DIR}
	command=$(get_kcptun_server_file) -c "${config_file}"
	process_name=%(program_name)s
	autostart=true
	redirect_stderr=true
	stdout_logfile=$(get_current_file 'log')
	stdout_logfile_maxbytes=1MB
	stdout_logfile_backups=0
	EOF
}

# ���÷���ǽ���Ŷ˿�
set_firewall() {
	if command_exists firewall-cmd; then
		if ! ( firewall-cmd --state >/dev/null 2>&1 ); then
			systemctl start firewalld >/dev/null 2>&1
		fi
		if [ "$?" = "0" ]; then
			if [ -n "$current_listen_port" ]; then
				firewall-cmd --zone=public --remove-port=${current_listen_port}/udp >/dev/null 2>&1
			fi

			if ! firewall-cmd --quiet --zone=public --query-port=${listen_port}/udp; then
				firewall-cmd --quiet --permanent --zone=public --add-port=${listen_port}/udp
				firewall-cmd --reload
			fi
		else
			cat >&1 <<-EOF
			����: �Զ���� firewalld ����ʧ��
			����б�Ҫ, ���ֶ���Ӷ˿� ${listen_port} �ķ���ǽ����:
			    firewall-cmd --permanent --zone=public --add-port=${listen_port}/udp
			    firewall-cmd --reload
			EOF
		fi
	elif command_exists iptables; then
		if ! ( service iptables status >/dev/null 2>&1 ); then
			service iptables start >/dev/null 2>&1
		fi

		if [ "$?" = "0" ]; then
			if [ -n "$current_listen_port" ]; then
				iptables -D INPUT -p udp --dport ${current_listen_port} -j ACCEPT >/dev/null 2>&1
			fi

			if ! iptables -C INPUT -p udp --dport ${listen_port} -j ACCEPT >/dev/null 2>&1; then
				iptables -I INPUT -p udp --dport ${listen_port} -j ACCEPT >/dev/null 2>&1
				service iptables save
				service iptables restart
			fi
		else
			cat >&1 <<-EOF
			����: �Զ���� iptables ����ʧ��
			���б�Ҫ, ���ֶ���Ӷ˿� ${listen_port} �ķ���ǽ����:
			    iptables -I INPUT -p udp --dport ${listen_port} -j ACCEPT
			    service iptables save
			    service iptables restart
			EOF
		fi
	fi
}

# ѡ��һ��ʵ��
select_instance() {
	if [ "$(get_instance_count)" -gt 1 ]; then
		cat >&1 <<-'EOF'
		��ǰ�ж�� Kcptun ʵ�� (������޸�ʱ������):
		EOF

		local files=""
		files=$(ls -lt '/etc/supervisor/conf.d/' | grep "^-" | awk '{print $9}' | grep "^kcptun[0-9]*\.conf$")
		local i=0
		local array=""
		local id=""
		for file in $files; do
			id="$(echo "$file" | grep -oE "[0-9]+")"
			array="${array}${id}#"

			i=$(expr $i + 1)
			echo "(${i}) ${file%.*}"
		done

		local sel=""
		while true
		do
			read -p "��ѡ�� [1~${i}]: " sel
			if [ -n "$sel" ]; then
				if ! is_number "$sel" || [ $sel -lt 1 ] || [ $sel -gt $i ]; then
					cat >&2 <<-EOF
					��������Ч���� 1~${i}!
					EOF
					continue
				fi
			else
				cat >&2 <<-EOF
				�����벻��Ϊ�գ�
				EOF
				continue
			fi

			current_instance_id=$(echo "$array" | cut -d '#' -f ${sel})
			break
		done
	fi
}

# ͨ����ǰ����˻�����ȡ Kcptun ������ļ���
get_kcptun_server_file() {
	if [ -z "$file_suffix" ]; then
		get_arch
	fi

	echo "${KCPTUN_INSTALL_DIR}/server_$file_suffix"
}

# ������ʵ���� ID
get_new_instance_id() {
	if [ -f "/etc/supervisor/conf.d/kcptun.conf" ]; then
		local i=2
		while [ -f "/etc/supervisor/conf.d/kcptun${i}.conf" ]
		do
			i=$(expr $i + 1)
		done
		echo "$i"
	fi
}

# ��ȡ�Ѱ�װ�� Kcptun �汾
get_installed_version() {
	local server_file=""
	server_file="$(get_kcptun_server_file)"

	if [ -f "$server_file" ]; then
		if [ ! -x "$server_file" ]; then
			chmod a+x "$server_file"
		fi

		echo "$(${server_file} -v 2>/dev/null | awk '{print $3}')"
	fi
}

# ���ص�ǰѡ��ʵ���������ļ�
load_instance_config() {
	local config_file=""
	config_file="$(get_current_file 'config')"

	if [ ! -s "$config_file" ]; then
		cat >&2 <<-'EOF'
		ʵ�������ļ������ڻ�Ϊ��, ����!
		EOF
		exit 1
	fi

	local config_content=""
	config_content="$(cat ${config_file})"

	if [ -z "$(get_json_string "$config_content" '.listen')" ]; then
		cat >&2 <<-EOF
		ʵ�������ļ����ڴ���, ����!
		�����ļ�·��: ${config_file}
		EOF
		exit 1
	fi

	local lines=""
	lines="$(get_json_string "$config_content" 'to_entries | map("\(.key)=\(.value | @sh)") | .[]')"

	OLDIFS=$IFS
	IFS=$(printf '\n')
	for line in $lines; do
		eval "$line"
	done
	IFS=$OLDIFS

	if [ -n "$listen" ]; then
		listen_port="$(echo "$listen" | rev | cut -d ':' -f1 | rev)"
		listen_addr="$(echo "$listen" | sed "s/:${listen_port}$//" | grep -oE '[0-9a-fA-F\.:]*')"
		listen=""
	fi
	if [ -n "$target" ]; then
		target_port="$(echo "$target" | rev | cut -d ':' -f1 | rev)"
		target_addr="$(echo "$target" | sed "s/:${target_port}$//" | grep -oE '[0-9a-fA-F\.:]*')"
		target=""
	fi

	if [ -n "$listen_port" ]; then
		current_listen_port="$listen_port"
	fi
}

# ��ʾ����� Kcptun �汾���Ϳͻ����ļ������ص�ַ
show_version_and_client_url() {
	local version=""
	version="$(get_installed_version)"
	if [ -n "$version" ]; then
		cat >&1 <<-EOF

		��ǰ��װ�� Kcptun �汾Ϊ: ${version}
		EOF
	fi

	if [ -n "$kcptun_release_html_url" ]; then
		cat >&1 <<-EOF
		������ǰ��:
		  ${kcptun_release_html_url}
		�ֶ����ؿͻ����ļ�
		EOF
	fi
}

# ��ʾ��ǰѡ��ʵ������Ϣ
show_current_instance_info() {
	local server_ip=""
	server_ip="$(get_server_ip)"

	printf '������IP: \033[41;37m %s \033[0m\n' "$server_ip"
	printf '�˿�: \033[41;37m %s \033[0m\n' "$listen_port"
	printf '���ٵ�ַ: \033[41;37m %s:%s \033[0m\n' "$target_addr" "$target_port"

	show_configs() {
		local k; local v
		for k in "$@"; do
			v="$(eval echo "\$$k")"
			if [ -n "$v" ]; then
				printf '%s: \033[41;37m %s \033[0m\n' "$k" "$v"
			fi
		done
	}

	show_configs "key" "crypt" "mode" "mtu" "sndwnd" "rcvwnd" "datashard" \
		"parityshard" "dscp" "nocomp" "quiet" "tcp" "nodelay" "interval" "resend" \
		"nc" "acknodelay" "sockbuf" "smuxbuf" "keepalive"

	show_version_and_client_url

	install_jq
	local client_config=""

	# ����������ǿͻ�����ʹ�õ�������Ϣ
	# �ͻ��˵� *remoteaddr* �˿ں�Ϊ����˵� *listen_port*
	# �ͻ��˵� *localaddr* �˿ںű�����Ϊ�˷���˵ļ��ٶ˿�
	client_config="$(cat <<-EOF
	{
	  "localaddr": ":${target_port}",
	  "remoteaddr": "${server_ip}:${listen_port}",
	  "key": "${key}"
	}
	EOF
	)"

	gen_client_configs() {
		local k; local v
		for k in "$@"; do
			if [ "$k" = "sndwnd" ]; then
				v="$rcvwnd"
			elif [ "$k" = "rcvwnd" ]; then
				v="$sndwnd"
			else
				v="$(eval echo "\$$k")"
			fi

			if [ -n "$v" ]; then
				if is_number "$v" || [ "$v" = "true" ] || [ "$v" = "false" ]; then
					client_config="$(echo "$client_config" | $JQ_BIN -r ".${k}=${v}")"
				else
					client_config="$(echo "$client_config" | $JQ_BIN -r ".${k}=\"${v}\"")"
				fi
			fi
		done
	}

	gen_client_configs "crypt" "mode" "mtu" "sndwnd" "rcvwnd" "datashard" \
		"parityshard" "dscp" "nocomp" "quiet" "tcp" "nodelay" "interval" "resend" \
		"nc" "acknodelay" "sockbuf" "smuxbuf" "keepalive"

	cat >&1 <<-EOF

	��ʹ�õĿͻ��������ļ�Ϊ:
	${client_config}
	EOF

	local mobile_config="key=${key}"
	gen_mobile_configs() {
		local k; local v
		for k in "$@"; do
			if [ "$k" = "sndwnd" ]; then
				v="$rcvwnd"
			elif [ "$k" = "rcvwnd" ]; then
				v="$sndwnd"
			else
				v="$(eval echo "\$$k")"
			fi

			if [ -n "$v" ]; then
				if [ "$v" = "false" ]; then
					continue
				elif [ "$v" = "true" ]; then
					mobile_config="${mobile_config};${k}"
				else
					mobile_config="${mobile_config};${k}=${v}"
				fi
			fi
		done
	}

	gen_mobile_configs "crypt" "mode" "mtu" "sndwnd" "rcvwnd" "datashard" \
		"parityshard" "dscp" "nocomp" "quiet" "tcp" "nodelay" "interval" "resend" \
		"nc" "acknodelay" "sockbuf" "smuxbuf" "keepalive"

	cat >&1 <<-EOF

	�ֻ��˲�������ʹ��:
	  ${mobile_config}

	EOF
}

do_install() {
	check_root
	disable_selinux
	installed_check
	set_kcptun_config
	install_deps
	install_kcptun
	install_supervisor
	gen_kcptun_config
	set_firewall
	start_supervisor
	enable_supervisor

	cat >&1 <<-EOF

	��ϲ! Kcptun ����˰�װ�ɹ���
	EOF

	show_current_instance_info

	cat >&1 <<-EOF
	Kcptun ��װĿ¼: ${KCPTUN_INSTALL_DIR}

	�ѽ� Supervisor ���뿪������,
	Kcptun ����˻��� Supervisor ������������

	����ʹ��˵��: ${0} help

	�������ű��ﵽ���㣬����������ߺ�ƿ����:
	  https://blog.kuoruan.com/donate

	���ܼ��ٵĿ�аɣ�
	EOF
}

# ж�ز���
do_uninstall() {
	check_root
	cat >&1 <<-'EOF'
	��ѡ����ж�� Kcptun �����
	EOF
	any_key_to_continue
	echo "����ж�� Kcptun ����˲�ֹͣ Supervisor..."

	if command_exists supervisorctl; then
		supervisorctl shutdown
	fi

	if command_exists systemctl; then
		systemctl stop supervisord.service
	elif command_exists serice; then
		service supervisord stop
	fi

	(
		set -x
		rm -f "/etc/supervisor/conf.d/kcptun*.conf"
		rm -rf "$KCPTUN_INSTALL_DIR"
		rm -rf "$KCPTUN_LOG_DIR"
	)

	cat >&1 <<-'EOF'
	�Ƿ�ͬʱж�� Supervisor ?
	ע��: Supervisor �������ļ���ͬʱ��ɾ��
	EOF

	read -p "(Ĭ��: ��ж��) ��ѡ�� [y/n]: " yn
	if [ -n "$yn" ]; then
		case "$(first_character "$yn")" in
			y|Y)
				if command_exists systemctl; then
					systemctl disable supervisord.service
					rm -f "/lib/systemd/system/supervisord.service" \
						"/etc/systemd/system/supervisord.service"
				elif command_exists service; then
					if [ -z "$lsb_dist" ]; then
						get_os_info
					fi
					case "$lsb_dist" in
						ubuntu|debian|raspbian)
							(
								set -x
								update-rc.d -f supervisord remove
							)
							;;
						fedora|centos|redhat|oraclelinux|photon)
							(
								set -x
								chkconfig supervisord off
								chkconfig --del supervisord
							)
							;;
					esac
					rm -f '/etc/init.d/supervisord'
				fi

				(
					set -x
					# �°�ʹ�� pip ж��
					if command_exists pip; then
						pip uninstall -y supervisor 2>/dev/null || true
					fi

					# �ɰ�ʹ�� easy_install ж��
					if command_exists easy_install; then
						rm -rf "$(easy_install -mxN supervisor | grep 'Using.*supervisor.*\.egg' | awk '{print $2}')"
					fi

					rm -rf '/etc/supervisor/'
					rm -f '/usr/local/bin/supervisord' \
						'/usr/local/bin/supervisorctl' \
						'/usr/local/bin/pidproxy' \
						'/usr/local/bin/echo_supervisord_conf' \
						'/usr/bin/supervisord' \
						'/usr/bin/supervisorctl' \
						'/usr/bin/pidproxy' \
						'/usr/bin/echo_supervisord_conf'
				)
				;;
			n|N|*)
				start_supervisor
				;;
		esac
	fi

	cat >&1 <<-EOF
	ж�����, ��ӭ�ٴ�ʹ�á�
	ע��: �ű�û���Զ�ж�� python-pip �� python-setuptools���ɰ�ű�ʹ�ã�
	������Ҫ, ���������ж�ء�
	EOF
}

# ����
do_update() {
	pre_ckeck

	cat >&1 <<-EOF
	��ѡ���˼�����, ���ڿ�ʼ����...
	EOF

	if get_shell_version_info; then
		local shell_path=$0

		if [ $new_shell_version -gt $SHELL_VERSION ]; then
			cat >&1 <<-EOF
			����һ����װ�ű�����, �汾��: ${new_shell_version}
			����˵��:
			$(printf '%s\n' "$shell_change_log")
			EOF
			any_key_to_continue

			mv -f "$shell_path" "$shell_path".bak

			download_file "$new_shell_url" "$shell_path"
			chmod a+x "$shell_path"

			sed -i -r "s/^CONFIG_VERSION=[0-9]+/CONFIG_VERSION=${CONFIG_VERSION}/" "$shell_path"
			sed -i -r "s/^INIT_VERSION=[0-9]+/INIT_VERSION=${INIT_VERSION}/" "$shell_path"
			rm -f "$shell_path".bak

			clear
			cat >&1 <<-EOF
			��װ�ű��Ѹ��µ� v${new_shell_version}, ���������µĽű�...
			EOF

			bash "$shell_path" update
			exit 0
		fi

		if [ $new_config_version -gt $CONFIG_VERSION ]; then
			cat >&1 <<-EOF
			���� Kcptun ���ø���, �汾��: v${new_config_version}
			����˵��:
			$(printf '%s\n' "$config_change_log")
			��Ҫ�������� Kcptun
			EOF
			any_key_to_continue

			instance_reconfig

			sed -i "s/^CONFIG_VERSION=${CONFIG_VERSION}/CONFIG_VERSION=${new_config_version}/" \
				"$shell_path"
		fi

		if [ $new_init_version -gt $INIT_VERSION ]; then
			cat >&1 <<-EOF
			���ַ��������ű��ļ�����, �汾��: v${new_init_version}
			����˵��:
			$(printf '%s\n' "$init_change_log")
			EOF

			any_key_to_continue

			download_startup_file
			set -sed -i "s/^INIT_VERSION=${INIT_VERSION}/INIT_VERSION=${new_init_version}/" \
				"$shell_path"
		fi
	fi

	echo "��ʼ��ȡ Kcptun �汾��Ϣ..."
	get_kcptun_version_info

	local cur_tag_name=""
	cur_tag_name="$(get_installed_version)"

	if [ -n "$cur_tag_name" ] && is_number "$cur_tag_name" && [ ${#cur_tag_name} -eq 8 ]; then
		cur_tag_name=v"$cur_tag_name"
	fi

	if [ -n "$kcptun_release_tag_name" ] && [ "$kcptun_release_tag_name" != "$cur_tag_name" ]; then
		cat >&1 <<-EOF
		���� Kcptun �°汾 ${kcptun_release_tag_name}
		$([ "$kcptun_release_prerelease" = "true" ] && printf "\033[41;37m ע��: �ð汾ΪԤ����, ��������� \033[0m")
		����˵��:
		$(printf '%s\n' "$kcptun_release_body")
		EOF
		any_key_to_continue

		install_kcptun
		start_supervisor

		show_version_and_client_url
	else
		cat >&1 <<-'EOF'
		δ���� Kcptun ����...
		EOF
	fi
}

# ���ʵ��
instance_add() {
	pre_ckeck

	cat >&1 <<-'EOF'
	��ѡ�������ʵ��, ���ڿ�ʼ����...
	EOF
	current_instance_id="$(get_new_instance_id)"

	set_kcptun_config
	gen_kcptun_config
	set_firewall
	start_supervisor

	cat >&1 <<-EOF
	��ϲ, ʵ�� kcptun${current_instance_id} ��ӳɹ�!
	EOF
	show_current_instance_info
}

# ɾ��ʵ��
instance_del() {
	pre_ckeck

	if [ -n "$1" ]; then
		if is_number "$1"; then
			if [ "$1" != "1" ]; then
				current_instance_id="$1"
			fi
		else
			cat >&2 <<-EOF
			��������, ��ʹ�� $0 del <id>
			<id> Ϊʵ��ID, ��ǰ���� $(get_instance_count) ��ʵ��
			EOF

			exit 1
		fi
	fi

	cat >&1 <<-EOF
	��ѡ����ɾ��ʵ�� kcptun${current_instance_id}
	ע��: ʵ��ɾ�����޷��ָ�
	EOF
	any_key_to_continue

	# ��ȡʵ���� supervisor �����ļ�
	supervisor_config_file="$(get_current_file 'supervisor')"
	if [ ! -f "$supervisor_config_file" ]; then
		echo "��ѡ���ʵ�� kcptun${current_instance_id} ������!"
		exit 1
	fi

	current_config_file="$(get_current_file 'config')"
	current_log_file="$(get_current_file 'log')"
	current_snmp_log_file="$(get_current_file 'snmp')"

	(
		set -x
		rm -f "$supervisor_config_file" \
			"$current_config_file" \
			"$current_log_file" \
			"$current_snmp_log_file"
	)

	start_supervisor

	cat >&1 <<-EOF
	ʵ�� kcptun${current_instance_id} ɾ���ɹ�!
	EOF
}

# ��ʾʵ����Ϣ
instance_show() {
	pre_ckeck

	if [ -n "$1" ]; then
		if is_number "$1"; then
			if [ "$1" != "1" ]; then
				current_instance_id="$1"
			fi
		else
			cat >&2 <<-EOF
			��������, ��ʹ�� $0 show <id>
			<id> Ϊʵ��ID, ��ǰ���� $(get_instance_count) ��ʵ��
			EOF

			exit 1
		fi
	fi

	echo "��ѡ���˲鿴ʵ�� kcptun${current_instance_id} ������, ���ڶ�ȡ..."

	load_instance_config

	echo "ʵ�� kcptun${current_instance_id} ��������Ϣ����:"
	show_current_instance_info
}

# ��ʾʵ����־
instance_log() {
	pre_ckeck

	if [ -n "$1" ]; then
		if is_number "$1"; then
			if [ "$1" != "1" ]; then
				current_instance_id="$1"
			fi
		else
			cat >&2 <<-EOF

			��������, ��ʹ�� $0 log <id>
			<id> Ϊʵ��ID, ��ǰ���� $(get_instance_count) ��ʵ��
			EOF

			exit 1
		fi
	fi

	echo "��ѡ���˲鿴ʵ�� kcptun${current_instance_id} ����־, ���ڶ�ȡ..."

	local log_file=""
	log_file="$(get_current_file 'log')"

	if [ -f "$log_file" ]; then
		cat >&1 <<-EOF
		ʵ�� kcptun${current_instance_id} ����־��Ϣ����:
		ע: ��־ʵʱˢ��, �� Ctrl+C �˳���־�鿴
		EOF
		tail -n 20 -f "$log_file"
	else
		cat >&2 <<-EOF
		δ�ҵ�ʵ�� kcptun${current_instance_id} ����־�ļ�...
		EOF
		exit 1
	fi
}

# ��������ʵ��
instance_reconfig() {
	pre_ckeck

	if [ -n "$1" ]; then
		if is_number "$1"; then
			if [ "$1" != "1" ]; then
				current_instance_id="$1"
			fi
		else
			cat >&2 <<-EOF
			��������, ��ʹ�� $0 reconfig <id>
			<id> Ϊʵ��ID, ��ǰ���� $(get_instance_count) ��ʵ��
			EOF

			exit 1
		fi
	fi

	cat >&1 <<-EOF
	��ѡ������������ʵ�� kcptun${current_instance_id}, ���ڿ�ʼ����...
	EOF

	if [ ! -f "$(get_current_file 'supervisor')" ]; then
		cat >&2 <<-EOF
		��ѡ���ʵ�� kcptun${current_instance_id} ������!
		EOF
		exit 1
	fi

	local sel=""
	cat >&1 <<-'EOF'
	��ѡ�����:
	(1) ��������ʵ������ѡ��
	(2) ֱ���޸�ʵ�������ļ�
	EOF
	read -p "(Ĭ��: 1) ��ѡ��: " sel
	echo
	[ -z "$sel" ] && sel="1"

	case "$(first_character "$sel")" in
		2)
			echo "���ڴ������ļ�, ���ֶ��޸�..."
			local config_file=""
			config_file="$(get_current_file 'config')"
			edit_config_file() {
				if [ ! -f "$config_file" ]; then
					return 1
				fi

				if command_exists vim; then
					vim "$config_file"
				elif command_exists vi; then
					vi "$config_file"
				elif command_exists gedit; then
					gedit "$config_file"
				else
					echo "δ�ҵ����õı༭��, ���ڽ���ȫ������..."
					return 1
				fi

				load_instance_config
			}

			if ! edit_config_file; then
				set_kcptun_config
			fi
			;;
		1|*)
			load_instance_config
			set_kcptun_config
			;;
	esac

	gen_kcptun_config
	set_firewall

	if command_exists supervisorctl; then
		supervisorctl restart "kcptun${current_instance_id}"

		if [ "$?" != "0" ]; then
			cat >&2 <<-'EOF'
			���� Supervisor ʧ��, Kcptun �޷���������!
			��鿴��־��ȡԭ�򣬻��߷������ű����ߡ�
			EOF
			exit 1
		fi
	else
		start_supervisor
	fi

	cat >&1 <<-EOF

	��ϲ, Kcptun ����������Ѹ���!
	EOF
	show_current_instance_info
}

#�ֶ���װ
manual_install() {
	pre_ckeck

	cat >&1 <<-'EOF'
	��ѡ�����Զ���汾��װ, ���ڿ�ʼ����...
	EOF

	local tag_name="$1"

	while true
	do
		if [ -z "$tag_name" ]; then
			cat >&1 <<-'EOF'
			���������밲װ�� Kcptun �汾������ TAG
			EOF
			read -p "(����: v20160904): " tag_name
			if [ -z "$tag_name" ]; then
				echo "������Ч, ����������!"
				continue
			fi
		fi

		if [ "$tag_name" = "SNMP_Milestone" ]; then
			echo "��֧�ִ˰汾, ����������!"
			tag_name=""
			continue
		fi

		local version_num=""
		version_num=$(echo "$tag_name" | grep -oE "[0-9]+" || "0")
		if [ ${#version_num} -eq 8 ] && [ $version_num -le 20160826 ]; then
			echo "��֧�ְ�װ v20160826 ����ǰ�汾"
			tag_name=""
			continue
		fi

		echo "���ڻ�ȡ��Ϣ�����Ժ�..."
		get_kcptun_version_info "$tag_name"
		if [ "$?" != "0" ]; then
			cat >&2 <<-EOF
			δ�ҵ���Ӧ�汾���ص�ַ (TAG: ${tag_name}), ����������!
			�����ǰ��:
			  ${KCPTUN_TAGS_URL}
			�鿴���п��� TAG
			EOF
			tag_name=""
			continue
		else
			cat >&1 <<-EOF
			���ҵ� Kcptun �汾��Ϣ, TAG: ${tag_name}
			EOF
			any_key_to_continue

			install_kcptun "$tag_name"
			start_supervisor
			show_version_and_client_url
			break
		fi
	done
}

pre_ckeck() {
	check_root

	if ! is_installed; then
		cat >&2 <<-EOF
		����: ��⵽�㻹û�а�װ Kcptun��
		���� Kcptun �����ļ����𻵣�
		�����нű������°�װ Kcptun ����ˡ�
		EOF

		exit 1
	fi
}

# ����Ƿ�װ�� kcptun
is_installed() {
	if [ -d '/usr/share/kcptun' ]; then
		cat >&1 <<-EOF
		��ⷢ�����ɾɰ����������°�
		�°��н�Ĭ�ϰ�װĿ¼����Ϊ�� ${KCPTUN_INSTALL_DIR}
		�ű����Զ����ļ��Ӿɰ�Ŀ¼ /usr/share/kcptun
		�ƶ����°�Ŀ¼ ${KCPTUN_INSTALL_DIR}
		EOF
		any_key_to_continue
		(
			set -x
			cp -rf '/usr/share/kcptun' "$KCPTUN_INSTALL_DIR" && \
				rm -rf '/usr/share/kcptun'
		)
	fi

	if [ -d '/etc/supervisor/conf.d/' ] && [ -d "$KCPTUN_INSTALL_DIR" ] && \
		[ -n "$(get_installed_version)" ]; then
		return 0
	fi

	return 1
}

# ����Ƿ��Ѿ���װ
installed_check() {
	local instance_count=""
	instance_count="$(get_instance_count)"
	if is_installed && [ $instance_count -gt 0 ]; then
		cat >&1 <<-EOF
		��⵽���Ѱ�װ Kcptun �����, �����õ�ʵ������Ϊ ${instance_count} ��
		EOF
		while true
		do
			cat >&1 <<-'EOF'
			��ѡ����ϣ���Ĳ���:
			(1) ���ǰ�װ
			(2) ��������
			(3) ���ʵ��(��˿�)
			(4) ������
			(5) �鿴����
			(6) �鿴��־���
			(7) �Զ���汾��װ
			(8) ɾ��ʵ��
			(9) ��ȫж��
			(10) �˳��ű�
			EOF
			read -p "(Ĭ��: 1) ��ѡ�� [1~10]: " sel
			[ -z "$sel" ] && sel=1

			case $sel in
				1)
					echo "��ʼ���ǰ�װ Kcptun �����..."
					load_instance_config
					return 0
					;;
				2)
					select_instance
					instance_reconfig
					;;
				3)
					instance_add
					;;
				4)
					do_update
					;;
				5)
					select_instance
					instance_show
					;;
				6)
					select_instance
					instance_log
					;;
				7)
					manual_install
					;;
				8)
					select_instance
					instance_del
					;;
				9)
					do_uninstall
					;;
				10)
					;;
				*)
					echo "��������, ��������Ч���� 1~10!"
					continue
					;;
			esac

			exit 0
		done
	fi
}

action=${1:-"install"}
case "$action" in
	install|uninstall|update)
		do_${action}
		;;
	add|reconfig|show|log|del)
		instance_${action} "$2"
		;;
	manual)
		manual_install "$2"
		;;
	help)
		usage 0
		;;
	*)
		usage 1
		;;
esac