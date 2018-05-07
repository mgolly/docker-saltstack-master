#!/bin/sh
#
# Copyright (c) 2018 mgolly (mgolly@users.noreply.github.com)
# Apache 2.0 Licensed

abort() {
    msg="$1"
    echo "$msg"
    echo "=> Environment was:"
    env
    echo "=> Program terminated!"
    exit 1
}

create_group() {
	if [ -z "$1" ] || [ -z "$2" ]
	then
		abort "=> create_group requires 2 args: (group, list)."
	elif ! addgroup "$1"
	then
		abort "=> Failed to create group \"$1\"!"
	else
		for user in $2
		do
			if ! adduser "${user}" "$1"
			then
				abort "=> Failed to add user \"${user}\" to group \"$1\""
			fi
		done
	fi
}

create_user() {
	if [ -z "$1" ] || [ -z "$2" ]
	then
		abort "=> create_user requires 2 args: (user, password)."
	elif ! adduser -D "$1"
	then
		abort "=> Failed to create user \"$1\"."
	elif ! echo "$1:$2" | chpasswd >/dev/null 2>&1
	then
		abort "=> Failed to set user \"$1\" password."
	fi
}

set_access() {
	if [ -z "$1" ] || [ -z "$2" ]
	then
		echo "=> set_access requires 2 args: (user, access).  No access set for \"$1\""
	else
		printf "%s" "external_auth:\n  pam:\n    $1:\n" > "/etc/salt/master.d/access_$1.conf"
		printf "%s" "$2" | sed 's/^/      /g' >> "/etc/salt/master.d/access_$1.conf"
	fi
}

# SaltStack versions
salt --versions-report

# Salt master keys?
if [ -z "${MASTER_PEM}" ] && [ -z "${MASTER_PUB}" ]
then
	echo "=> No master keys supplied, master will create keys on first run."
elif [ -z "${MASTER_PEM}" ] || [ -z "${MASTER_PUB}" ]
then
	abort "=> Both SALT_MASTER_PEM and SALT_MASTER_PUB must be set."
elif [ -f "/run/secrets/${MASTER_PEM}" ] && [ -f "/run/secrets/${MASTER_PUB}" ]
then
	echo "=> Found master keys in docker swarm secrets"
	cp "/run/secrets/${MASTER_PEM}" /etc/salt/pki/master/master.pem
	cp "/run/secrets/${MASTER_PUB}" /etc/salt/pki/master/master.pub
else
	echo "=> Found master keys in environment variables"
	printf "%s" "${MASTER_PEM}" > /etc/salt/pki/master/master.pem
	printf "%s" "${MASTER_PUB}" > /etc/salt/pki/master/master.pub
fi

# Salt minion keys?
# Only possible if salt master keys were set
if ! [ -f "/etc/salt/pki/master/master.pem" ]
then
	echo "=> No master key set, no minions will be pre-accepted."
elif [ -z "${MINIONS}" ]
then
	echo "=> No minion keys supplied, no minions will be pre-accepted."
else
	for minion in ${MINIONS}
	do
		var_minionkey="${minion}_KEY"

		if [ -n "${!var_minionkey}" ]
		then
			echo "=> Found minion key for ${minion} in environment variable"
			printf "%s" "${!var_minionkey}" > "/etc/salt/pki/master/minion/${minion}"
		elif [ -f "/run/secrets/${var_minionkey}" ]
		then
			echo "=> Found minion key for ${minion} in docker swarm secrets"
			cp "/run/secrets/${var_minionkey}" "/etc/salt/pki/master/minion/${minion}"
		else
			abort "=> Failed to pre-accept minion \"${minion}\"."
		fi
	done
fi

# Salt accounts?
if [ -z "${ACCOUNTS}" ]
then
	echo "=> No accounts supplied, salt-api/molten may not be accessable."
