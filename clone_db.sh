#!/bin/bash
# clone_db.sh: Clone a database into another database.

echo ""
echo "Processing '$0 $1 $2 $3'"
echo ""

if [ "$(whoami)" != 'root' ]; then
    echo "You need to use '[root]# $0' or 'sudo $0' to run this script.";
    exit 1;
fi

. db.conf

if [ -z "$1" ] || [ -z "$2" ]; then
  echo "pull_db.sh [source] [destination] [no backup]";
  echo "";
  echo -e "\tsource\t\t- The source database (from list)";
  echo -e "\tdestination\t- The destination database (from list)";
  echo -e "\tno backup\t- optionally set this to 1 to not backup the destination database";
  echo "";
  echo -e "\tAvailable databases:";
  
  for i in ${AVAILABLE_DB[@]}; do
    echo -e "\t- ${i}";
  done
  echo "";
  exit 1;
fi

if [ "$2" == 'production' ]; then 
    echo "You can not clone to production from any database."; 
    echo "";
    exit 1;
fi

SOURCE_DB=$1
SOURCE_CONFIG="db_$1"
DESTINATION_DB=$2
DESTINATION_CONFIG="db_$2"

if [ -z $(eval "echo \${$SOURCE_CONFIG[HOST]}") ]; then
    echo "The name '$1' specified as the source database has no configuration.";
    echo "";
    exit 1;
fi

if [ -z $(eval "echo \${$DESTINATION_CONFIG[HOST]}") ]; then
    echo "The name '$2' specified as the destination database has no configuration.";
    echo "";
    exit 1;
fi

SOURCE_HOST=$(eval "echo \${$SOURCE_CONFIG[HOST]}")
SOURCE_DATABASE=$(eval "echo \${$SOURCE_CONFIG[DATABASE]}")
SOURCE_USERNAME=$(eval "echo \${$SOURCE_CONFIG[USERNAME]}")
SOURCE_PASSWORD=$(eval "echo \${$SOURCE_CONFIG[PASSWORD]}")

DESTINATION_HOST=$(eval "echo \${$DESTINATION_CONFIG[HOST]}")
DESTINATION_DATABASE=$(eval "echo \${$DESTINATION_CONFIG[DATABASE]}")
DESTINATION_USERNAME=$(eval "echo \${$DESTINATION_CONFIG[USERNAME]}")
DESTINATION_PASSWORD=$(eval "echo \${$DESTINATION_CONFIG[PASSWORD]}")

MYSQL_CMD="mysql -h $SOURCE_HOST -u $SOURCE_USERNAME --password=\"$SOURCE_PASSWORD\" -e \";\""

if [ ! $MYSQL_CMD 2>/dev/null ]; then
    echo "Incorrect MySQL login details for '$SOURCE_DB' - '$SOURCE_HOST'"
    echo ""
    exit 1;
fi

MYSQL_CMD="mysql -h $DESTINATION_HOST -u $DESTINATION_USERNAME --password=\"$DESTINATION_PASSWORD\" -e \";\""

if [ ! $MYSQL_CMD 2>/dev/null ]; then
    echo "Incorrect MySQL login details for '$DESTINATION_DB' - '$DESTINATION_HOST'"
    echo ""
    exit 1;
fi

DATE=`date +%Y%m%d_%H%M%S`

echo "";
echo "This will clone all data from '$SOURCE_DATABASE' into '$DESTINATION_DATABASE'";
echo "";
if [ "$3" ]; then
    echo "WARNING: '$DESTINATION_DB' - '$DESTINATION_DATABASE' will not be backed up!"
else
    echo "NOTE: '$DESTINATION_DB' - '$DESTINATION_DATABASE' will be backed up to 'backups/saved/${DESTINATION_DATABASE}_$DATE.sql'"
fi
echo "";
read -r -p "Do you want to continue? [y/N] " response
response=${response,,}    # tolower
if [[ $response =~ ^(yes|y)$ ]]; then

    # pull the database configuration

    if [ -z "$3" ]; then
        # Backup destination
        mkdir -p "./backups/saved"
        mysqldump -h $DESTINATION_HOST -p --user=$DESTINATION_USERNAME --password=$DESTINATION_PASSWORD --add-drop-table --add-drop-database --databases $DESTINATION_DATABASE > backups/saved/TEMP_${DESTINATION_DATABASE}_$DATE.sql
        # Remove definer that can not be used in RDS
        perl -pe 's/\sDEFINER=`[^`]+`@`[^`]+`//' < ./backups/saved/TEMP_${DESTINATION_DATABASE}_$DATE.sql > ./backups/saved/${DESTINATION_DATABASE}_$DATE.sql
        unlink ./backups/saved/TEMP_${DESTINATION_DATABASE}_$DATE.sql
        zip ./backups/saved/${DESTINATION_DATABASE}_$DATE.zip ./backups/saved/${DESTINATION_DATABASE}_$DATE.sql
        unlink ./backups/saved/${DESTINATION_DATABASE}_$DATE.sql
    fi

    mkdir -p "./backups/current"

    # Pull the source down
    mysqldump -h $SOURCE_HOST -p --user=$SOURCE_USERNAME --password=$SOURCE_PASSWORD --add-drop-table $SOURCE_DATABASE > backups/current/TEMP_$SOURCE_DATABASE.sql

    # Remove definer that can not be used in RDS
    perl -pe 's/\sDEFINER=`[^`]+`@`[^`]+`//' < ./backups/current/TEMP_$SOURCE_DATABASE.sql > ./backups/current/$SOURCE_DATABASE.sql
    unlink ./backups/current/TEMP_$SOURCE_DATABASE.sql

    # Push the source onto the destination
    mysql -h $DESTINATION_HOST --user=$DESTINATION_USERNAME --password=$DESTINATION_PASSWORD -e "DROP DATABASE IF EXISTS ${DESTINATION_DATABASE}"
    mysql -h $DESTINATION_HOST --user=$DESTINATION_USERNAME --password=$DESTINATION_PASSWORD -e "CREATE DATABASE ${DESTINATION_DATABASE} DEFAULT CHARACTER SET utf8mb4"
    mysql -h $DESTINATION_HOST --user=$DESTINATION_USERNAME --password=$DESTINATION_PASSWORD --database=$DESTINATION_DATABASE < backups/current/$SOURCE_DATABASE.sql

    # Remove final restore file that we have used
    unlink ./backups/current/$SOURCE_DATABASE.sql
        
fi

exit 0;