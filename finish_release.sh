#!/bin/bash

##### TO EDIT #####

asf_username="jake"

# Same as for .prepare_release.sh
mail_dir="/home/jake/Documents/Mail/"
debian_package_dir="/home/jake/Tmp/"

# The directory for reprepro
reprepro_dir="/var/packages"
artifacts_svn_dir="/home/jake/workspace/cassandra-dist-svn"

###################

asf_git_repo="http://git-wip-us.apache.org/repos/asf"
apache_host="people.apache.org"

# Reset getopts in case it has been used previously in the shell.
OPTIND=1

# Initialize our own variables:
verbose=0
fake_mode=0

show_help()
{
    local name=`basename $0`
    echo "$name [options] <release_version> <staging_number>"
    echo ""
    echo "where [options] are:"
    echo "  -h: print this help"
    echo "  -v: verbose mode (show everything that is going on)"
    echo "  -f: fake mode, print any output but don't do anything (for debugging)"
    echo ""
    echo "Example: $name 2.0.3 1024"
}

while getopts ":hvf" opt; do
    case "$opt" in
    h)
        show_help
        exit 0
        ;;
    v)  verbose=1
        ;;
    f)  fake_mode=1
        ;;
    \?)
        echo "Invalid option: -$OPTARG" >&2
        show_help
        exit 1
        ;;
    esac
done

shift $(($OPTIND-1))

release=$1
staging_number=$2
deb_release=${release/-/\~}

if [ -z "$release" ]
then
    echo "Missing argument <release_version>"
    show_help
    exit 1
fi
if [ -z "$staging_number" ]
then
    echo "Missing argument <staging_number>"
    show_help
    exit 1
fi

if [ "$#" -gt 2 ]
then
    shift
    echo "Too many arguments. Don't know what to do with '$@'"
    show_help
    exit 1
fi

# Somewhat lame way to check we're in a git repo but that will do
git log -1 &> /dev/null
if [ $? -ne 0 ]
then
    echo "The current directory does not appear to be a git repository."
    echo "You must run this from the Cassandra git source repository."
    exit 1
fi

if [ "$release" == "$deb_release" ]
then
    echo "Publishing release $release using staging number $staging_number"
else
    echo "Publishing release $release (debian uses $deb_release) using staging number $staging_number"
fi

# "Saves" stdout to other descriptor since we might redirect them below
exec 3>&1 4>&2

if [ $verbose -eq 0 ]
then
    # Not verbose, redirect all ouptut to a logfile 
    logfile="release-${release}.log"
    [ ! -e "$logfile" ] || rm $logfile
    touch $logfile
    exec > $logfile
    exec 2> $logfile
fi

execute()
{
    local cmd=$1

    echo ">> $cmd"
    [ $fake_mode -eq 1 ] || $cmd
    if [ $? -ne 0 ]
    then
        echo "Error running $cmd" 1>&3 2>&4
        exit $?
    fi
}

idx=`expr index "$release" -`
if [ $idx -eq 0 ]
then
    release_short=${release}
else
    release_short=${release:0:$((idx-1))}
fi
i

echo "Deploying artifacts ..." 1>&3 2>&4
start_dir=$PWD
cd $artifacts_svn_dir
mkdir $release_short
cd $release_short
for type in bin src; do
    for part in gz gz.md5 gz.sha1 gz.asc gz.asc.md5 gz.asc.sha1; do
        echo "Downloading apache-cassandra-${release}-$type.tar.$part..." 1>&3 2>&4
        curl -O https://repository.apache.org/content/repositories/orgapachecassandra-${staging_number}/org/apache/cassandra/apache-cassandra/${release}/apache-cassandra-${release}-$type.tar.$part
    done
done

cd $start_dir

echo "Tagging release ..." 1>&3 2>&4
execute "git checkout $release-tentative"

# Ugly but somehow 'execute "git tag -a cassandra-$release -m 'Apache Cassandra $release release' "' doesn't work
echo "Apache Cassandra $release release" > "_tmp_msg_"
execute "git tag -a cassandra-$release -F _tmp_msg_"
rm _tmp_msg_
execute "git push apache refs/tags/cassandra-$release"
execute "git tag -d $release-tentative"
execute "git push apache :refs/tags/$release-tentative"

echo "Deploying debian packages ..." 1>&3 2>&4

