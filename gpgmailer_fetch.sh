#! /bin/bash
#
# tested Linux Workstation (ubuntu+sendmail+procmail). YMMV.
#
# ---------------------------------------------------
# * fetch mails from remote locations/incoming dirs
# * decrypt with gnupg
# * feed into procmail
# ---------------------------------------------------

BASEDIR="${HOME}/.gpgmailer/"
CONFDIR="${BASEDIR}/.conf/"
INCOMING="${BASEDIR}/incoming/"
DONEDIR="${BASEDIR}/done/"
ERRORDIR="${BASEDIR}/error/"
TMPDIR="${BASEDIR}/tmp/"
SEEN="${DONEDIR}/seen"


LOGDIR=${BASEDIR}/log/
LOG_INC="${LOGDIR}/incoming.log"
LOG="${LOGDIR}/gpgmailer.log"
mkdir -pv "${BASEDIR}" || exit 128
mkdir -pv "${INCOMING}" || exit 128
mkdir -pv "${DONEDIR}" || exit 128
mkdir -pv "${ERRORDIR}" || exit 128
mkdir -pv "${TMPDIR}" || exit 128
mkdir -pv "${LOGDIR}" || exit 128

chmod 700 "${BASEDIR}" "${CONFDIR}" "${LOGDIR}" "${INCOMING}" "${DONEDIR}" "${ERRORDIR}" "${TMPDIR}"

exec >>"${LOG}"
exec 2>>"${LOG}"
chmod 600 "${LOG}"

touch "${SEEN}" || exit 128
chmod 600 "${SEEN}"

PASSFILE="${CONFDIR}/pass"
test -r "${PASSFILE}" || 
	{ echo "Missing ${CONFDIR}/pass" >&2; exit 128; }
chmod 400 "${PASSFILE}" 


CONF_SOURCES="${CONFDIR}/sources.conf"
test -r "${CONF_SOURCES}" || 
	{ echo "Missing ${CONF_SOURCES}" >&2; exit 128; }
chmod 600 "${CONF_SOURCES}"
source "${CONF_SOURCES}" || exit 128

test -n "${SOURCES}" ||
	{ echo "SOURCES is empty, need at least one rsync source" >&2; exit 128; }

# ----------------------------------------------------
# 1. fetch files from remote locations using rsync+ssh
# ----------------------------------------------------
OPTS='-avHWx --remove-source-files --include="*.asc" --exclude="*"'
for SOURCE in ${SOURCES}; do 
	echo "Get from ${SOURCE}"
	rsync ${OPTS} "${SOURCE}"  "${INCOMING}" 
done


# ----------------------------------------------------
# 2. decrypt every *.asc from incoming, feed to procmail and move to "done"
# ----------------------------------------------------
while IFS='|' read ID X FILE; do 
	# empty ID?
	test -z "${ID}" && 
		{ echo "Skip Empty ID X=${X}, FILE=${FILE}" >&2; continue; }

	# X must always be empty here
	test -z "${X}" || 
		{ echo "Skip nonempty X=${X}, ID=${ID}, FILE=${FILE}" >&2; continue; }

	# FILE must be at least exist and readable
	test -r "${FILE}" || 
		{ echo "Skip non existing or unreadble FILE=${FILE} ID=${ID}" >&2; continue; }

	# input seems valid here

	# a/bc/abcdef0123
	SUBDIR="${ID:0:1}/${ID:1:2}"

	# check for already seen this ID (shecksum)
	grep --quiet --fixed-strings "${ID}" "${SEEN}" && 
		{ mkdir -pv "${ERRORDIR}/${SUBDIR}" && 
		  mv -v "${FILE}" "${ERRORDIR}/${SUBDIR}/${ID}_seen"; continue ; }

	# not seen yet, try to decrypt and feed to procmail
	TMPFILE="${TMPDIR}/${ID}_tmp"
	gpg --passphrase-file "${PASSFILE}" --batch --output "${TMPFILE}" --decrypt "${FILE}" ||
		{ mkdir -pv "${ERRORDIR}/${SUBDIR}" && 
		  mv -v "${FILE}" "${ERRORDIR}/${SUBDIR}/${ID}_gpg_failed"; continue; }

	procmail < "${TMPFILE}" ||
		{ mkdir -pv "${ERRORDIR}/${SUBDIR}" &&
		  mv -v "${FILE}" "${ERRORDIR}/${SUBDIR}/${ID}_procmail_failed" ; continue ; }

	echo "$(date)|${ID}|${FILE}" >> "${SEEN}"
	mkdir -pv "${DONEDIR}/${SUBDIR}"
	mv -v "${FILE}" "${DONEDIR}/${SUBDIR}/${ID}_done" && 
	rm "${TMPFILE}"

done < <(find "${INCOMING}" -name "*.asc" -exec sha256sum  {} + | tr ' ' '|' | tee -a "${LOG_INC}")

