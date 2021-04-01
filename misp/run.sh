#!/bin/bash
#
# MISP docker startup script
# Xavier Mertens <xavier@rootshell.be>
#
# 2017/05/17 - Created
# 2017/05/31 - Fixed small errors
# 2019/10/17 - Use built-in mysql docker DB creation and use std env names (dafal)
#

set -e

if [ -r /opt/misp/firstboot.tmp ]; then
        echo "Container started for the fist time. Setup might time a few minutes. Please wait..."
        echo "(Details are logged in /tmp/install.log)"
        export DEBIAN_FRONTEND=noninteractive

        # If the user uses a mount point restore our files
        if [ ! -d /var/www/MISP/app ]; then
                echo "Restoring MISP files..."
                cd /var/www/MISP
                tar xzpf /root/MISP.tgz
                rm /root/MISP.tgz
        fi

        echo "Configuring postfix"
        if [ -z "$POSTFIX_RELAY_HOST" ]; then
                echo "POSTFIX_RELAY_HOST is not set, please configure Postfix manually later..."
        else
                postconf -e "relayhost = $POSTFIX_RELAY_HOST"
        fi

        # Fix timezone (adapt to your local zone)
        if [ -z "$TIMEZONE" ]; then
                echo "TIMEZONE is not set, please configure the local time zone manually later..."
        else
                echo "$TIMEZONE" > /etc/timezone
                dpkg-reconfigure -f noninteractive tzdata >>/tmp/install.log
        fi

        echo "Creating MySQL database"

        # Check MYSQL_HOST
        if [ -z "$MYSQL_HOST" ]; then
                echo "MYSQL_HOST is not set. Aborting."
                exit 1
        fi
		
		# Waiting for DB to be ready
		while ! mysqladmin ping -h"$MYSQL_HOST" --silent; do
		    sleep 5
			echo "Waiting for database to be ready..."
		done
		
        # Set MYSQL_PASSWORD
        if [ -z "$MYSQL_PASSWORD" ]; then
                echo "MYSQL_PASSWORD is not set, use default value 'misp'"
                MYSQL_PASSWORD=misp
        else
                echo "MYSQL_PASSWORD is set to '$MYSQL_PASSWORD'"
        fi

        ret=`echo 'SHOW TABLES;' | mysql -u $MYSQL_USER --password="$MYSQL_PASSWORD" -h $MYSQL_HOST -P 3306 $MYSQL_DATABASE # 2>&1`
        if [ $? -eq 0 ]; then
                echo "Connected to database successfully!"
                found=0
                for table in $ret; do
                        if [ "$table" == "attributes" ]; then
                                found=1
                        fi
                done
                if [ $found -eq 1 ]; then
                        echo "Database misp available"
                else
                        echo "Database misp empty, creating tables ..."
                        ret=`mysql -u $MYSQL_USER --password="$MYSQL_PASSWORD" $MYSQL_DATABASE -h $MYSQL_HOST -P 3306 2>&1 < /var/www/MISP/INSTALL/MYSQL.sql`
                        if [ $? -eq 0 ]; then
                            echo "Imported /var/www/MISP/INSTALL/MYSQL.sql successfully"
                        else
                            echo "ERROR: Importing /var/www/MISP/INSTALL/MYSQL.sql failed:"
                            echo $ret
                        fi
                fi
        else
                echo "ERROR: Connecting to database failed:"
                echo $ret
        fi

        # MISP configuration
        echo "Creating MISP configuration files"
        cd /var/www/MISP/app/Config
        cp -a database.default.php database.php
        sed -i "s/localhost/$MYSQL_HOST/" database.php
        sed -i "s/db\s*login/$MYSQL_USER/" database.php
        sed -i "s/8889/3306/" database.php
        sed -i "s/db\s*password/$MYSQL_PASSWORD/" database.php

        # # Fix the base url
        # if [ -z "$MISP_BASEURL" ]; then
        #         echo "No base URL defined, don't forget to define it manually!"
        # else
        #         echo "Fixing the MISP base URL ($MISP_BASEURL) ..."
        #         sed -i "s@'baseurl'[\t ]*=>[\t ]*'',@'baseurl' => '$MISP_BASEURL',@g" /var/www/MISP/app/Config/config.php
        # fi

        # Less Red
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.language" "eng"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.host_org_id" 1
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.default_event_tag_collection" 0
        # Tune global time outs
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Session.autoRegenerate" 0
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Session.timeout" 600
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Session.cookieTimeout" 3600

        # Change base url, either with this CLI command or in the UI
        sudo -u www-data /var/www/MISP/app/Console/cake Baseurl $MISP_BASEURL
        # example: 'baseurl' => 'https://<your.FQDN.here>',
        # alternatively, you can leave this field empty if you would like to use relative pathing in MISP
        # 'baseurl' => '',
        # The base url of the application (in the format https://www.mymispinstance.com) as visible externally/by other MISPs.
        # MISP will encode this URL in sharing groups when including itself. If this value is not set, the baseurl is used as a fallback.
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.external_baseurl" $MISP_BASEURL

        # Enable GnuPG
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "GnuPG.email" "$MISP_ADMIN_EMAIL"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "GnuPG.homedir" "/var/www/MISP/.gnupg"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "GnuPG.password" "$MISP_GPG_PASSWORD"
        # FIXME: what if we have not gpg binary but a gpg2 one?
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "GnuPG.binary" "$(which gpg)"

        # Enable installer org and tune some configurable
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.host_org_id" 1
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.email" "$MISP_ADMIN_EMAIL"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.disable_emailing" true
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.contact" "$MISP_ADMIN_EMAIL"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.disablerestalert" true
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.showCorrelationsOnIndex" true
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.default_event_tag_collection" 0

        # Provisional Cortex tunes
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Cortex_services_enable" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Cortex_services_url" "http://127.0.0.1"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Cortex_services_port" 9000
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Cortex_timeout" 120
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Cortex_authkey" ""
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Cortex_ssl_verify_peer" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Cortex_ssl_verify_host" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Cortex_ssl_allow_self_signed" true

        # Various plugin sightings settings
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Sightings_policy" 0
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Sightings_anonymise" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Sightings_anonymise_as" 1
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Sightings_range" 365
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Sightings_sighting_db_enable" false

        # Plugin CustomAuth tuneable
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.CustomAuth_disable_logout" false

        # RPZ Plugin settings
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.RPZ_policy" "DROP"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.RPZ_walled_garden" "127.0.0.1"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.RPZ_serial" "\$date00"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.RPZ_refresh" "2h"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.RPZ_retry" "30m"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.RPZ_expiry" "30d"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.RPZ_minimum_ttl" "1h"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.RPZ_ttl" "1w"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.RPZ_ns" "localhost."
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.RPZ_ns_alt" ""
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.RPZ_email" "root.localhost"

        # Force defaults to make MISP Server Settings less RED
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.language" "eng"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.proposals_block_attributes" false

        # Redis block
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.redis_host" "127.0.0.1"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.redis_port" 6379
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.redis_database" 13
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.redis_password" ""

        # Force defaults to make MISP Server Settings less YELLOW
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.ssdeep_correlation_threshold" 40
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.extended_alert_subject" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.default_event_threat_level" 4
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.newUserText" "Dear new MISP user,\\n\\nWe would hereby like to welcome you to the \$org MISP community.\\n\\n Use the credentials below to log into MISP at \$misp, where you will be prompted to manually change your password to something of your own choice.\\n\\nUsername: \$username\\nPassword: \$password\\n\\nIf you have any questions, don't hesitate to contact us at: \$contact.\\n\\nBest regards,\\nYour \$org MISP support team"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.passwordResetText" "Dear MISP user,\\n\\nA password reset has been triggered for your account. Use the below provided temporary password to log into MISP at \$misp, where you will be prompted to manually change your password to something of your own choice.\\n\\nUsername: \$username\\nYour temporary password: \$password\\n\\nIf you have any questions, don't hesitate to contact us at: \$contact.\\n\\nBest regards,\\nYour \$org MISP support team"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.enableEventBlocklisting" true
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.enableOrgBlocklisting" true
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.log_client_ip" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.log_auth" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.disableUserSelfManagement" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.disable_user_login_change" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.disable_user_password_change" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.disable_user_add" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.block_event_alert" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.block_event_alert_tag" "no-alerts=\"true\""
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.block_old_event_alert" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.block_old_event_alert_age" ""
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.block_old_event_alert_by_date" ""
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.incoming_tags_disabled_by_default" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.maintenance_message" "Great things are happening! MISP is undergoing maintenance, but will return shortly. You can contact the administration at \$email."
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.footermidleft" ""
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.footermidright" ""
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.welcome_text_top" ""


        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.welcome_text_bottom" "Welcome to MISP."
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.attachments_dir" "/var/www/MISP/app/files"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.download_attachments_on_load" true
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.title_text" "MISP"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.terms_download" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.showorgalternate" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "MISP.event_view_filter_fields" "id, uuid, value, comment, type, category, Tag.name"

        # Force defaults to make MISP Server Settings less GREEN
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "debug" 0
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Security.auth_enforced" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Security.rest_client_baseurl" ""
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Security.advanced_authkeys" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Security.password_policy_length" 12
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Security.password_policy_complexity" '/^((?=.*\d)|(?=.*\W+))(?![\n])(?=.*[A-Z])(?=.*[a-z]).*$|.{16,}/'
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Security.self_registration_message" "If you would like to send us a registration request, please fill out the form below. Make sure you fill out as much information as possible in order to ease the task of the administrators."

        # Set Plugin Settings
        # Enrichment
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Enrichment_services_enable" true
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Enrichment_hover_enable" false
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Enrichment_hover_popover_only" true
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Enrichment_timeout" 10
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Enrichment_hover_timeout" 5
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Enrichment_services_url" "http://127.0.0.1"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Enrichment_services_port" 6666

        # Import
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Import_services_enable" true
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Import_timeout" 10  
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Import_services_url" "http://127.0.0.1"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Import_services_port" 6666

        # Export
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Export_services_enable" true
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Export_timeout" 10 
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Export_services_url" "http://127.0.0.1"
        sudo -u www-data /var/www/MISP/app/Console/cake Admin setSetting "Plugin.Export_services_port" 6666
                
