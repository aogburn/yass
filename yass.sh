#!/bin/bash
#
# Yass is just 'Yet Another Script' Script.  It is a main script to call
# and more quickly decompress and analyze a directory of various JBoss
# data files including access logs, GC logs (via garbagecat), server
# logs(via yala), and thread dumps (via yatda). Create a $HOME/.yass/config
# to specify locations of these dependencies.
#
# Usage: sh ./yass.sh <directory> (or current directory if not specified)
LC_ALL=C

VALID_UPDATE_MODES=(force ask never)

YASS_SH="$(basename "$(test -L "$0" && readlink "$0" || echo "$0")")"

cleanup() {
    pkill -P $$
}

for sig in INT QUIT HUP TERM; do
  trap "
    cleanup
    trap - $sig EXIT
    kill -s $sig "'"$$"' "$sig"
done
trap cleanup EXIT

usage() {
    if [ ! "x$1" = "x" ]; then
        echo
        echo -e "$1"
        echo
    fi
    echo "Usage:"
    echo " sh ./$YASS_SH <options> <directory>"
    echo
    echo "Yass is just 'Yet Another Script' script.  It is a main script to call"
    echo "and more quickly decompress and analyze a directory of various JBoss"
    echo "data files including access logs, GC logs (via garbagecat), server"
    echo "logs(via yala), and thread dumps (via yatda)."
    echo
    echo "Options:"
    echo " -a, --accessLog         recursively look for and summarize access logs"
    echo " -g, --gcLog             recursively look for and summarize GC logs via a specified garbagecat"
    echo " -s, --serverLog         recursively look for and sumarize server logs via a specified yala.sh"
    echo " -t, --threadDump        recursively look for and summarize thread dumps via a specified yatda.sh"
    echo " -u, --updateMode        the update mode to use, one of [${VALID_UPDATE_MODES[*]}], default: force"
    echo " -x, --extract           recursively look for and extract compressed files in the directory"
    echo " -h, --help              show this help" 
}

# is_valid_option <argument> <array> <option>
is_valid_option() {
    ARGUMENT=$1
    ARRAY=$2
    OPTION=$3
    
    if [[ ! " ${ARRAY[*]} " =~ " ${ARGUMENT} " ]]; then
        echo "${YASS_SH}: invalid argument '$ARGUMENT' for option '$OPTION', must be one of [${ARRAY[*]}]"
        return 22 # -> Invalid Argument
    else
        return 0  # -> Success
    fi
}

# wait for a pending process to complete so we don't exceed our parallelism limit and swamp the system
wait_for_pids() {
    joblist=($(jobs -p))
    while (( ${#joblist[*]} >= $PARALLEL_LIMIT ))
    do
        wait -n
        joblist=($(jobs -p))
    done
}


# source a global $HOME/.yass/config if available
if [ -d $HOME/.yass ] && [ -f $HOME/.yass/config ]; then
    source $HOME/.yass/config 
fi

# set required variables with default values, if not set in $HOME/.yass/config
# update options
[ -z $UPDATE_MODE ] && UPDATE_MODE="force"
[ -z $MD5 ] && MD5="https://raw.githubusercontent.com/aogburn/yass/main/md5"
[ -z $REMOTE_YASS_SH ] && REMOTE_YASS_SH="https://raw.githubusercontent.com/aogburn/yass/main/yass.sh"
# other
[ -z $PARALLEL_LIMIT ] && PARALLEL_LIMIT="10"
[ -z $GARBAGECAT_OPTS ] && GARBAGECAT_OPTS="-p -t 40"
# Setup the JVM
if [ "x$JAVA" = "x" ]; then
    if [ "x$JAVA_HOME" != "x" ]; then
        JAVA="$JAVA_HOME/bin/java"
    else
        JAVA="java"
    fi
fi

# parse the cli options
OPTS=$(getopt -o 'a,g,s,t,x,h,u:' --long 'accessLog,gcLog,serverLog,threadDump,extract,help,updateMode:' -n "${YASS_SH}" -- "$@")

# if getopt has a returned an error, exit with the return code of getopt
res=$?; [ $res -gt 0 ] && exit $res

eval set -- "$OPTS"
unset OPTS

OPTIONS_SET="false"
while true; do
    case "$1" in
        '-h'|'--help')
            usage; exit 0; shift
            ;;
        '-a'|'--accessLog')
            ACCESS="true"; OPTIONS_SET="true"; shift
            ;;
        '-g'|'--gcLog')
            GC="true"; OPTIONS_SET="true"; shift
            ;;
        '-s'|'--serverLog')
            SERVER="true"; OPTIONS_SET="true"; shift
            ;;
        '-t'|'--threadDump')
            THREAD="true"; OPTIONS_SET="true"; shift
            ;;
        '-x'|'--extract')
            EXTRACT="true"; OPTIONS_SET="true"; shift
            ;;
        '-u'|'--updateMode')
            is_valid_option "$2" "${VALID_UPDATE_MODES[*]}" "-u, --update"
            result=$?
            if [ $result -gt 0 ]; then
                exit $result
            fi
            UPDATE_MODE=$2
            shift 2
            ;;
        '--') shift; break;;
        * )
            echo "Invalid Option: $1"
            echo ""
            usage; exit; shift
            ;;
    esac
