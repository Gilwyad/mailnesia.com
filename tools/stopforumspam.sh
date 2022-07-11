#!/bin/bash

# 1) download Mailnesia email addresses listed on Stopforumspam and ban those
# 2) download IPs from Stopforumspam and save them to files
# Script to be ran daily. The IPs shall be banned using ban-ips-with-firewall-cmd.sh
# after the download.

# banned mailboxes
curl --silent --limit-rate 50k 'https://www.stopforumspam.com/downloads/listed_email_1.zip' | funzip | perl -ne 'print "$1\n" if m/^([^\@]+)\@mailnesia\.com$/i' | /home/peter/projects/mailnesia.com/tools/redis.pl ban_mailbox

# banned IPs

banned_IPs=$(mktemp --tmpdir banned_IPs-XXXXXX);
tor_IPs=$(mktemp --tmpdir tor_IPs-XXXXXX);

curl --silent --limit-rate 50k 'https://www.stopforumspam.com/downloads/listed_ip_1.zip' | funzip | sort > $banned_IPs

# download TOR exit node list to ignore

curl --silent --limit-rate 50k 'https://check.torproject.org/exit-addresses' | perl -ne 'next unless m/^ExitAddress/; print ((split / /)[1] . "\n");' | sort > $tor_IPs


# use only the lines (IPs) that are unique to FILE1 ( suppress column
# 2 (lines unique to FILE2) and column 3 (lines that appear in both
# files))

comm -23 $banned_IPs $tor_IPs | fgrep -v 172.93.51.149 > /tmp/banned-ipv4.txt

# IPV6 TODO: ignore server's own IPv6 address? 2602:ff16:1:0:1:ca:0:1
curl --silent --limit-rate 50k 'https://stopforumspam.com/downloads/listed_ip_1_ipv6.zip' | funzip | sort > /tmp/banned-ipv6.txt


# remove temporary files
rm $banned_IPs
rm $tor_IPs
