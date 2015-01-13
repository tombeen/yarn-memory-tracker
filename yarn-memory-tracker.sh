#!/bin/bash

YARN_ENV=$HADOOP_HOME/etc/hadoop/yarn-env.sh
CONTAINER_PATTERN="container_*"
MEM_GREP_PATTERN="INFO org.apache.hadoop.yarn.server.nodemanager.containermanager.monitor.ContainersMonitorImpl: Memory usage of ProcessTree"

# log example 
# yarn-wdong-nodemanager-klose1.log:2015-01-05 04:00:21,921 INFO org.apache.hadoop.yarn.server.nodemanager.containermanager.monitor.ContainersMonitorImpl: Memory usage of ProcessTree 27966 for container-id container_1420401494322_0001_01_000001: 78.1 MB of 2 GB physical memory used; 1.6 GB of 4.2 GB virtual memory used

# we want to use awk convert this to
# klose1 2015-01-05 04:00:21 TS 27966 container_1420401494322_0001_01_000001 78.1 MB 2 GB 1.6 GB 4.2 GB
# where TS is equivalent timestamp
# $1: yarn-wdong-nodemanager-klose1.log:2015-01-05
# $2: 04:00:21,921
# $9: 27966
# $12: container_1420401494322_0001_01_000001
# $13: 78.1
# $14: MB
# $16: 2
# $17: GB
# $21: 1.6
# $22: GB
# $24: 4.2
# $25: GB

# output format is
# washtenaw 2015-01-06 14:56:40 1420574200 16669 container_1420574192658_0001_01_000001 0.274023 9 8.9 18.9

# extract node from $1: 

AWK_PROG=' {
    split($1, arr, "[:]");
    node = arr[1];
    date = arr[2];
    split(node, arr, "[-.]");
    node=arr[4];
    split($2, arr, ",");
    time = arr[1];
    date_time=date  " "  time;
    gsub(/[:-]/, " ", date_time);
    ts = mktime(date_time);
    pid=$9;
    split($12, arr, ":");
    container = arr[1];
    p_use = $13;
    bad=0;
    if ($14 == "MB") {
        p_use /= 1024.0;
    }
    else if ($14 != "GB") {
        bad=1;
    }
    p_cap = $16;
    if ($17 == "MB") {
        p_cap /= 1024.0;
    }
    else if ($17 != "GB") {
        bad=1;
    }
    v_use = $21;
    if ($22 == "MB") {
        v_use /= 1024.0;
    }
    else if ($22 != "GB") {
        bad=1;
    }
    v_cap = $24;
    if ($25 == "MB") {
        v_cap /= 1024.0;
    }
    else if ($25 != "GB") {
        bad=1;
    }
    if (bad != 0) {
        print "Found memory unit of neither MB or GB, do not know what to do." > "/dev/stderr";
        print $0 > "/dev/stderr";
        exit;
    }
    else {
        print node, date, time, ts, pid, container, p_use, p_cap, v_use, v_cap; 
    }
} '


APP=$1

if [ -z "$APP" ]
then
    echo "usage:    $0 app-id"
    exit 1
fi

if [ ! -f $YARN_ENV ]
then
    echo "yarn-env.sh not found under \$HADOOP_HOME/etc/hadoop/yarn-env.sh"
    echo "\$HADOOP_HOME=$HADOOP_HOME"
    exit 1
fi

. $YARN_ENV

LOG_DIR=$YARN_LOG_DIR/userlogs/$APP

if [ ! -d $LOG_DIR ]
then
    echo "Log for app $APP not found under $LOG_DIR"
    exit 1
fi

NC=`find $LOG_DIR/ -type d -name "$CONTAINER_PATTERN" | wc -l`

MEMLOG=`mktemp`
SUM=`mktemp`

grep "$MEM_GREP_PATTERN"  $YARN_LOG_DIR/*.log | sed 's/0B of/0 GB of/g' | awk "$AWK_PROG" > $MEMLOG

echo $NC containers found for app $APP
NC=1
find $LOG_DIR/ -type d -name "$CONTAINER_PATTERN" | sort | while read C
do
    CID=`basename $C`
    printf "%s: " $CID
    NC=$((NC+1))
    grep $CID $MEMLOG | cut -f 7,8 -d ' ' | awk 'BEGIN{m=0;c=0;}{if ($1 > m) {m = $1;} c=$2;}END{print $1, $2}' | while read U C
    do
        echo $U of $C GB
        echo $U $C >> $SUM
    done
done

awk 'BEGIN{u=0;c=0;}{u+=$1;c+=$2;}END{print u, c;}' $SUM | while read U C
do
    echo Total: $U of $C GB.
done

rm $MEMLOG
rm $SUM