done

# check if directory is given
if [ $# -eq 0 ]; then
    # if not, process current directory
    TARGET_DIR=`pwd`
else
    # otherwise after parsing the options, '$1' is the directory name
    TARGET_DIR=$1
fi

EXT=".yass"
DIR=`dirname "$(readlink -f "$0")"`
DEST=$TARGET_DIR/summary$EXT

# Colors
export RED='\033[0;31m'
export BLUE='\033[0;34m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export NC='\033[0m'

# Check for a new yass.sh if UPDATE_MODE is not 'never'
if [ "$UPDATE_MODE" != "never" ]; then
    echo "Checking script update. Use option '-u never' to skip the update check"

    SUM=`md5sum $DIR/$YASS_SH | awk '{ print $1 }'`
    NEWSUM=$(curl -s $MD5)

    if [ "x$NEWSUM" != "x" ]; then
        if [ $SUM != $NEWSUM ]; then

            echo
            echo "$YASS_SH - $SUM - local"
            echo "$YASS_SH - $NEWSUM - remote"

            if [ "$UPDATE_MODE" = "ask" ]; then
                while true; do
                    echo
                    read -p "A new version of $YASS_SH is available, do you want to update?" yn
                    case $yn in
                        [Yy]* ) UPDATE="true"; break;;
                        [Nn]* ) UPDATE="false"; break;;
                        * ) echo "Choose yes or no.";;
                    esac
                done
            else
                UPDATE="true"
            fi

            if [ "$UPDATE" = "true" ]; then
                echo "Downloading new version. Please re-run $YASS_SH."
                wget -q $REMOTE_YASS_SH -O $DIR/$YASS_SH
                exit
            fi
        fi
    fi
    echo
    echo "Checks complete."
fi

if [ ! -d "$TARGET_DIR" ]; then
    usage "${YELLOW}<DIRECTORY> '$TARGET_DIR' does not exist.${NC}"
    exit
fi



# First extract any files
if [ "$OPTIONS_SET" = "false" ] || [ "$EXTRACT" = "true" ]; then
    aunpack --version > /dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}aunpack command not found.  Cannot successfully extract files.  Ensure atool package is installed.${NC}"
    else
        CHECK_FILES=true
        while [ $CHECK_FILES == true ]; do
            echo -e "${GREEN}Extracting files${NC}"
            pids=()
            CHECK_FILES=false
            for file in `find $TARGET_DIR -type f \( -iname \*.zip -o -iname \*.7z -o -iname \*.Z -o -iname \*.gz -o -iname \*.rar  -o -iname \*.bz2 -o -iname \*.xz -o -iname \*.tar -o -iname \*.tar.bz2 -o -iname \*.tar.gz -o -iname \*.tar.xz  -o -iname \*.tgz -o -iname \*.tbz2 \)`; do
                echo "    Extracting $file"
                mkdir $file-extract
                aunpack -X $file-extract $file; rm -rf $file &
                pids+=($!)
                # We extracted, so check again in case there were nested compressed archives
                CHECK_FILES=true
            done

            # wait for all extract pids
            for pid in ${pids[*]}; do
                wait $pid
            done

            # remove any space in file names to simplify processing and avoid errors
            while read line
            do
                echo -e "${GREEN}Removing space from $line${NC}"
                mv "$line" "${line// /_}"
            done < <(find $TARGET_DIR -iname "* *")
        done
        echo -e "${GREEN}File extraction complete${NC}"
    fi
    echo
fi


# remove any space in file names to simplify processing
while read line
do
    echo -e "${GREEN}Removing space from $line${NC}"
    mv "$line" "${line// /_}"
done < <(find $TARGET_DIR -iname "* *")


# Summarize server logs
if [ "$OPTIONS_SET" = "false" ] || [ "$SERVER" = "true" ]; then

    if [ x"$YALA_SH" == x ]; then
        echo -e "${RED}<YALA_SH> variable not specified.  Cannot summarize server logs.  Specify <YALA_SH> in $HOME/.yass/config${NC}"
    else
        echo -e "${GREEN}## Finding and summarizing server logs in $TARGET_DIR with $YALA_SH ##${NC}"
        NUMBER_SERVER_LOGS=0
        server_pids=()
        for file in `find $TARGET_DIR -type f -iname \*server\*log\*`; do
            if [[ ${file} != *".yala"* ]] && [[ ${file} != *".yass" ]]; then
                echo "    Summarizing $file with $YALA_SH"
                #$YALA_SH -u never $file > $file.yala-summary &
                $YALA_SH -u never $file &> /dev/null &
                server_pids+=($!)
                NUMBER_SERVER_LOGS=$((NUMBER_SERVER_LOGS+1))
            fi
        done
    fi
    echo
