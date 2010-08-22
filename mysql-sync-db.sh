#!/bin/sh
#
# See Usage statement for more information.
#

usage() {
cat <<EOUSAGE

Usage: `basename $0` --source-config source-my.cnf-file --destination-config destination-my.cnf-file
	
	20100821 Xavier Snark xssnark@gmail.com
	A simple, limited shell script for synchronizing MySQL databases between servers.
	This script uses my.cnf defaults files for managing the migration of data between the source
	and destination databases. An example defaults file mmay contain:

		[client]
		host=your_db_hostname
		database=my_database
		user=my_username
		password="my_secret_passord"
	
	To use, create two of these files, one for the source database
	(perhaps named "source_db_config") and one for the destination (perhaps named "dest_db_config").
	Call this script with these config files as arguments, for example:

		$0 -v -n -s source_db_config -d dest_db_config

	Note this command would operate in dry-run mode and not actually perform any operations.

Required Arguments:
	-s or --source-config my.cnf-file
	-d or --destination-config my.cnf-file
		This is to specify a source and destination my.cnf file. This must be used to pass username,
		password, host, and database settings for accessing the servers.
Optional Arguments
	-o
	--dump-database
		This specifies the specific database name to dump from the source host. (mysqldump will NOT use
		database specification in the config files, at least not that I've been able to determine. It
		must have database names passed on the command line.)
		If this is omitted, the script will attempt to determine the database for the source database
		by connecting to the source and issuing a select DATABASE() and then capturing the output.
		This argument only affects the SOURCE database, the destination will be the database configured
		in the destination defaults file.
	-v
	--verbose
		Spew a lot of messages about what's happening.
	-l
	--verbose-mysql
		Run MySQL commands in verbose mode. (Mnemonic: "loud"; Independent of -v argument)
	-n
	--dry-run
		Don't perform the cleaning, dump, or import operations.
		
EOUSAGE
}


# Make sure then pass at least two arguments
# (-r is optional)
# This is nearly useless 
if [ $# -lt 4 ]; then
	echo "Invalid arguments supplied (At least 2 are required, but you supplied $#)."
	usage
	exit 1
fi

# Get arguments, if any
while [ ! -z $1 ]; do
	case $1
	in
		--help)
		usage
		exit
				;;
		-s|--source-config)
			SRC_CNF=$2
				test ! -e $SRC_CNF && echo "ERROR: Unable to locate source configuration file: $SRC_CNF" && exit 1
				test $VERBOSE && echo "Setting source config file to $SRC_CNF"
				shift 2
				;;
		-d|--destination-config)
				DST_CNF=$2
				test ! -e $DST_CNF && echo "ERROR: Unable to locate destination configuration file: $DST_CNF" && exit 1
				test $VERBOSE && echo "Setting destination config file to $DST_CNF"
				shift 2
				;;
		-o|--dump-database)
				DUMPDB=$2
				test $VERBOSE && echo "Using explicit dump database specification: $DUMPDB"
				shift 2
				;;
		-n|--dry-run)
				DRY_RUN=1
				shift
				;;
		-v|--verbose)
			VERBOSE=1
				shift
				;;
		-l|--verbose-mysql)
			MYVERBOSE=-v
				shift
				;;
		-h|--help)
			# fairly pointless here since there's a minimum number of required arguments.
			usage
			exit 0
			;;
		*) 
				echo "Unknown Option: \"$1\""
				usage
				exit 1
				;;
	esac
done

test -z $SRC_CNF && (echo "ERROR: Empty source config file: $SRC_CNF" && exit 1)
test -z $DST_CNF && (echo "ERROR: Empty destination config file: $DST_CNF" && exit 1)
test ! -e $SRC_CNF && echo "ERROR: Unable to locate source configuration file: $SRC_CNF" && exit 1
test ! -e $DST_CNF && echo "ERROR: Unable to locate destination configuration file: $DST_CNF" && exit 1

# Because mysqldump won't use the database configured in the defaults file, this bit
# of nonsense is used to tease out the database
identify_dump_db() {
	test $VERBOSE && echo "Identifying dump database..."
	DUMPDB=`echo 'select DATABASE()' | mysql --defaults-file=$DST_CNF | grep -v DATABASE`
	test -z $DUMPDB && echo "ERROR: Unable to determine name of dump database, exiting." && exit 2
	test $VERBOSE && echo "dump database is: $DUMPDB"
}

cleandb() {
	CLEAN_DEFAULTS_FILE=$1
	test $VERBOSE && echo "Generating list of tables to clean from database using config $CLEAN_DEFAULTS_FILE"
	echo 'show tables' | mysql --defaults-file=$CLEAN_DEFAULTS_FILE | while read TABLE; do 
		test $VERBOSE && (test ! $DRY_RUN && echo "Attempting to drop table if existing: $TABLE" || echo "Would be dropping table if existing: $TABLE")
		test ! $DRY_RUN && ( echo "drop table if exists $TABLE" | mysql --defaults-file=$CLEAN_DEFAULTS_FILE)
	done
}

import_pipe() {
	test $VERBOSE && (test ! $DRY_RUN && echo "Performing dump/import process..." || echo "Skipping dump/import process")
	test ! $DRY_RUN && mysqldump --defaults-file=$SRC_CNF $MYVERBOSE $DUMPDB | mysql --defaults-file=$DST_CNF $MYVERBOSE
	PIPE_EXIT=$?
	test ! $DRY_RUN && test $PIPE_EXIT -ne 0 && echo "Warning: pipeline exited with $PIPE_EXIT"
}

test $DRY_RUN && echo "Operating in dry-run mode."

test -z $DUMPDB && test $VERBOSE && echo "Attempting to identify dump database..."
test -z $DUMPDB && identify_dump_db

test $VERBOSE && (test ! $DRY_RUN && echo "Preparing to clean out destination database..." || echo "Skipping cleaning destination database.")
cleandb $DST_CNF

import_pipe $SRC_CNF $DST_CNF

