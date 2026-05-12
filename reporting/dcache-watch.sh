#/bin/bash

# Exit on any error
set -e

loghost=
user_for_loghost=
pathprefix=

if [ -z "$loghost" ] || [ -z "$user_for_loghost" ] || [ -z "$pathprefix" ]; then
  echo "Variables loghost, user_for_loghost and pathprefix needs to be defined inside this script."
  echo "pathprefix will be removed from the file path to fit more text in to screen"
  echo "unless -f is specified."
  echo
  echo "For example:"
  echo "loghost=dcache.somewhere.example"
  echo "user_for_loghost=root"
  echo "pathprefix=/pnfs/csc.fi/data/cms"
  exit 1
fi

print_help()
{
   echo "This script translates dcache file transfer logs aka billing logs"
   echo "to human readable format. It connects to dcache server over ssh"
   echo "to read the logs and processes them on local computer with /usr/bin/gawk"
   echo
   echo "Syntax: $(basename "$0") [-dfhi] [date/time]"
   echo
   echo "Options:"
   echo "-d     Print transfers on specific date and time. Format YYYY-MM-DDTHH:MM:SS eg. 2025-11-25T10:12:14"
   echo "       or 2025-11-25T10:12 or 2025-11-25T10 or 2025-11-25."
   echo "-f     Show full file path"
   echo "-h     Print this help."
   echo "-i     Include headnode logs which are not errors. This doubles the data."
   echo "-s     Show source address column"
   echo
   echo "Without -d live log is shown."
}

while getopts ":dfhis" option; do
   case $option in
      d) date=yes;;
      f) showfullpath=yes;;
      h) print_help
         exit;;
      i) headnodelogs=yes;;
      s) source=yes;;
   esac
done
shift $((OPTIND - 1))

if [ ! -f /usr/bin/gawk ]; then
  echo "/usr/bin/gawk not found, exiting."
  exit 1
fi