fi



# Summarize thread dumps
if [ "$OPTIONS_SET" = "false" ] || [ "$THREAD" = "true" ]; then
    if [ x"$YATDA_SH" == x ]; then
        echo -e "${RED}<YATDA_SH> variable not specified.  Cannot summarize thread dumps.  Specify <YATDA_SH> in $HOME/.yass/config${NC}"
    else
        echo -e "${GREEN}## Finding and summarizing thread dump files in $TARGET_DIR with $YATDA_SH ##${NC}"
        NUMBER_THREAD_DUMPS=0
        for file in `grep -lR "Full thread dump " $TARGET_DIR`; do
            isFile=`file $file | grep "ASCII text"`
            if [ "$isFile" != "" ]; then
                echo "    Summarizing $file with $YATDA_SH"
                #$YATDA_SH -u never $file > $file.yatda-summary &
                $YATDA_SH -u never $file &> /dev/null &
                dump_pids+=($!)
                NUMBER_THREAD_DUMPS=$((NUMBER_THREAD_DUMPS+1))
            fi
        done
    fi
    echo
fi



# Summarize gc logs
if [ "$OPTIONS_SET" = "false" ] || [ "$GC" = "true" ]; then
    if [ x"$GARBAGECAT" == x ]; then
        echo -e "${RED}<GARBAGECAT> variable not specified.  Cannot summarize GC logs.  Specify <GARBAGECAT> jar location in $HOME/.yass/config${NC}"
    else
        echo -e "${GREEN}## Finding and summarizing GC files in $TARGET_DIR with $GARBAGECAT ##${NC}"
        i=0
        gc_pids=()
        NUMBER_GC_LOGS=0
        for file in `find $TARGET_DIR -type f -iname \*gc\*log\*`; do
            if [[ ${file} != *".garbagecat-report" ]] && [[ ${file} != *".yass"* ]]; then
                wait_for_pids
                echo "    Summarizing $file with $GARBAGECAT"
                $JAVA $JAVA_OPTS -jar $GARBAGECAT $GARBAGECAT_OPTS $file -o $file.garbagecat-report &
                gc_pids+=($!)
                NUMBER_GC_LOGS=$((NUMBER_GC_LOGS+1))
            fi
        done
    fi
    echo
fi



# Finish server logs
if [ "$OPTIONS_SET" = "false" ] || [ "$SERVER" = "true" ]; then
    # wait for all SERVER yala pids
    for pid in ${server_pids[*]}; do
        wait $pid
    done

    # highlight of yalas
    echo -e "${YELLOW}====== Server log yala summaries ======${NC}"
    echo "====== Server log yala summaries ======" > $TARGET_DIR/server-log.yass-report
    echo "Number of server log files: $NUMBER_SERVER_LOGS" | tee -a $TARGET_DIR/server-log.yass-report
    echo | tee -a $TARGET_DIR/server-log.yass-report
    if [ $NUMBER_SERVER_LOGS -gt 0 ]; then
        for file in `find $TARGET_DIR -type f -iname \*.yala`; do
                echo -e "${YELLOW}## Yala highlights of $file ##${NC}"
                echo "## Yala highlights of $file ##" >> $TARGET_DIR/server-log.yass-report
                grep -R "*** First and last timestamped lines of" -A 2 $file | tee -a $TARGET_DIR/server-log.yass-report
                if [ -f $file-errors ]; then 
                    grep "known ERRORS found of " $file-errors | tee -a $TARGET_DIR/server-log.yass-report
                fi
        echo | tee -a $TARGET_DIR/server-log.yass-report
        done
    fi
fi 


