#!/bin/bash

set -e

# process files:
# /tmp/banned-ipv4.txt
# /tmp/banned-ipv6.txt
# with firewall-cmd as root to add to the banned ipset (ban all IPs in these files)



IPV4_FILE=banned-ipv4.txt
IPV6_FILE=banned-ipv6.txt
IPV4_IPSET_NAME=mailnesia-banned-ipv4
IPV6_IPSET_NAME=mailnesia-banned-ipv6


function file_exists() {
  local FILE=/tmp/$1
  if ! [[ -f $FILE ]]; then
    >&2 echo "File $FILE doesn't exist"
    return 1
  fi
}


function create_ipset() {
  local IPSET_NAME=$1
  local FAMILY=$2

  # create an ipset with the name specified as the first parameter, with an IP family specified in the second
  # parameter (e.g. inet or inet6)
  # (if they don't already exist)
  if ! firewall-cmd --permanent --ipset=$IPSET_NAME --get-description
  then
    firewall-cmd --permanent --new-ipset=$IPSET_NAME --type=hash:ip --option=family=$FAMILY --option=timeout=2147483
  fi
}



# add the file specified (under /tmp) in the second parameter to the ipset specified in the first parameter
function add_entries_from_file_to_ipset() {
  local IPSET_NAME=$1
  local FILE=$2
  firewall-cmd --ipset=$IPSET_NAME --add-entries-from-file=/tmp/$FILE
}


# apply permanent configuration to runtime
function reload() {
  firewall-cmd --reload
}


# main
if file_exists $IPV4_FILE
then
  create_ipset $IPV4_IPSET_NAME inet
  reload
  add_entries_from_file_to_ipset $IPV4_IPSET_NAME $IPV4_FILE

  # drop traffic for the loaded ipsets
  firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source ipset='$IPV4_IPSET_NAME' drop"
fi


if file_exists $IPV6_FILE
then
  create_ipset $IPV6_IPSET_NAME inet6
  reload
  add_entries_from_file_to_ipset $IPV6_IPSET_NAME $IPV6_FILE

  # drop traffic for the loaded ipsets
  firewall-cmd --permanent --add-rich-rule="rule family='ipv6' source ipset='$IPV6_IPSET_NAME' drop"
fi

# enable the listed ports
firewall-cmd --permanent --add-port=80/tcp --add-port=443/tcp --add-port=6443/tcp --add-port=25/tcp

reload

