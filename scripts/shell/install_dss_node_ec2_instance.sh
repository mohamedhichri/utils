DKU_VERSION="14.3.2"
DKU_PATH="/data/DATA_DIR/"

sudo yum install wget -y

sudo mkdir -p /data/DATA_DIR

sudo chmod -R 755 /data/

sudo chown -R dataiku /data/DATA_DIR/

sudo useradd -m -u 12345 -s /bin/bash dataiku

sudo passwd -l dataiku

sudo su - dataiku

DKU_VERSION="14.3.2"
DKU_PATH="/data/DATA_DIR/"

pwd

wget https://downloads.dataiku.com/public/studio/${DKU_VERSION}/dataiku-dss-${DKU_VERSION}.tar.gz

# copy license.json file

tar xvf dataiku-dss-${DKU_VERSION}.tar.gz 

# If the User Isolation Framework is to be configured on this instance,
# make sure all user accounts have read-execute permission to the installation directory
chmod a+x .
umask 22

#switch back to ec2-user
DKU_VERSION="14.3.2"
sudo -i "/home/dataiku/dataiku-dss-${DKU_VERSION}/scripts/install/install-deps.sh"

# Run installer, with data directory $HOME/dss_data and base port 10000
dataiku-dss-${DKU_VERSION}/installer.sh -d ${DKU_PATH} -l /home/dataiku/license.json -p 10000

# Manually start DSS, using the command shown by the installer step
${DKU_PATH}/bin/dss start

${DKU_PATH}/bin/dss stop


# Create a system service, using the command shown by the previous step
sudo "/home/dataiku/dataiku-dss-${DKU_VERSION}/scripts/install/install-boot.sh" "${DKU_PATH}" dataiku
#
# Start the system service
sudo systemctl start dataiku