# Finish thread dumps
if [ "$OPTIONS_SET" = "false" ] || [ "$THREAD" = "true" ]; then
    # wait for all THREAD yatda pids
    for pid in ${dump_pids[*]}; do
        wait $pid
    done

    # highlight of yatdas
    echo -e "${YELLOW}====== Thread dump yatda summaries ======${NC}"
    echo "====== Thread dump yatda summaries ======" > $TARGET_DIR/thread-dump.yass-report
    echo | tee -a $TARGET_DIR/thread-dump.yass-report
    if [ $NUMBER_THREAD_DUMPS -gt 0 ]; then

        MAX_NUMBER_THREADS=0
        MAX_NUMBER_REQUEST_THREADS=0
        MAX_NUMBER_REQUESTS=0
        MAX_AVG_NUMBER_THREADS=0
        MAX_AVG_NUMBER_REQUEST_THREADS=0
        MAX_AVG_NUMBER_REQUESTS=0

        for file in `find $TARGET_DIR -type f -iname \*.yatda`; do
            echo -e "${YELLOW}## Yatda summary of $file ##${NC}"
            echo "## Yatda summary of $file ##" >> $TARGET_DIR/thread-dump.yass-report
            sed -n -e '/Number of thread dumps:/,/Specific findings/ p' $file | grep -v "Specific findings" | tee -a $TARGET_DIR/thread-dump.yass-report
            sed -n -e '/Top lines of request threads/,/Most common from first/ p' $file | grep -v "Most common from first" | tee -a $TARGET_DIR/thread-dump.yass-report
            if [ -f $file-cpu ]; then 
                grep "Max " -A 1 $file-cpu | tee -a $TARGET_DIR/thread-dump.yass-report
            fi
            if [ -f $file-gc-cpu ]; then 
                grep "Max " -A 1 $file-gc-cpu | tee -a $TARGET_DIR/thread-dump.yass-report
            fi
            echo | tee -a $TARGET_DIR/thread-dump.yass-report

            NUMBER_THREADS=`grep "Total number of threads:" $file | sed -E 's/^Total number of threads:  ([0-9]+)/\1/g'`
            if [ "$NUMBER_THREADS" != "" ]; then
                if [ $NUMBER_THREADS -gt $MAX_NUMBER_THREADS ]; then
                    MAX_NUMBER_THREADS=$NUMBER_THREADS
                    MAX_NUMBER_THREADS_FILE=$file
                elif [ $NUMBER_THREADS -eq $MAX_NUMBER_THREADS ]; then
                    MAX_NUMBER_THREADS=$NUMBER_THREADS
                    MAX_NUMBER_THREADS_FILE="$file
$MAX_NUMBER_THREADS_FILE"
                fi
            fi

            NUMBER_REQUEST_THREADS=`grep "Total number of request threads:" $file | sed -E 's/Total number of request threads:  ([0-9]+)/\1/g'`
            if [ "$NUMBER_REQUEST_THREADS" != "" ]; then
                if [ $NUMBER_REQUEST_THREADS -gt $MAX_NUMBER_REQUEST_THREADS ]; then
                    MAX_NUMBER_REQUEST_THREADS=$NUMBER_REQUEST_THREADS
                    MAX_NUMBER_REQUEST_THREADS_FILE=$file
                elif [ $NUMBER_REQUEST_THREADS -eq $MAX_NUMBER_REQUEST_THREADS ]; then
                    MAX_NUMBER_REQUEST_THREADS=$NUMBER_REQUEST_THREADS
                    MAX_NUMBER_REQUEST_THREADS_FILE="$file
$MAX_NUMBER_REQUEST_THREADS_FILE"
                fi
            fi

            NUMBER_REQUESTS=`grep "Total number of in process requests:" $file | sed -E 's/Total number of in process requests:  ([0-9]+)/\1/g'`
            if [ "$NUMBER_REQUESTS" != "" ]; then
                if [ $NUMBER_REQUESTS -gt $MAX_NUMBER_REQUESTS ]; then
                    MAX_NUMBER_REQUESTS=$NUMBER_REQUESTS
                    MAX_NUMBER_REQUESTS_FILE=$file
                elif [ $NUMBER_REQUESTS -eq $MAX_NUMBER_REQUESTS ]; then
                    MAX_NUMBER_REQUESTS=$NUMBER_REQUESTS
                    MAX_NUMBER_REQUESTS_FILE="$file
$MAX_NUMBER_REQUESTS_FILE"
                fi
            fi

            AVG_NUMBER_THREADS=`grep "Average number of threads per thread dump:" $file | sed -E 's/Average number of threads per thread dump:  ([0-9]+)/\1/g'`
            if [ "$AVG_NUMBER_THREADS" != "" ]; then
                if [ $AVG_NUMBER_THREADS -gt $MAX_AVG_NUMBER_THREADS ]; then
                    MAX_AVG_NUMBER_THREADS=$AVG_NUMBER_THREADS
                    MAX_AVG_NUMBER_THREADS_FILE=$file
                elif [ $AVG_NUMBER_THREADS -eq $MAX_AVG_NUMBER_THREADS ]; then
                    MAX_AVG_NUMBER_THREADS=$AVG_NUMBER_THREADS
                    MAX_AVG_NUMBER_THREADS_FILE="$file