fi
        

        # Generate the admin user PGP key
        echo "Creating admin GnuPG key"
        echo "Passphrase is: $MISP_GPG_PASSWORD"
        if [ -z "$MISP_ADMIN_EMAIL" -o -z "$MISP_ADMIN_PASSPHRASE" ]; then
                echo "No admin details provided, don't forget to generate the PGP key manually!"
        else
                echo "Generating admin PGP key ... (please be patient, we need some entropy)"
                cat >/tmp/gpg.tmp <<GPGEOF
%echo Generating a basic OpenPGP key
Key-Type: RSA
Key-Length: 2048
Name-Real: MISP Admin
Name-Email: $MISP_ADMIN_EMAIL
Expire-Date: 0
Passphrase: $MISP_GPG_PASSWORD
%commit
%echo Done
GPGEOF
fi

if [ -r /opt/misp/firstboot.tmp ]; then
        
        sudo -u www-data gpg --homedir /var/www/MISP/.gnupg --gen-key --batch /tmp/gpg.tmp >>/tmp/install.log
        rm -rf /tmp/gpg.tmp
        sudo -u www-data gpg --homedir /var/www/MISP/.gnupg --export --armor $MISP_ADMIN_EMAIL > /var/www/MISP/app/webroot/gpg.asc
        sudo rm -rf /opt/misp/firstboot.tmp
        sudo rm -rf /tmp/*
fi

# Make MISP live - this isn't ideal, as it means taking an instance
# non-live will make it live again if the container restarts.  That seems
# better than the default which is that MISP is non-live on container restart.
# Ideally live/non-live would be persisted in the database.
/var/www/MISP/app/Console/cake live 1
chown www-data:www-data /var/www/MISP/app/Config/config.php*

# Start supervisord
echo "Starting supervisord"
cd /
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf


echo "***********************************************************************************"
echo "**                       MISP-DOCKER START UP COMPLETE                           **"
echo "***********************************************************************************"
echo "***********************************************************************************"