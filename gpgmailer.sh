#! /bin/sh -f 
#
# tested with FreeBSD+sendmail+gpg
#
# local MTA: 
# * encrypt incoming mails using GnuPG
# * to be used as ~/.forward: e.g. 
#      "|exec /home/user/bin/gpgmailer.sh"

# -----------------------------------------------------------------------
# CONFIG: gpg recipient, public key must be in pubkeys and fully trusted
#
# CHANGE THIS!!!
# -----------------------------------------------------------------------
RCPT="changethis@example.com"

# -----------------------------------------------------------------------
# INIT Logging: we don't know HOME yet, log into tmpfile
# -----------------------------------------------------------------------
LOG="$(mktemp -t gpgmailer)"

exec >>"${LOG}"
exec 2>>"${LOG}"
#set -x

# -----------------------------------------------------------------------
# get USER and HOME as we're going to have an empty environment  
# -----------------------------------------------------------------------
OIFS="${IFS}"            
IFS=":"
# ensure pathname expansion disabled here (noglob) as the second field 
# from passwd will be `*' in most cases!  /bin/sh -f
set -- $(getent passwd $(whoami))
IFS="${OIFS}"
USER="${1}"
HOME="${6}"

# -----------------------------------------------------------------------
# environment done, now set up directories and files
# -----------------------------------------------------------------------
BASEDIR="${HOME}/.gpgmailer/"
INCOMING="${BASEDIR}/incoming/"

LOGDIR=${BASEDIR}/log/
OLDLOG="${LOG}"
LOG="${LOGDIR}/gpgmailer.log"

NOW="$(date "+%Y%m%d%H%M%S")"
HOST="$(hostname -f)"


mkdir -pv "${BASEDIR}" "${LOGDIR}" "${INCOMING}" || 
	exit 128
chmod 700 "${BASEDIR}" "${LOGDIR}" "${INCOMING}"
touch "${LOG}" || 
	exit 128
chmod 600 "${LOG}"

# continue loggin into ${LOG}
exec >>"${LOG}"
exec 2>>"${LOG}"
cat "${OLDLOG}" >> "${LOG}" && 
	rm "${OLDLOG}"

ENC_TMP="$(mktemp "${INCOMING}/${HOST}_${USER}_${NOW}_XXXXXX")"
ENC_FILE="${ENC_TMP}.asc"

test -f "${ENC_TMP}" || 
	{ echo "Cannot create tmpfile ${ENC_TMP}" >&2; exit 128; }

# we need just the temporary filename, 
# gpg2 wont override existing files, so remove it here
rm "${ENC_TMP}" || 
	exit 1

# -----------------------------------------------------------------------
# init and logging done, now receive from stdin
# -----------------------------------------------------------------------

/usr/local/bin/gpg --no-secmem-warning --armor --recipient "${RCPT}" --output "${ENC_TMP}" --encrypt && 
	mv -v "${ENC_TMP}" "${ENC_FILE}"