$MAX_AVG_NUMBER_THREADS_FILE"
                fi
            fi

            AVG_NUMBER_REQUEST_THREADS=`grep "Average number of request threads per thread dump:" $file | sed -E 's/Average number of request threads per thread dump:  ([0-9]+)/\1/g'`
            if [ "$AVG_NUMBER_REQUEST_THREADS" != "" ]; then
                if [ $AVG_NUMBER_REQUEST_THREADS -gt $MAX_AVG_NUMBER_REQUEST_THREADS ]; then
                    MAX_AVG_NUMBER_REQUEST_THREADS=$AVG_NUMBER_REQUEST_THREADS
                    MAX_AVG_NUMBER_REQUEST_THREADS_FILE=$file
                elif [ $AVG_NUMBER_REQUEST_THREADS -eq $MAX_AVG_NUMBER_REQUEST_THREADS ]; then
                    MAX_AVG_NUMBER_REQUEST_THREADS=$AVG_NUMBER_REQUEST_THREADS
                    MAX_AVG_NUMBER_REQUEST_THREADS_FILE="$file
$MAX_AVG_NUMBER_REQUEST_THREADS_FILE"
                fi
            fi

            AVG_NUMBER_REQUESTS=`grep "Average number of in process requests per thread dump:" $file | sed -E 's/Average number of in process requests per thread dump:  ([0-9]+)/\1/g'`
            if [ "$AVG_NUMBER_REQUESTS" != "" ]; then
                if [ $AVG_NUMBER_REQUESTS -gt $MAX_AVG_NUMBER_REQUESTS ]; then
                    MAX_AVG_NUMBER_REQUESTS=$AVG_NUMBER_REQUESTS
                    MAX_AVG_NUMBER_REQUESTS_FILE=$file
                elif [ $AVG_NUMBER_REQUESTS -eq $MAX_AVG_NUMBER_REQUESTS ]; then
                    MAX_AVG_NUMBER_REQUESTS=$AVG_NUMBER_REQUESTS
                    MAX_AVG_NUMBER_REQUESTS_FILE="$file
$MAX_AVG_NUMBER_REQUESTS_FILE"
                fi
            fi
        done
    fi

    echo -e "${YELLOW}====== Final thread dump summary ======${NC}"
    echo "====== Final thread dump summary ======" >> $TARGET_DIR/thread-dump.yass-report
    {
        echo "Number of thread dump files: $NUMBER_THREAD_DUMPS"
        echo
        if [ $NUMBER_THREAD_DUMPS -gt 1 ]; then
            echo "* Max number of threads is $MAX_NUMBER_THREADS in files:"
            echo "$MAX_NUMBER_THREADS_FILE"
            echo
            echo "* Max number of request threads is $MAX_NUMBER_REQUEST_THREADS in files:"
            echo "$MAX_NUMBER_REQUEST_THREADS_FILE"
            echo
            echo "* Max number of processing requests is $MAX_NUMBER_REQUESTS in files:"
            echo "$MAX_NUMBER_REQUESTS_FILE"
            echo
            echo "* Max average number of threads is $MAX_AVG_NUMBER_THREADS in files:"
            echo "$MAX_AVG_NUMBER_THREADS_FILE"
            echo
            echo "* Max average number of request threads is $MAX_AVG_NUMBER_REQUEST_THREADS in files:"
            echo "$MAX_AVG_NUMBER_REQUEST_THREADS_FILE"
            echo
            echo "* Max average number of processing requests is $MAX_AVG_NUMBER_REQUESTS in files:"
            echo "$MAX_AVG_NUMBER_REQUESTS_FILE"
            echo
        fi
    }  | tee -a $TARGET_DIR/thread-dump.yass-report
    echo -e "${YELLOW}====== Completed thread dump summary ======${NC}"
    echo "====== Completed thread dump summary ======" >> $TARGET_DIR/thread-dump.yass-report
fi