if [ "$date" ]; then
  timestamp=$1
  timestamp_length=${#timestamp}
  if [ $timestamp_length -gt 19 ]; then echo "Date/time has too many chars, exiting." && exit 1; fi

  # Parse year, month and day of month from timestamp
  # It is position and number of chars
  year=${timestamp:0:4}
  month=${timestamp:5:2}
  day=${timestamp:8:2}
  todaynoextrachars="$year$month$day"

  if [ "$todaynoextrachars" -gt `date +"%Y%m%d"` ]; then
    echo "Date is in the future."
    exit 1
  fi

  timeforgrepping=${timestamp:11:8}

  datelogfile="${year}.${month}.${day}"
  echo
  echo "Scanning for $timestamp"
  echo
  datelogfiletoday=`date +"%Y.%m.%d"`

  if [ $datelogfile == $datelogfiletoday ]; then
    if [ -n $timeforgrepping ]; then
      watchcommand="cat /var/lib/dcache/billing/${year}/${month}/billing-${datelogfile} | grep \"^${month}.${day} ${timeforgrepping}\""
    else
      watchcommand="cat /var/lib/dcache/billing/${year}/${month}/billing-${datelogfile}"
    fi
  else
    if [ -n $timeforgrepping ]; then
      watchcommand="bzcat /var/lib/dcache/billing/${year}/${month}/billing-${datelogfile}.bz2 | grep \"^${month}.${day} ${timeforgrepping}\""
    else
      watchcommand="bzcat /var/lib/dcache/billing/${year}/${month}/billing-${datelogfile}.bz2"
    fi
  fi
else
  today=`date +"%Y.%m.%d"`
  month=`date +"%m"`
  year=`date +"%Y"`
  watchcommand="tail -f /var/lib/dcache/billing/${year}/${month}/billing-${today}"
fi

function awk_magic {
  /usr/bin/gawk -v headnodelogs="$headnodelogs" -v showfullpath="$showfullpath" -v pathprefix="@/$pathprefix+/" -v source="$source" '
    {
      # https://www.gnu.org/software/gawk/manual/html_node/Splitting-By-Content.html
      FPAT = "(\\[[^\\[]+\\])|({[^{]+})|([^ ]+)"
      CONVFMT="%.1f"
    }
    {
      if ( showfullpath != "yes" ) { gsub(pathprefix, "") }
      gsub(/\[|\]/, "", $3)
    }

    /Domain:request/ {
      gsub(/\[|\]/, "", $4)
      gsub(/\[|\]/, "", $6)
      gsub(/{|}/, "", $10)
      gsub(/door:/, "", $3)
      gsub(/@.*Domain/, "", $3)
      gsub(/:request/, "", $3)
      match ($4, /[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$|[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}$/, matchres)
      split($10,ten,":\"")
      gsub(/"/, "", ten[2])
      if ( ten[1] != 0 )
      {
        if (source == "yes") {
          printf "%8s %-22s %4s %-39s %-22s %-100s\n", $2, $3, "\033[31mERRO\033[0m", matchres[0], "", "\033[31m"ten[2]"\033[0m "$6
        }
        else {
          printf "%8s %-22s %4s %-22s %-100s\n", $2, $3, "\033[31mERRO\033[0m", "", "\033[31m"ten[2]"\033[0m "$6
        }
      }
      else if ( headnodelogs == "yes" )
      {
        # Print all headnode logs including those which are not errors
        split($5,five,",")
        gsub(/\]/, "", five[2])
        if ( source == "yes" ) {
          printf "%8s %-22s %4s %-39s %-22s %-100s\n", $2, $3, "DONE", "", (five[2]/1000000)"MB in "($8/1000)"s", $6
        }
        else {
          printf "%8s %-22s %4s %-22s %-100s\n", $2, $3, "DONE", (five[2]/1000000)"MB in "($8/1000)"s", $6
        }
      }
    }

    $3 ~ /Domain:remove/ {
      gsub(/\[|\]/, "", $6)
      gsub(/@.*Domain/, "", $3)

      if ( $3 ~ /door:/ )
      {
        gsub(/door:/, "", $3)
        gsub(/:remove/, "", $3)
        gsub(/\[|\]/, "", $5)
        split($5,five,",")

        if (source == "yes") {
          printf "%8s %-22s %4s %-39s %-22s %-100s\n", $2, $3, "\033[33mREMO\033[0m", "", "     "(five[2]/1000000"MB"), $6
        }
        else {
          printf "%8s %-22s %4s %-22s %-100s\n", $2, $3, "\033[33mREMO\033[0m", (five[2]/1000000"MB"), $6
        }
      }
      else if ( $3 ~ /pool:/ )
      {
        gsub(/\[|\]/, "", $4)
        split($4,four,",")
        gsub(/pool:/, "", $3)
        gsub(/:remove/, "", $3)
        if (source == "yes") {
          printf "%8s %-22s %4s %-39s %-22s %-100s\n", $2, $3, "\033[33mREMO\033[0m", "", "     "(four[2]/1000000"MB"), four[1]
        }
        else {
          printf "%8s %-22s %4s %-22s %-100s\n", $2, $3, "\033[33mREMO\033[0m", (four[2]/1000000"MB"), four[1]
        }
      }
      else
      {
        # Maybe nothing gets this far
        gsub(/\[|\]/, "", $5)
        split($5,five,",")
        printf "%8s %-22s %4s %-22s %-100s\n", $2, $3, "\033[33mREMO\033[0m", (five[2]/1000000"MB"), five[1]
      }
    }

    ( $3 ~ /pool:.*:transfer/ ) {
      gsub(/\[|\]/, "", $4)
      gsub(/\[|\]/, "", $5)
      gsub(/{|}/, "", $10)
      gsub(/{|}/, "", $12)
      gsub(/pool:/, "", $3)
      gsub(/:transfer/, "", $3)
      split($4,four,",")
      gsub("true","\033[94mWRIT\033[0m",$9)
      gsub("false","\033[34mREAD\033[0m",$9)

      if ( $10 ~ /^Xrootd-5.0:/ ) { 
        proto="XR50"
        gsub(/^Xrootd-5.0:/, "", $10)
        match ($10, /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|^[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}/, matchres)      }
      else if ( $10 ~ /^Http-1.1:/ ) {
        proto="HTTP"
        gsub(/^Http-1.1:/, "", $10)
        match ($10, /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|^[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}/, matchres)
      }
      else if ( $10 ~ /^Https-1.1:/ ) {
        proto="HTTPS"
        gsub(/^Https-1.1:/, "", $10)
        match ($10, /^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|^[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}:[0-9a-fA-F]{1,4}/, matchres)
      }
      else if ( $10 ~ /^RemoteHttpsDataTransfer-1.1:/ ) {
        proto="RHTTP"
        gsub(/^RemoteHttpsDataTransfer-1.1:https:\/\//, "", $10)
        match ($10, /[^:]*/, matchres)
      }
      else {
        proto="NoMatch"
        $10="NoProtocolMatchNoSource"
      }

      split($12,twelve,":\"")
      gsub(/"/, "", twelve[2])

      if (source == "yes") {
        if ( twelve[1] != 0 ) {
          printf "%8s %-22s %4s %-39s %-22s %-1s %4s %-1s\n", $2, $3, $9, matchres[0], proto" "(four[2]/1000000"MB")" "($8/1000)"s", "\033[31mERRO\033[0m", "\033[31m"twelve[2]"\033[0m", $5
        }
        else if ( $5 == "Unknown" ) {
          printf "%8s %-22s %4s %-39s %-22s %-100s\n", $2, $3, $9, matchres[0], proto" "(four[2]/1000000"MB")" "($8/1000)"s", four[1]
        }
        else {
          printf "%8s %-22s %4s %-39s %-22s %-100s\n", $2, $3, $9, matchres[0], proto" "(four[2]/1000000"MB")" "($8/1000)"s", $5
        }
      }
      else {
        if ( twelve[1] != 0 ) {
          printf "%8s %-22s %4s %-22s %-1s %4s %-1s\n", $2, $3, $9, proto" "(four[2]/1000000"MB")" "($8/1000)"s", "\033[31mERRO\033[0m", "\033[31m"twelve[2]"\033[0m", $5
        }
        else if ( $5 == "Unknown" ) {
          printf "%8s %-22s %4s %-22s %-100s\n", $2, $3, $9, proto" "(four[2]/1000000"MB")" "($8/1000)"s", four[1]
        }
        else {
          printf "%8s %-22s %4s %-22s %-100s\n", $2, $3, $9, proto" "(four[2]/1000000"MB")" "($8/1000)"s", $5
        }
      }
    }
  '
}

ssh ${user_for_loghost}@${loghost} $watchcommand | awk_magic
