#!/bin/bash

# downloads banned email addresses and IPs from stopforumspam.com and
# adds them to redis - to be ran daily


# banned mailboxes
curl --silent --limit-rate 50k 'https://www.stopforumspam.com/downloads/listed_email_1.zip' | funzip | perl -ne 'print "$1\n" if m/^([^\@]+)\@mailnesia\.com$/i' | /home/peter/projects/mailnesia.com/tools/redis.pl ban_mailbox

# banned IPs

banned_IPs=$(mktemp --tmpdir banned_IPs-XXXXXX);
tor_IPs=$(mktemp --tmpdir tor_IPs-XXXXXX);

#IP_list=$(curl --silent --limit-rate 50k 'https://www.stopforumspam.com/downloads/listed_ip_1.zip' | funzip);
curl --silent --limit-rate 50k 'https://www.stopforumspam.com/downloads/listed_ip_1.zip' | funzip | sort > $banned_IPs

# download TOR exit node list to ignore

#TOR_exit_nodes=$(curl --silent --limit-rate 50k 'https://check.torproject.org/exit-addresses' | perl -ne 'next unless m/^ExitAddress/; print ((split / /)[1] . "\n");');
curl --silent --limit-rate 50k 'https://check.torproject.org/exit-addresses' | perl -ne 'next unless m/^ExitAddress/; print ((split / /)[1] . "\n");' | sort > $tor_IPs


# use only the lines (IPs) that are unique to FILE1 ( suppress column
# 2 (lines unique to FILE2) and column 3 (lines that appear in both
# files))

comm -23 $banned_IPs $tor_IPs | fgrep -v 162.250.144.109 | /home/peter/projects/mailnesia.com/tools/redis.pl ban_ip



#echo $IP_list | grep -v 162.250.144.109 $TOR_exit_nodes | /home/peter/projects/mailnesia.com/tools/redis.pl sadd banned_IPs






# remove temporary files
rm $banned_IPs
rm $tor_IPs
