#!/bin/bash

HOSTNAME=''
URL='?<SCRIPT>alert("Cookie"+document.cookie)</SCRIPT>'
RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://${HOSTNAME}${URL}")
echo -e ${RESPONSE_CODE}

if [ "${RESPONSE_CODE}" = '403' ]; then
	exit 0
elif [ "${RESPONSE_CODE}" = '200' ]; then
	exit 2
else
	exit 3
fi