# Summarize access logs
if [ "$OPTIONS_SET" = "false" ] || [ "$ACCESS" = "true" ]; then
    echo -e "${GREEN}## Finding and summarizing access files in $TARGET_DIR  ##${NC}"
    echo
    #peaks across all access logs
    ANY_RESPONSE_TIMES=0
    NUMBER_ACCESS_LOGS=0
    PEAK_COMPLETED=0
    PEAK_COMPLETED_DATE_FILE=0
    PEAK_LONG=0
    PEAK_LONG_DATE_FILE=0
    PEAK_LONGEST=0
    PEAK_LONGEST_DATE_FILE=0
    PEAK_NUM4XXs=0
    PEAK_NUM4XXs_DATE_FILE=0
    PEAK_NUM5XXs=0
    PEAK_NUM5XXs_DATE_FILE=0
    for file in `find $TARGET_DIR -type f -iname \*access\*log\*`; do
        if [[ ${file} != *".yass"* ]]; then
            echo "    Summarizing $file" | tee $file-summary.yass-access

            # completed - count of completed requests
            # long - count of long requests (>10 sec)
            TOTAL_COMPLETED=0
            TOTAL_NUM200s=0
            TOTAL_NUM304s=0
            TOTAL_NUM3XXs=0
            TOTAL_NUM4XXs=0
            TOTAL_NUM5XXs=0
            HIGHEST_COMPLETED=0
            HIGHEST_COMPLETED_DATE=0
            TOTAL_LONG=0
            HIGHEST_LONG=0
            HIGHEST_LONG_DATE=0
            HIGHEST_NUM4XXs=0
            HIGHEST_NUM4XXs_DATE=0
            HIGHEST_NUM5XXs=0
            HIGHEST_NUM5XXs_DATE=0

            # highest longest request in this access log
            HIGHEST_LONGEST=0

            tmp=$file.yass-access-tmp

            RESPONSE_TIMES=`grep -m 1 "[0-9]\.[0-9][0-9][0-9]$" $file | wc -l`
            if [ $RESPONSE_TIMES -eq "0" ]; then
                echo "        Response times not found in $file.  Use %T as last field of access-log pattern for response time summaries."
            fi

            if [ $RESPONSE_TIMES -ne "0" ]; then
                ANY_RESPONSE_TIMES=$RESPONSE_TIMES
                printf "%17s | %10s | %20s | %20s | %20s | %20s | %20s | %20s\n" "DATE" "COMPLETED" "LONGER(>10s)" "200s" "304s" "OTHER 3XXs" "4XXs" "5XXs" >> $file-summary.yass-access
                echo "========================================================================================================================================================================" >> $file-summary.yass-access
            else
                printf "%17s | %10s | %20s | %20s | %20s | %20s | %20s\n" "DATE" "COMPLETED" "200s" "304s" "OTHER 3XXs" "4XXs" "5XXs" >> $file-summary.yass-access
                echo "=================================================================================================================================================" >> $file-summary.yass-access
            fi

            #DATES=`cat $file | awk '{ print $4 }' | sed 's/\[//'| sed 's/:[0-9][0-9]$//' | uniq`;
            # fleshed out sed to find and support date in any column
            DATES=`cat $file | sed -E 's/.*\[([0-9][0-9]\/[A-Z][a-z][a-z]\/20[0-9][0-9]:[0-9][0-9]:[0-9][0-9]).*/\1/g' | uniq`;
            for x in $DATES; do
                # longest this minute
                LONGEST=0

                grep "$x" $file > $tmp
                COMPLETED=`cat $tmp | wc -l`
                TOTAL_COMPLETED=$((TOTAL_COMPLETED + COMPLETED))
                if [ $COMPLETED -gt $HIGHEST_COMPLETED ]; then
                    HIGHEST_COMPLETED=$COMPLETED
                    HIGHEST_COMPLETED_DATE=$x
                    if [ $COMPLETED -gt $PEAK_COMPLETED ]; then
                        PEAK_COMPLETED=$COMPLETED
                        PEAK_COMPLETED_DATE_FILE="$x in $file"
                    fi
                fi


                NUM200s=`grep -E "HTTP/[0-9]\.[0-9]\"? 200 " $tmp | wc -l`
                TOTAL_NUM200s=$((TOTAL_NUM200s + NUM200s))

                NUM304s=`grep -E "HTTP/[0-9]\.[0-9]\"? 304 " $tmp | wc -l`
                TOTAL_NUM304s=$((TOTAL_NUM304s + NUM304s))

                NUM3XXs=`grep -E "HTTP/[0-9]\.[0-9]\"? 3[0-9]([0-3]|[5-9]) " $tmp | wc -l`
                TOTAL_NUM3XXs=$((TOTAL_NUM3XXs + NUM3XXs))

                NUM4XXs=`grep -E "HTTP/[0-9]\.[0-9]\"? 4[0-9][0-9] " $tmp | wc -l`
                TOTAL_NUM4XXs=$((TOTAL_NUM4XXs + NUM4XXs))
                if [ $NUM4XXs -gt $HIGHEST_NUM4XXs ]; then
                    HIGHEST_NUM4XXs=$NUM4XXs
                    HIGHEST_NUM4XXs_DATE=$x
                    if [ $NUM4XXs -gt $PEAK_NUM4XXs ]; then
                        PEAK_NUM4XXs=$NUM4XXs
                        PEAK_NUM4XXs_DATE_FILE="$x in $file"
                    fi
                fi

                NUM5XXs=`grep -E "HTTP/[0-9]\.[0-9]\"? 5[0-9][0-9] " $tmp | wc -l`
                TOTAL_NUM5XXs=$((TOTAL_NUM5XXs + NUM5XXs))
                if [ $NUM5XXs -gt $HIGHEST_NUM5XXs ]; then
                    HIGHEST_NUM5XXs=$NUM5XXs
                    HIGHEST_NUM5XXs_DATE=$x
                    if [ $NUM5XXs -gt $PEAK_NUM5XXs ]; then
                        PEAK_NUM5XXs=$NUM5XXs
                        PEAK_NUM5XXs_DATE_FILE="$x in $file"
                    fi
                fi


                PERCENT_NUM200s=`printf %.2f $((10**4 * $NUM200s / $COMPLETED ))e-2`
                PERCENT_NUM304s=`printf %.2f $((10**4 * $NUM304s / $COMPLETED ))e-2`
                PERCENT_NUM3XXs=`printf %.2f $((10**4 * $NUM3XXs / $COMPLETED ))e-2`
                PERCENT_NUM4XXs=`printf %.2f $((10**4 * $NUM4XXs / $COMPLETED ))e-2`
                PERCENT_NUM5XXs=`printf %.2f $((10**4 * $NUM5XXs / $COMPLETED ))e-2`
                if [ $RESPONSE_TIMES -ne "0" ]; then
                    LONG=`grep -v " [0-9]\.[0-9][0-9][0-9]$" $tmp | wc -l`
                    PERCENT_LONG=`printf %.2f $((10**4 * $LONG / $COMPLETED ))e-2`
                    TOTAL_LONG=$((TOTAL_LONG + LONG))
                    if [ $LONG -gt $HIGHEST_LONG ]; then
                        HIGHEST_LONG=$LONG
                        HIGHEST_LONG_DATE=$x
                        if [ $LONG -gt $PEAK_LONG ]; then
                            PEAK_LONG=$LONG
                            PEAK_LONG_DATE_FILE="$x in $file"
                        fi
                    fi

                    printf "%s | %10s | %10s - %6s%% | %10s - %6s%% | %10s - %6s%% | %10s - %6s%% | %10s - %6s%% | %10s - %6s%%\n" $x $COMPLETED $LONG $PERCENT_LONG $NUM200s $PERCENT_NUM200s $NUM304s $PERCENT_NUM304s $NUM3XXs $PERCENT_NUM3XXs $NUM4XXs $PERCENT_NUM4XXs $NUM5XXs $PERCENT_NUM5XXs >> $file-summary.yass-access
                else
                    printf "%s | %10s | %10s - %6s%% | %10s - %6s%% | %10s - %6s%% | %10s - %6s%% | %10s - %6s%%\n" $x $COMPLETED $NUM200s $PERCENT_NUM200s $NUM304s $PERCENT_NUM304s $NUM3XXs $PERCENT_NUM3XXs $NUM4XXs $PERCENT_NUM4XXs $NUM5XXs $PERCENT_NUM5XXs >> $file-summary.yass-access
                fi
            done

            echo >> $file-summary.yass-access
            echo -e "${YELLOW}## Access log summary of $file ##${NC}"
            echo "## Access log summary of $file ##" >> $TARGET_DIR/access-log.yass-report
            {
                echo "* Number of requests: $TOTAL_COMPLETED"
                if [ $TOTAL_COMPLETED -gt 0 ]; then
                    echo "* Number of 200s: $TOTAL_NUM200s - `printf %.2f $((10**4 * $TOTAL_NUM200s / $TOTAL_COMPLETED ))e-2`%"
                    echo "* Number of 304s: $TOTAL_NUM304s - `printf %.2f $((10**4 * $TOTAL_NUM304s / $TOTAL_COMPLETED ))e-2`%"
                    echo "* Number of 4XXs: $TOTAL_NUM3XXs - `printf %.2f $((10**4 * $TOTAL_NUM3XXs / $TOTAL_COMPLETED ))e-2`%"
                    echo "* Number of 4XXs: $TOTAL_NUM4XXs - `printf %.2f $((10**4 * $TOTAL_NUM4XXs / $TOTAL_COMPLETED ))e-2`%"
                    echo "* Number of 5XXs: $TOTAL_NUM5XXs - `printf %.2f $((10**4 * $TOTAL_NUM5XXs / $TOTAL_COMPLETED ))e-2`%"
                    echo "* Highest completed request count is $HIGHEST_COMPLETED at $HIGHEST_COMPLETED_DATE"
                    if [ $RESPONSE_TIMES -ne "0" ]; then
                        echo "* Highest long response count is $HIGHEST_LONG at $HIGHEST_LONG_DATE"
                    fi
                    echo "* Highest number of 4XX responses is $HIGHEST_NUM4XXs at $HIGHEST_NUM4XXs_DATE"
                    echo "* Highest number of 5XX responses is $HIGHEST_NUM5XXs at $HIGHEST_NUM5XXs_DATE"
                fi
                echo
            } | tee -a $TARGET_DIR/access-log.yass-report
            rm -rf $tmp
            NUMBER_ACCESS_LOGS=$((NUMBER_ACCESS_LOGS+1))
        fi
    done


    echo -e "${YELLOW}====== Final access log summary ======${NC}"
    echo "====== Final access log summary ======" >> $TARGET_DIR/access-log.yass-report
    {
        echo "Number of access log files: $NUMBER_ACCESS_LOGS" | tee -a $TARGET_DIR/access-log.yass-report
        if [ $NUMBER_ACCESS_LOGS -gt 0 ]; then
            echo "* Peak completed request count is $PEAK_COMPLETED at $PEAK_COMPLETED_DATE_FILE"
            if [ $ANY_RESPONSE_TIMES -ne "0" ]; then
                echo "* Peak long response count is $PEAK_LONG at $PEAK_LONG_DATE_FILE"
            fi
            echo "* Peak number of 4XX responses is $PEAK_NUM4XXs at $PEAK_NUM4XXs_DATE_FILE"
            echo "* Peak number of 5XX responses is $PEAK_NUM5XXs at $PEAK_NUM5XXs_DATE_FILE"
        fi
    } | tee -a $TARGET_DIR/access-log.yass-report
    echo -e "${YELLOW}====== Completed access log summary ======${NC}"
    echo "====== Completed access log summary ======" >> $TARGET_DIR/access-log.yass-report