current_dir=`pwd`

debian_series="${release_short:0:1}${release_short:2:1}x"

execute "cd $reprepro_dir"
execute "sudo reprepro includedeb $debian_series $debian_package_dir/cassandra_${release}_debian/cassandra_${deb_release}_all.deb"
execute "sudo reprepro includedsc $debian_series $debian_package_dir/cassandra_${release}_debian/cassandra_${deb_release}.dsc"
execute "cp -r dists/$debian_series ${artifacts_svn_dir}/debian/dists"
execute "cp pool/main/c/cassandra/cassandra_${deb_release}_all.deb ${artifacts_svn_dir}/debian/pool/main/c/cassandra"
execute "cp pool/main/c/cassandra/cassandra_${deb_release}.diff.gz ${artifacts_svn_dir}/debian/pool/main/c/cassandra"
execute "cp pool/main/c/cassandra/cassandra_${deb_release}.dsc ${artifacts_svn_dir}/debian/pool/main/c/cassandra"

if [ "$release_short" \> "2.1" ]
then
    execute "sudo reprepro includedeb $debian_series $debian_package_dir/cassandra_${release}_debian/cassandra-tools_${deb_release}_all.deb"
    execute "cp pool/main/c/cassandra/cassandra-tools_${deb_release}_all.deb ${artifacts_svn_dir}/debian/pool/main/c/cassandra"
fi

execute "cd $current_dir"

# Restore stdout/stderr (and close temporary descriptors) if not verbose
[ $verbose -eq 1 ] || exec 1>&3 3>&- 2>&4 4>&-

mail_file="$mail_dir/mail_release_$release"
[ ! -e "$mail_file" ] || rm $mail_file

echo "[RELEASE] Apache Cassandra $release released" > $mail_file
echo "" >> $mail_file
echo "The Cassandra team is pleased to announce the release of Apache Cassandra" >> $mail_file
echo "version $release." >> $mail_file
echo "" >> $mail_file
echo "Apache Cassandra is a fully distributed database. It is the right choice" >> $mail_file
echo "when you need scalability and high availability without compromising" >> $mail_file
echo "performance." >> $mail_file
echo "" >> $mail_file
echo " http://cassandra.apache.org/" >> $mail_file
echo "" >> $mail_file
echo "Downloads of source and binary distributions are listed in our download" >> $mail_file
echo "section:" >> $mail_file
echo "" >> $mail_file
echo " http://cassandra.apache.org/download/" >> $mail_file
echo "" >> $mail_file
series="${release_short:0:1}.${release_short:2:1}"
echo "This version is a bug fix release[1] on the $series series. As always, please pay" >> $mail_file
echo "attention to the release notes[2] and Let us know[3] if you were to encounter" >> $mail_file
echo "any problem." >> $mail_file
echo "" >> $mail_file
echo "Enjoy!" >> $mail_file
echo "" >> $mail_file
echo "[1]: (CHANGES.txt)" >> $mail_file
echo "[2]: (NEWS.txt)" >> $mail_file
echo "[3]: https://issues.apache.org/jira/browse/CASSANDRA" >> $mail_file


echo "Done deploying artifacts. Please make sure to:"
echo " 0) commit changes to ${artifacts_svn_dir}"
echo " 1) release artifacts from repository.apache.org"
echo " 2) wait for the artifacts to sync at http://www.apache.org/dist/cassandra/"
echo " 3) update the website (~/Git/hyde/hyde.py -g -s src/ -d publish/)"
echo " 4) update CQL doc if appropriate"
echo " 5) update wikipedia page if appropriate"
echo " 6) send announcement email: draft in $mail_dir/mail_release_$release, misses short links for"
echo "    > CHANGES.txt: $asf_git_repo?p=cassandra.git;a=blob_plain;f=CHANGES.txt;hb=refs/tags/cassandra-$release"
echo "    > NEWS.txt:    $asf_git_repo?p=cassandra.git;a=blob_plain;f=NEWS.txt;hb=refs/tags/cassandra-$release"
echo " 7) update #cassandra topic on irc (/msg chanserv op #cassandra)"
echo " 8) tweet from @cassandra"
echo " 9) release version in JIRA"
echo " 10) remove old version from people.apache.org (in /www/www.apache.org/dist/cassandra and debian)"

