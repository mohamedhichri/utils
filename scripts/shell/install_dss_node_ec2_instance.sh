sudo useradd -m -u 12345 -s /bin/bash dataiku

sudo passwd -l dataiku

sudo su - dataiku

pwd

wget https://downloads.dataiku.com/public/studio/14.5.0/dataiku-dss-14.5.0.tar.gz

# copy license.json file

tar xvf dataiku-dss-14.5.0.tar.gz 

# If the User Isolation Framework is to be configured on this instance,
# make sure all user accounts have read-execute permission to the installation directory
chmod a+x .
umask 22

#switch back to ec2-user
sudo -i "/home/dataiku/dataiku-dss-14.5.0/scripts/install/install-deps.sh"

# Run installer, with data directory $HOME/dss_data and base port 10000
dataiku-dss-14.5.0/installer.sh -d /home/dataiku/dss_data -l /home/dataiku/license.json -p 10000

# Manually start DSS, using the command shown by the installer step
/home/dataiku/dss_data/bin/dss start

/home/dataiku/dss_data/bin/dss stop


# Create a system service, using the command shown by the previous step
sudo "/home/dataiku/dataiku-dss-14.5.0/scripts/install/install-boot.sh" "/home/dataiku/dss_data" dataiku
#
# Start the system service
sudo systemctl start dataiku
