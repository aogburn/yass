# yass
Yass is just 'Yet Another Script' Script.  It is a main script to call and more quickly decompress and analyze a directory of various JBoss data files including access logs, GC logs (via garbagecat), server logs(via yala), and thread dumps (via yatda).

# installation
* To install, run the following in a directory where you want to keep the script and known error file references:
```
wget https://raw.githubusercontent.com/aogburn/yass/main/yass.sh
chmod 755 yass.sh
```
* Install the atool package to provide the aunpack command used to easily uncompress various file types.  And also install other compression libraries:
```
yum install atool unzip gzip bzip2 tar p7zip ncompress
```
* Create a $HOME/.yass/config file like the example.config and specify variables below to indicate the locations of these tools:
```
GARBAGECAT=/path/to/garbagecat.jar
YALA_SH=/path/to/yala.sh
YATDA_SH=/path/to/yatda.sh
```

# updating 

When run, yass will look for a new version to use and update itself with a simple wget if so. This update check can be omitted by using the option `-u, --updateMode` with either the value `never` (no update check is being performed) or `ask` (the user is asked to update if a new version is found). The script may be updated over time with new helpful checks, stats, or known issue searches.

# usage

* By default, yass will check the directory it is run in and all underlying files and subdirectories.  It will first extract any compressed files (and then any compressed files that were nested in those).  It then checks for file names matching "*server*log*" and runs the specified yala.sh on each.  It checks for thread dump files (a file containing the indicative "Full thread dump" string) and runs yatda.sh on each.  It checks for file names match "*gc*log*" and runs the specified garbagecat on each.  Once these are done, it summarizes portions of the yala outputs server-log-summary.yass, yatda portions to thread-dump-summary.yass along with indications of which files have peak thread stats, and garbagecat report portions to gc-log-summary.yass along with indications of which files have highest pause times and lowest throughput.  To run on the current directory:
```
 ./yass.sh
```
Or you may specify the directory to run against:
```
 ./yass.sh /path/to/target/directory
```
* Options include all of the flags mentioned below.  All analysis options would be used by default.  If you specify any option, then analysis will only be done for the explictly set flags (
```
 -a, --accessLog         recursively look for and summarize access logs
 -g, --gcLog             recursively look for and summarize GC logs via a specified garbagecat
 -s, --serverLog         recursively look for and sumarize server logs via a specified yala.sh
 -t, --threadDump        recursively look for and summarize thread dumps via a specified yatda.sh
 -u, --updateMode        the update mode to use, one of [${VALID_UPDATE_MODES[*]}], default: force
 -x, --extract           recursively look for and extract compressed files in the directory
 -h, --help              show this help
```
