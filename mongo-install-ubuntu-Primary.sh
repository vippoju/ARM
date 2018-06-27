#!/bin/bash
dnsname=$1
secondarynodecount=$2
inputlocation=$3
cat /dev/null > /var/log/mongolog.log

echo "dnsname ${dnsname}" >> /var/log/mongolog.log
echo "secondarynodecount ${secondarynodecount}" >> /var/log/mongolog.log
echo "inputlocation ${inputlocation}" >> /var/log/mongolog.log
echo "executing install Mongo started" >> /var/log/mongolog.log

# Disable THP
sudo echo never > /sys/kernel/mm/transparent_hugepage/enabled
sudo echo never > /sys/kernel/mm/transparent_hugepage/defrag
sudo grep -q -F 'transparent_hugepage=never' /etc/default/grub || echo 'transparent_hugepage=never' >> /etc/default/grub

log()
{
    # Un-comment the following if you would like to enable logging to a service
    #curl -X POST -H "content-type:text/plain" --data-binary "${HOSTNAME} - $1" https://logs-01.loggly.com/inputs/<key>/tag/es-extension,${HOSTNAME}
    echo "$1" >> /var/log/mongolog.log
} 

log "secondary script execution - start"

install_mongodb()
{
log "install_mongodb32 - start"

sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv EA312927

echo "deb http://repo.mongodb.com/apt/ubuntu trusty/mongodb-enterprise/3.2 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-enterprise.list

# Disable THP
sudo echo never > /sys/kernel/mm/transparent_hugepage/enabled
sudo echo never > /sys/kernel/mm/transparent_hugepage/defrag
sudo grep -q -F 'transparent_hugepage=never' /etc/default/grub || echo 'transparent_hugepage=never' >> /etc/default/grub

# Install updates
sudo apt-get -y update

# Modified tcp keepalive according to https://docs.mongodb.org/ecosystem/platforms/windows-azure/
sudo bash -c "sudo echo net.ipv4.tcp_keepalive_time = 120 >> /etc/sysctl.conf"
sudo bash -c "sudo echo net.core.rmem_max =67108864 >> /etc/sysctl.conf"
sudo bash -c "sudo echo net.core.wmem_max =67108864 >> /etc/sysctl.conf"
sudo bash -c "sudo echo net.ipv4.tcp_rmem = 4096 87380 33554432 >> /etc/sysctl.conf"
sudo bash -c "sudo echo net.ipv4.tcp_wmem = 4096 65536 33554432 >> /etc/sysctl.conf"
sudo bash -c "sudo echo net.ipv4.tcp_congestion_control=htcp >> /etc/sysctl.conf"
sudo bash -c "sudo echo net.ipv4.tcp_mtu_probing=1 >> /etc/sysctl.conf"

#Install Mongo DB
sudo apt-get install -y mongodb-enterprise=3.2.10 mongodb-enterprise-server=3.2.10 mongodb-enterprise-shell=3.2.10 mongodb-enterprise-mongos=3.2.10 mongodb-enterprise-tools=3.2.10

echo "mongodb-enterprise hold" | sudo dpkg --set-selections
echo "mongodb-enterprise-server hold" | sudo dpkg --set-selections
echo "mongodb-enterprise-shell hold" | sudo dpkg --set-selections
echo "mongodb-enterprise-mongos hold" | sudo dpkg --set-selections
echo "mongodb-enterprise-tools hold" | sudo dpkg --set-selections
log "mongo install successfull"

# this to bind to all ip addresses
sudo sed -i -e 's/bindIp: 127.0.0.1/bindIp: 0.0.0.0/g' /etc/mongod.conf

}

log "raid exec - start"


configureraid() { 

log "configureraid start"
	sudo rm -rf /tmp/raid*
	cd /tmp 
	sudo apt-get install wget
	log "wget install successfull"
	sudo wget -d -o /var/log/wgetlog.log https://cemongovmsname.blob.core.windows.net/templates/raid.sh
	log "sleep after downloading the raid script"
	sleep 3m
	log "after 3mins sleep"
	if [ -f /tmp/raid.sh ]; then
		log "raid script exists"
		sudo bash /tmp/raid.sh
		if [ $? -eq 0 ]; then 
		log "raid.sh execution successfull"
				sed -i 's/disk1//' /etc/fstab 
				log "sed -i successfull"
				umount /var/lib/mongodb/disk1 
				log "umount successfull"
				mount /dev/md0 /var/lib/mongodb	
				log "mount successfull"
		log "raid execution successfull"
		fi
		
	else	
		log "raid execution failed"
	
	fi
}	

configureraid

install_mongodb

#create users
mongo <<EOF
use admin
db.createUser({user:"mongowonderware",pwd:"mongowonderware123",roles:[{role: "userAdminAnyDatabase", db: "admin" },{role: "readWriteAnyDatabase", db: "admin" },{role: "root", db: "admin" }]})
exit
EOF
if [ $? -eq 0 ];then
    echo "mongo user added succeefully." >> /var/log/mongolog.log
else
    echo "mongo user added failed!" >> /var/log/mongolog.log
fi

echo "Stoping mongodb" >> /var/log/mongolog.log
sudo service mongod stop
echo "starting mongodb" >> /var/log/mongolog.log
sudo service mongod start
echo "initiate replSetName " >> /var/log/mongolog.log
sudo sed -i -e 's/#replication:/replication:\n replSetName: "rs0"/g' /etc/mongod.conf


log "executing mongod status" 
sudo service mongod status >> /var/log/mongolog.log
# This is required to sleep before executing replication script
sudo service mongod start
sudo sleep 300

sudo service mongod status >> /var/log/mongolog.log
log "executing mongo shell start after sleep " 

log "Authenticating the user " 

mongo<<EOF
use admin
db.auth("mongowonderware", "mongowonderware123")
config ={_id:"rs0",members:[{_id:0,host:"${dnsname}.${inputlocation}.cloudapp.azure.com:27017"}]}
rs.initiate(config)
exit
EOF
if [ $? -eq 0 ];then
    log "replica set initiation succeeded."
else
	sudo service mongod status >> /var/log/mongolog.log
    log "replica set initiation failed!" 
fi

# The below script is for creation of replication
log "creating replication on secondary nodes "
sudo mongo --eval "printjson(rs.add('${dnsname}secondary0.${inputlocation}.cloudapp.azure.com:27017'))" --quiet >> /var/log/mongolog.log
sudo mongo --eval "printjson(rs.add('${dnsname}secondary1.${inputlocation}.cloudapp.azure.com:27017'))" --quiet >> /var/log/mongolog.log


#sudo mongo --eval "printjson(rs.initiate({ _id: 'rs0', members: [ { _id: 0, host: '${dnsname}.${inputlocation}.cloudapp.azure.com:27017' } ] }))" --quiet >> /var/log/mongolog.log

log "executing mongo shell end "