fi


# Finish GC logs
if [ "$OPTIONS_SET" = "false" ] || [ "$GC" = "true" ]; then
    # wait for all GC garbagecat pids
    echo -e "${GREEN}Finishing garbagecats${NC}"
    for pid in ${gc_pids[*]}; do
        wait $pid
    done
    echo -e "${GREEN}Finished garbagecats${NC}"

    # highlight of GC logs
    echo -e "${YELLOW}====== Garbagecat GC log summaries ======${NC}"
    echo "====== Garbagecat GC log summaries ======" > $TARGET_DIR/gc-log.yass-report
    echo | tee -a $TARGET_DIR/gc-log.yass-report

    if [ $NUMBER_GC_LOGS -gt 0 ]; then
        LOWEST_THROUGHPUT=100
        MAX_PAUSE_SECONDS=0
        MAX_PAUSE_MILLIS=0

        for file in `find $TARGET_DIR -type f -iname \*.garbagecat-report`; do
            echo -e "${YELLOW}## Garbagecat GC log summary of $file ##${NC}"
            echo "## Garbagecat GC log summary of $file ##" >> $TARGET_DIR/gc-log.yass-report
            sed -n -E -e '/(JVM|SUMMARY):/,/ANALYSIS:/ p' $file | grep -v "ANALYSIS:" | tee -a $TARGET_DIR/gc-log.yass-report
            echo | tee -a $TARGET_DIR/gc-log.yass-report

            # Track lowest throughput to report
            THROUGHPUT=`grep "GC Throughput" $file | sed -E 's/^[^0-9]+([0-9]+)[^0-9]+/\1/g'`
            if [ "$THROUGHPUT" != "" ]; then
                if [ $THROUGHPUT -lt $LOWEST_THROUGHPUT ]; then
                    LOWEST_THROUGHPUT=$THROUGHPUT
                    LOWEST_THROUGHPUT_FILE=$file
                elif [ $THROUGHPUT -eq $LOWEST_THROUGHPUT ]; then
                    LOWEST_THROUGHPUT_FILE="$LOWEST_THROUGHPUT_FILE