else
	for account in ${ACCOUNTS}
	do
		var_pass="${account}_PASSWORD"
		var_list="${account}_LIST"
		var_access="${account}_ACCESS"

		if [ -n "${!var_pass}" ]
		then
			echo "=> Found password for \"${account}\" in environment variable."
			create_user "${account}" "${!var_pass}"
			set_access "${account}" "${!var_access}"
		elif [ -f "/run/secrets/${var_pass}" ]
		then
			echo "=> Found password for \"${account}\" in docker swarm secrets."
			create_user "${account}" "$(cat /run/secrets/${var_pass})"
			set_access "${account}" "$(cat /run/secrets/${var_access})"
		elif [ -n "${!var_list}" ]
		then
			echo "=> Found list for '${account}' in environment variable."
			create_group "${account}" "${!var_list}"
			set_access "${account}\%" "${!var_access}"
		elif [ -f "/run/secrets/${var_list}" ]
		then
			echo "=> Found list for \"${account}\" in docker secrets."
			create_group "${account}" "$(cat /run/secrets/${var_list})"
			set_access "${account}\%" "$(cat /run/secrets/${var_access})"
		else
			abort "=> Unknown account type for \"${account}\"."
		fi
	done
fi

# Other salt master config
if [ -z "${CONFIGS}" ]
then
	echo "=> No extra config supplied."
else
	for config in ${CONFIGS}
	do
		var_config="${config}_CONFIG"

		if [ -n "${!var_config}" ]
		then
			echo "=> Found extra config \"${config}\" in environment variable."
			printf "%s" "${!var_config}" > "/etc/salt/master.d/${config}.conf"
		elif [ -f "/run/config/${var_config}" ]
		then
			echo "=> Found extra config \"${config}\" in docker swarm config."
			cp "/run/config/${var_config}" "/etc/salt/master.d/${config}.conf"
		elif [ -f "/run/secrets/${var_config}" ]
		then
			echo "=> Found extra config \"${config}\" in docker swarm secrets."
			cp "/run/secrets/${var_config}" "/etc/salt/master.d/${config}.conf"
		else
			abort "=> Failed to copy extra config \"${config}\"."
		fi
	done
fi

# Salt API cert(s)?
if [ -z "${API_CERT_INDEX}" ]
then
	echo "=> No certs supplied, creating self-signed cert:"
	salt-call --local tls.create_self_signed_cert cacert_path='/etc/salt/pki' tls_dir='api' -l error
	rm -f /var/log/salt/minion
elif [ -z "${API_CERT_CRT}" ] || [ -z "${API_CERT_KEY}" ]
then
	abort "=> API_CERT_INDEX, API_CERT_CRT, and API_CERT_KEY must all be set."
elif [ "${API_CERT_CRT}" != "${API_CERT_CRT%BEGIN CERTIFICATE*}" ]
then
	echo "=> Found salt-api cert in environment variables"
	printf "%s" "${API_CERT_INDEX}" > "/etc/salt/pki/index.txt"
	printf "%s" "${API_CERT_CRT}"   > "/etc/salt/pki/api/localhost.crt"
	printf "%s" "${API_CERT_KEY}"   > "/etc/salt/pki/api/localhost.key"
else
	echo "=> Found salt-api cert in docker swarm secrets"
	cp "/run/secrets/${API_CERT_INDEX}" "/etc/salt/pki/index.txt"
	cp "/run/secrets/${API_CERT_CRT}"   "/etc/salt/pki/api/certs/localhost.crt"
	cp "/run/secrets/${API_CERT_KEY}"   "/etc/salt/pki/api/certs/localhost.key"
fi

echo

# Start SaltStack Syndic?
if ! grep -r -e ^syndic_master /etc/salt/master* >/dev/null 2>&1
then
	echo "=> Not starting salt syndic as no syndic_master is set in configs."
elif [ ! -x "$(which salt-syndic)" ]
then
	echo "=> Not starting salt syndic as there is no salt-syndic executable."
else
	echo "=> Starting salt-syndic."
	salt-syndic --daemon --log-level="${LOG_LEVEL:-error}" &
fi

# Start SaltStack API / Molten UI?
if ! grep -r -e ^rest_cherrypy /etc/salt/master* >/dev/null 2>&1
then
	echo "=> Not starting salt api as no 'rest_cherrypy' is set in configs."
elif [ ! -x "$(which salt-api)" ]
then
	echo "=> Not starting salt api as there is no salt-api executable."
else
	echo "=> Starting salt-api."
	salt-api --daemon --log-file-level="${LOG_LEVEL:-error}" &
fi

# Start SaltStack Master
echo "=> Starting salt-master."
exec salt-master --log-level="${LOG_LEVEL:-error}"
