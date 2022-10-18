#!/bin/bash

TEMPLATE_SED_FILEPATH="template.sed"
TURN_ADD_MISSING_USER_FILEPATH="turn_add_missing_user.sh"
CONFIGURATION_VOIP_FILEPATH=./synapse/voip.yaml

ERROR_CODE_NOT_ENOOUGH_ARGUMENTS=1
ERROR_CODE_SSL_DIRECTORIES_MISSING=2
ERROR_CODE_SSL_FILES_MISSING=3
ERROR_CODE_SSL_CANT_GENERATE_COMPLETE_PEM=4
ERROR_CODE_TEMPLATES_MISSING=5
ERROR_CODE_TEMPLATES_CANNOT_GENERATE_SED_FILE=6
ERROR_CODE_COTURN_CANT_GENERATE_ADD_USER_SCRIPT=7


bail_out() {
	error_code=$1
	# If you need a little more security, you can uncomment
	# the following lines.
	# If you need real security, don't use this script and
	# do it yourself, using the various security features
	# provided by Docker.
	#if [ -f "$TEMPLATE_SED_FILEPATH" ];
	#then
	#	rm "$TEMPLATE_SED_FILEPATH"
	#fi
	exit $error_code
}

generate_secret() {
	echo $(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
}

print_ssl_files_requirements() {
	echo "× You need the following files :"
	echo "- fullchain.pem : Certificate with full chain of trust"
	echo "- privkey.pem   : The private key associated with the SSL certificate"
}

check_ssl_files() {
	if [ ! -d "ssl" ];
	then
		echo "× ssl/ is missing, or inaccessible"
		echo "× Place the SSL files for  in ssl/"
		print_ssl_files_requirements
		bail_out $ERROR_CODE_SSL_DIRECTORIES_MISSING
	fi

	if [ ! -f "ssl/coturn.key.pem" -o ! -f "ssl/coturn.crt.pem" ];
	then
		echo "× Some files are missing in ssl/"
		print_ssl_files_requirements
		bail_out $ERROR_CODE_SSL_FILES_MISSING
	fi

	echo "✓ SSL files are present"
}

template_generate_sed_file() {
	matrix_domain="$1"
	turn_domain="$2"
	turn_external_ip="$3"
	turn_username="$4"
	turn_password="$5"

	cat << EOF > "$TEMPLATE_SED_FILEPATH"
s/\${matrix_domain}/$matrix_domain/g
s/\${turn_domain}/$turn_domain/g
s/\${turn_username}/$turn_username/g
s/\${turn_password}/$turn_password/g
s/\${turn_external_ip}/$turn_external_ip/g
EOF

	if [ $? -ne 0 ];
	then
		echo "× Could not write into $TEMPLATE_SED_FILEPATH"
		echo "× Exiting..."
		bail_out $ERROR_CODE_TEMPLATES_CANNOT_GENERATE_SED_FILE
	else
		echo "✓ sed file generated successfully"
	fi

	
}

template_check_for_files() {
	output_filepaths="$1"
	templates="present"

	for out_filepath in $output_filepaths;
	do
		template_filepath="$out_filepath.template"
		if [ ! -f "$template_filepath" ];
		then
			echo "Template for $template_filepath is not present anymore"
			templates="missing"
		fi
	done

	if [ ! "$templates" = "present" ];
	then
		echo "× Some templates are missing"
		echo "× Exiting"
		bail_out $ERROR_CODE_TEMPLATES_MISSING
	fi
}

template_generate_files() {
	output_filepaths="$1"
	for out_filepath in $output_filepaths;
	do
		template_filepath="$out_filepath.template"
		sed -f "$TEMPLATE_SED_FILEPATH" "$template_filepath" > "$out_filepath"
	done
}

generate_turn_configuration() {
	# While Synapse support multiple URI for TURN
	# defining an array of URI through environment variables is
	# kind of a pain
	# We could always some sort of delimiter, but I'd rather generate
	# a simple configuration file and let the user edit it if they're
	# dealing with a very complex setup
	turn_main_uri=$1
	turn_user=$2
	turn_password=$3
	cat << EOF > "$CONFIGURATION_VOIP_FILEPATH"
turn_uris: ["turn:$turn_main_uri:5349"]
turn_username: "$turn_user"
turn_password: "$turn_password"
turn_allow_guests: false
EOF
}

coturn_generate_add_missing_user_script() {
	cat << EOF > $TURN_ADD_MISSING_USER_FILEPATH
#!/bin/bash
echo "If a Docker error occurs, make sure to run this script with"
echo "appropriate privileges, and that the services are up"
echo "(docker-compose up -d)"
echo ""
docker-compose exec coturn turnadmin -a -b "/srv/coturn/turndb" -u "$turn_username" -p "$turn_password" -r "$turn_domain"
EOF
	if [ $? -ne 0 ];
	then
		echo ""
		echo "Could not generate the script to add the missing COTURN user"
		echo "You'll have to run previously mentionned docker command manually"
		bail_out $ERROR_CODE_COTURN_CANT_GENERATE_ADD_USER_SCRIPT
	fi

	chmod +x $TURN_ADD_MISSING_USER_FILEPATH
	if [ $? -ne 0 ];
	then
		echo ""
		echo "  OR simply run : sh ./$TURN_ADD_MISSING_USER_FILEPATH"
	else
		echo "  OR simply run : ./$TURN_ADD_MISSING_USER_FILEPATH"
	fi
}

coturn_advise_to_add_user() {
	turn_username="$1"
	turn_password="$2"
	turn_domain="$3"
	echo ""
	echo "● The TURN credentials have been written in ./synapse/voip.yaml"
	echo "- It should be copied in your synapse/conf/homeserver.d/voip.yaml conf."
	echo "● Once the services up and running (docker-compose up -d)"
	echo "  Remember to add the TURN user in COTURN by running :"
	echo "docker-compose exec coturn turnadmin -a -b \"/srv/coturn/turndb\" -u \"$turn_username\" -p \"$turn_password\" -r \"$turn_domain\""
}

print_usage() {
	echo "./automate.sh your.matrix.domain.com your.turn.domain.com"
	echo ""
	echo "Notes"
	echo "-----"
	echo ""
	echo "This script will (re)generate all the configuration files"
	echo "required to run an instance of Synapse, using this Docker"
	echo "setup."
	echo ""
	echo "A few required variables might be autogenerated, if not provided :"
	echo "- The TURN username if TURN_USERNAME is not set"
	echo "  (Currently set to \"$TURN_USERNAME\")"
	echo "- The TURN password if TURN_PASSWORD is not set"
	echo "  (Currently set to \"$TURN_PASSWORD\")"
	echo ""
	echo "Each file will be generated using a filename.ext.template file"
	echo "Only the parts of the templates with \$\{ \} will be modified"
}

if [ "$#" -lt 3 ];
then
	echo "Not enough arguments"
	print_usage
	bail_out $ERROR_CODE_NOT_ENOOUGH_ARGUMENTS
fi

MATRIX_DOMAIN="$1"
TURN_DOMAIN="$2"
TURN_PUBLIC_IP_ADDRESS="$3"

# We don't check for strings with only spaces
# If the user REALLY want to fuck up his configuration
# I won't stop him

# Yes the comparator is "=" not "=="
# Because SHit happens

if [ "$TURN_USERNAME" = "" ];
then
	TURN_USERNAME="$(generate_secret)"
	echo "● TURN username not provided or empty"
	echo "● Generating a new TURN username : $TURN_USERNAME"
fi

if [ "$TURN_PASSWORD" = "" ];
then
	TURN_PASSWORD="$(generate_secret)"
	echo "● TURN password not provided or empty"
	echo "● Generating a new TURN password : $TURN_PASSWORD"
fi

echo "● Using the following setup:"
echo "- MATRIX_DOMAIN          : $MATRIX_DOMAIN"
echo "- TURN_PUBLIC_IP_ADDRESS : $TURN_PUBLIC_IP_ADDRESS"
echo "- TURN_DOMAIN            : $TURN_DOMAIN"
echo "- TURN_USERNAME          : $TURN_USERNAME"
echo "- TURN_PASSWORD          : $TURN_PASSWORD"
echo ""

template_generate_sed_file "$MATRIX_DOMAIN" "$TURN_DOMAIN" "$TURN_PUBLIC_IP_ADDRESS" "$TURN_USERNAME" "$TURN_PASSWORD" &&

check_ssl_files &&

echo "✓ ssl certs present"

FILES_TO_GENERATE="
coturn/turnserver.conf
"

template_check_for_files "$FILES_TO_GENERATE" &&

echo "✓ Template files present" && 

template_generate_files "$FILES_TO_GENERATE" &&

echo "✓ Configuration files generated !" &&

echo "" &&
echo "● You can now start your server with :" &&
echo "docker-compose up -d" &&

generate_turn_configuration "$TURN_DOMAIN" "$TURN_USERNAME" "$TURN_PASSWORD" "$TURN_PUBLIC_IP_ADDRESS" &&
coturn_advise_to_add_user "$TURN_USERNAME" "$TURN_PASSWORD" "$TURN_DOMAIN" &&
coturn_generate_add_missing_user_script "$TURN_USERNAME" "$TURN_PASSWORD" "$TURN_DOMAIN"