$file"
                fi

                # Track max pause to report
                PAUSE_SECONDS=`grep "GC Pause Max" $file | sed -E 's/^GC Pause Max: ([0-9]+).*/\1/g'`
                PAUSE_MILLIS=`grep "GC Pause Max" $file | sed -E 's/^GC Pause Max: [0-9]+\.([0-9]+).*/\1/g'`

                if [ $PAUSE_SECONDS -gt $MAX_PAUSE_SECONDS ]; then
                    MAX_PAUSE_SECONDS=$PAUSE_SECONDS
                    MAX_PAUSE_MILLIS=$PAUSE_MILLIS
                    MAX_PAUSE_FILE=$file
                elif [ $PAUSE_SECONDS -eq $MAX_PAUSE_SECONDS ]  && [ $PAUSE_MILLIS -gt $MAX_PAUSE_MILLIS ]; then
                    MAX_PAUSE_MILLIS=$PAUSE_MILLIS
                    MAX_PAUSE_FILE=$file
                fi
            fi
        done
    fi


    echo -e "${YELLOW}====== Final GC summary ======${NC}"
    echo "====== Final GC summary ======" >> $TARGET_DIR/gc-log.yass-report
    # Output low & max
    {
        echo "Number of GC log files: $NUMBER_GC_LOGS" | tee -a $TARGET_DIR/gc-log.yass-report
        if [ $NUMBER_GC_LOGS -gt 1 ]; then
            echo "* Lowest throughput is $LOWEST_THROUGHPUT in files:"
            echo "$LOWEST_THROUGHPUT_FILE"
            echo
            echo "* Max pause is $MAX_PAUSE_SECONDS.$MAX_PAUSE_MILLIS in $MAX_PAUSE_FILE"
        fi
    }  | tee -a $TARGET_DIR/gc-log.yass-report
    echo -e "${YELLOW}====== Completed GC summary ======${NC}"
    echo "====== Completed GC summary ======" >> $TARGET_DIR/gc-log.yass-report
fi 
