#! /bin/bash

# Parse a support-core plugin -style txt file as specification for jenkins plugins to be installed
# in the reference directory, so user can define a derived Docker image with just :
#
# FROM jenkins
# COPY plugins.txt /plugins.txt
# RUN /usr/local/bin/plugins.sh /plugins.txt
#
# Note: Plugins already installed are skipped
#

set -e

if [ -z "$1" ]
then
    echo "
USAGE:
  Parse a support-core plugin -style txt file as specification for jenkins plugins to be installed
  in the reference directory, so user can define a derived Docker image with just :

  FROM jenkins
  COPY plugins.txt /plugins.txt
  RUN /usr/local/bin/plugins.sh /plugins.txt

  Note: Plugins already installed are skipped

"
    exit 1
else
    JENKINS_INPUT_JOB_LIST=$1
    if [ ! -f $JENKINS_INPUT_JOB_LIST ]
    then
        echo "ERROR File not found: $JENKINS_INPUT_JOB_LIST"
        exit 1
    fi
fi

# the war includes a # of plugins, to make the build efficient filter out
# the plugins so we dont install 2x - there about 17!
if [ -d $JENKINS_HOME ]
then
    TEMP_ALREADY_INSTALLED=$JENKINS_HOME/preinstalled.plugins.$$.txt
else
    echo "ERROR $JENKINS_HOME not found"
    exit 1
fi

JENKINS_PLUGINS_DIR=/var/jenkins_home/plugins
if [ -d $JENKINS_PLUGINS_DIR ]
then
    echo "Analyzing: $JENKINS_PLUGINS_DIR"
    for i in `ls -pd1 $JENKINS_PLUGINS_DIR/*|egrep '\/$'`
    do
        JENKINS_PLUGIN=`basename $i`
        JENKINS_PLUGIN_VER=`egrep -i Plugin-Version "$i/META-INF/MANIFEST.MF"|cut -d\: -f2|sed 's/ //'`
        echo "$JENKINS_PLUGIN:$JENKINS_PLUGIN_VER"
    done > $TEMP_ALREADY_INSTALLED
else
    JENKINS_WAR=/usr/share/jenkins/jenkins.war
    if [ -f $JENKINS_WAR ]
    then
        echo "Analyzing war: $JENKINS_WAR"
        TEMP_PLUGIN_DIR=/tmp/plugintemp.$$
        for i in `jar tf $JENKINS_WAR|egrep 'plugins'|egrep -v '\/$'|sort`
        do
            rm -fr $TEMP_PLUGIN_DIR
            mkdir -p $TEMP_PLUGIN_DIR
            PLUGIN=`basename $i|cut -f1 -d'.'`
            (cd $TEMP_PLUGIN_DIR;jar xf $JENKINS_WAR "$i";jar xvf $TEMP_PLUGIN_DIR/$i META-INF/MANIFEST.MF >/dev/null 2>&1)
            VER=`egrep -i Plugin-Version "$TEMP_PLUGIN_DIR/META-INF/MANIFEST.MF"|cut -d\: -f2|sed 's/ //'`
            echo "$PLUGIN:$VER"
        done > $TEMP_ALREADY_INSTALLED
        rm -fr $TEMP_PLUGIN_DIR
    else
        rm -f $TEMP_ALREADY_INSTALLED
        echo "ERROR file not found: $JENKINS_WAR"
        exit 1
    fi
fi

REF=/usr/share/jenkins/ref/plugins
mkdir -p $REF
COUNT_PLUGINS_INSTALLED=0

JENKINS_MIRROR="${JENKINS_MIRROR:-$JENKINS_UC/download}"
if ! [ -z "$JENKINS_UC_DOWNLOAD" ]; then
    echo "JENKINS_UC_DOWNLOAD envvar is deprecated, use JENKINS_MIRROR"
    JENKINS_MIRROR=$JENKINS_UC_DOWNLOAD
fi

while read spec || [ -n "$spec" ]; do

    plugin=(${spec//:/ });
    [[ ${plugin[0]} =~ ^# ]] && continue
    [[ ${plugin[0]} =~ ^\s*$ ]] && continue
    [[ -z ${plugin[1]} ]] && plugin[1]="latest"

    if ! grep -q "${plugin[0]}:${plugin[1]}" $TEMP_ALREADY_INSTALLED
    then
        echo "Downloading ${plugin[0]}:${plugin[1]}"
        curl --retry 3 --retry-delay 5 -sSL -f ${JENKINS_MIRROR}/plugins/${plugin[0]}/${plugin[1]}/${plugin[0]}.hpi -o $REF/${plugin[0]}.jpi
        unzip -qqt $REF/${plugin[0]}.jpi
        COUNT_PLUGINS_INSTALLED=`expr $COUNT_PLUGINS_INSTALLED + 1`
    else
        echo "  ... skipping already installed:  ${plugin[0]}:${plugin[1]}"
    fi
done  < $JENKINS_INPUT_JOB_LIST

echo "---------------------------------------------------"
if [ $COUNT_PLUGINS_INSTALLED -gt 0 ]
then
    echo "INFO: Successfully installed $COUNT_PLUGINS_INSTALLED plugins."

    if [ -d $JENKINS_PLUGINS_DIR ]
    then
        echo "INFO: Please restart the container for changes to take effect!"
    fi
else
    echo "INFO: No changes, all plugins previously installed."

fi
echo "---------------------------------------------------"

#cleanup
rm $TEMP_ALREADY_INSTALLED
exit 0
