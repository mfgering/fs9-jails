

.DEFAULT_GOAL := help
#JAIL_HOST ?= test3
JAIL_HOST_TRANSMISSION ?= transmission_test
JAIL_HOST_SABNZBD ?= sabnzbd_test
JAIL_HOST_SONARR ?= sonarr_test
JAIL_HOST_RADARR ?= radarr_test
JAIL_HOST_JACKETT ?= jackett_test

FN_HOST ?= 192.168.1.229
FN_SETUP_DIR_NAME ?= fn9_setup
FN_USER_ME ?= mgering

.PHONY : clean portsnap openvpn clean_openvpn transmission transmission_dirs \
	clean-transmission jail_sabnzbd update_root_ssh_key fn9_setup \
	copy_setup_to_f9 mount_setup jail

help:
	@echo Hi there

clean: clean_openvpn clean_transmission

###############################################################################
# Run these remotely
###############################################################################

#######################
# FreeNAS 9 setup
#######################

remote_setup: update_root_ssh_key jail copy_setup_to_fn9 remote_transmission

update_root_ssh_key:
	-./in_host.py update_ssh_key $(FN_HOST) root id_rsa.pub

copy_setup_to_fn9:
	-ssh root@$(FN_HOST) mkdir $(FN_SETUP_DIR_NAME)
	scp -r -p * root@$(FN_HOST):$(FN_SETUP_DIR_NAME)/

# For each jail...

remote_transmission: mount_transmission_setup remote_jail_transmission_services

mount_transmission_setup: jail_transmission
	ssh root@$(FN_HOST) $(FN_SETUP_DIR_NAME)/fn9_host_make_mount.sh $(JAIL_HOST_TRANSMISSION) $(FN_SETUP_DIR_NAME)

jail_transmission:
	-./in_host.py create_jail $(FN_HOST) $(JAIL_HOST_TRANSMISSION)

remote_jail_transmission_services:
	ssh root@$(FN_HOST) make -C $(FN_SETUP_DIR_NAME) fn9_jail_transmission_services fn9_transmission_settings

remote_jail_transmission_storage:
	#TODO: FIX THIS
	$(error Need to add storage to the jail)

###############################################################################
# Run these within the FreeNAS host
###############################################################################

fn9_transmission_settings:
	cp transmission-settings.json /mnt/vol1/apps/transmission/settings.json
	chown media:media /mnt/vol1/apps/transmission/settings.json

fn9_jail_transmission_services:
	jexec $(JAIL_HOST_TRANSMISSION) make -C /root/$(FN_SETUP_DIR_NAME) jail_transmission_services

###############################################################################
# Run these within the jail
###############################################################################

###############
# Portsnap
###############

/var/db/portsnap:
	portsnap fetch

/usr/ports: /var/db/portsnap
	portsnap extract

portsnap: /usr/ports
	portsnap update

####################
# sabnzbd
####################
sabnzbd_source:
	-mkdir /tmp/fn9_setup
	-rm -fr /tmp/fn9_setup/SABnzbd-2.0.0 /tmp/fn9_setup/sabnzbd /usr/local/share/sabnzbd
	cd /tmp/fn9_setup; fetch https://github.com/sabnzbd/sabnzbd/releases/download/2.0.0/SABnzbd-2.0.0-src.tar.gz; \
	  tar xzf SABnzbd-2.0.0-src.tar.gz; \
	  mv SABnzbd-2.0.0 sabnzbd; \
	  sed -i '' -e "s/#!\/usr\/bin\/python -OO/#!\/usr\/local\/bin\/python2.7 -OO/" sabnzbd/SABnzbd.py; \
	  mv sabnzbd /usr/local/share/

sabnzbd_packages:
	pkg install -y py27-sqlite3 unzip py27-yenc py27-cheetah py27-openssl py27-feedparser py27-utils unrar par2cmdline

sabnzbd_config: /sabnzbd/config
	cp sabnzbd.rc.d /usr/local/etc/rc.d/sabnzbd
	./in_jail.py add_sabnzbd_rc_conf

/sabnzbd/config: FORCE
	mkdir -p $@
	chown media:media $@

sabnzbd: sabnzbd_packages sabnzbd_source sabnzbd_config

####################
# openvpn rules
####################

/usr/local/etc/openvpn:
	mkdir -p /usr/local/etc/openvpn

/usr/local/etc/rc.d/openvpn: /usr/local/etc/rc.d
	pkg install -y openvpn
	./in_jail.py add_openvpn_rc_conf

/openvpn:
	mkdir -p /openvpn
	chown media:media /openvpn

openvpn: /openvpn /usr/local/etc/openvpn /usr/local/etc/rc.d/openvpn 
	@echo openvpn installed

clean_openvpn:
	-service openvpn stop
	-pkg remove -y openvpn
	rm -fr /openvpn
	./in_jail.py remove_openvpn_rc_conf


####################
# transmission rules
####################

jail_transmission_services: transmission_dirs /usr/local/etc/rc.d/transmission

transmission_dirs: /transmission/config /transmission/watched /transmission/downloads /transmission/incomplete-downloads

/transmission/config /transmission/watched /transmission/downloads /transmission/incomplete-downloads: FORCE
	mkdir -p $@
	chown media:media $@

/usr/local/etc/rc.d/transmission: /usr/local/etc/rc.d
	pkg install -y transmission-daemon transmission-cli transmission-web
	./in_jail.py add_transmission_rc_conf
	#cp transmission-settings.json /transmission/config/settings.json
	touch /usr/local/etc/rc.d/transmission

transmission: transmission_dirs /usr/local/etc/rc.d/transmission
	-service transmission stop
	cp transmission-settings.json /transmission/config/settings.json

clean_transmission:
	-service transmission stop
	-pkg remove -y transmission-daemon transmission-cli transmission-web
	rm -fr /transmission
	-rmuser -y transmission
	./in_jail.py remove_transmission_rc_conf


##########################

FORCE:

test:
	echo "TEST!!"
