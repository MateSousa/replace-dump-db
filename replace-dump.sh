#!/usr/bin/env bash

cd "$(dirname "$0")"

#Arguments
DATABASE_NAME=$1
DUMP_FILE=$2
#MYSQL credentials, if this is the first time you run this script, you need to set the credentials as a argument, 
#after that a new file called .my.cnf will be created in the root of the project and you don't need to set the credentials anymore.
MYSQL_USER=$3
MYSQL_PASSWORD=$4

#Validate all arguments

if [ -z "$DATABASE_NAME" ]; then
	echo "You need to set the database name as argument"
	exit 1
fi

if [ -z "$DUMP_FILE" ]; then
	echo "Dump file not set, using the s3 bucket"
fi

if [ ! -f "$CONFIG_FILE" ]; then
	if [ -z "$MYSQL_USER" ]; then
		echo "You need to set the mysql user as argument"
		exit 1
	fi

	if [ -z "$MYSQL_PASSWORD" ]; then
		echo "You need to set the mysql password as argument"
		exit 1
	fi
fi

#Variables
MYSQL_HOST="localhost"
MYSQL_PORT="3306"
CONFIG_FILE=".my.cnf"
S3_BUCKET=
OS_SYSTEM=

#check os system
if [ "$(uname)" == "Darwin" ]; then
    OS_SYSTEM="mac"
elif [ "$(expr substr $(uname -s) 1 5)" == "Linux" ]; then
    OS_SYSTEM="linux"
elif [ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]; then
    OS_SYSTEM="windows"
fi

if ! command -v mysql &> /dev/null; then
	echo "Error: mysql client is not installed." >&2
	exit 1
fi

handle_mysql_credentials() {
	if [ ! -f "$CONFIG_FILE" ] && [[ -z "$MYSQL_USER" || -z "$MYSQL_PASSWORD" ]]; then
		echo "You need to set the mysql user and password as arguments"
		exit 1
	fi

	if [ -f "$CONFIG_FILE" ]; then
		case "$OS_SYSTEM" in
			linux|mac)
				MYSQL_USER=$(grep user "$CONFIG_FILE" | cut -d'=' -f2)
				MYSQL_PASSWORD=$(grep password "$CONFIG_FILE" | cut -d'=' -f2)
				;;
			windows)
				MYSQL_USER=$(findstr user "$CONFIG_FILE" | cut -d'=' -f2)
				MYSQL_PASSWORD=$(findstr password "$CONFIG_FILE" | cut -d'=' -f2)
				;;
		esac
	fi

	if [ ! -f "$CONFIG_FILE" ]; then
		echo "Creating .my.cnf file"
		echo "[client]" >> "$CONFIG_FILE"
		echo "user=$MYSQL_USER" >> "$CONFIG_FILE"
		echo "password=$MYSQL_PASSWORD" >> "$CONFIG_FILE"
	fi
}

handle_aws_credentials() {
	echo "Checking if aws cli is installed"

	if ! command -v aws &> /dev/null; then
		echo "Error: aws cli is not installed." >&2
		exit 1
	fi

	AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id)
    AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key)


	if [ -z "$AWS_ACCESS_KEY_ID" ]; then
		echo "Error: aws_access_key_id is not set." >&2
		exit 1
	fi

	if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
		echo "Error: aws_secret_access_key is not set." >&2
		exit 1
	fi

	echo "AWS looks good"
}

handle_db_dump_file() {
	if [ ! -f "$DUMP_FILE.sql" ]; then
		echo "The dump file does not exist, getting it from s3 bucket"

		handle_aws_credentials

		echo "Getting the last dump file from s3 bucket"
		S3_DUMP_FILE=$(aws s3api list-objects --bucket "$S3_BUCKET" --query 'reverse(sort_by(Contents,&LastModified))[0].Key' --output text)

		if [ -z "$S3_DUMP_FILE" ]; then
			echo "Error getting the dump file from s3 bucket"
			exit 1
		fi

		echo "Downloading dump file from s3 bucket"
		aws s3 cp "s3://$S3_BUCKET/$S3_DUMP_FILE" "$DUMP_FILE.sql"

		if [ $? -ne 0 ]; then
			echo "Error downloading dump file from s3 bucket"
			exit 1
		fi

		DUMP_FILE="$DUMP_FILE.sql"

		echo "Dump file downloaded from s3 bucket successfully, using it"
	else 
		echo "Dump file exists, using it"
	fi
}

handle_mysql_credentials
handle_db_dump_file

delete_create_import_database() {
	echo "Deleting database $DATABASE_NAME"
	mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "DROP DATABASE IF EXISTS $DATABASE_NAME"

	echo "Creating database $DATABASE_NAME"
	mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" -e "CREATE DATABASE $DATABASE_NAME"

	echo "Importing dump file $DUMP_FILE"
	mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -p"$MYSQL_PASSWORD" "$DATABASE_NAME" < "$DUMP_FILE"

	echo "Deleting dump file $DUMP_FILE"
	rm "$DUMP_FILE"	
	
	if [ $? -ne 0 ]; then
		echo "Error importing dump file $DUMP_FILE"
		exit 1
	fi

}

running_informations() {
	echo "Running with the following arguments:"
	echo "DATABASE_NAME: $DATABASE_NAME"
	echo "DUMP_FILE: $DUMP_FILE"
	echo "MYSQL_USER: $MYSQL_USER"
	echo "MYSQL_PASSWORD: $MYSQL_PASSWORD"
	echo "MYSQL_HOST: $MYSQL_HOST"
	echo "MYSQL_PORT: $MYSQL_PORT"
	echo "S3_BUCKET: $S3_BUCKET"
	echo "OS_SYSTEM: $OS_SYSTEM"
	echo "CONFIG_FILE: $CONFIG_FILE"   
	echo "S3_DUMP_FILE: $S3_DUMP_FILE"   
	echo "Running the script in the following directory: $(pwd)"

	echo "Script will run in 5 seconds, press ctrl + c to cancel"

	sleep 5
}

# Main
running_informations
delete_create_import_database

echo "Script finished successfully, bye bye :)"
