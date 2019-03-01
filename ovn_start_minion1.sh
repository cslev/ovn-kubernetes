#!/bin/bash

source ovn_config.sh
source minion1_args.sh

echo -ne "${orange}Create necessary directories if not exist...${none}"
sudo mkdir -p $OVN_PID_DIR
sudo mkdir -p $OVN_DB_FILE_DIR
sudo mkdir -p $OVN_LOG_DIR
sudo mkdir -p $OVN_SOCKET_DIR
sudo mkdir -p /var/run/openvswitch
echo -e "${green}[DONE]${none}"

echo -ne "${orange}Create OVS database...${none}"
sudo ovsdb-tool create $OVN_DB_FILE_DIR/conf.db  $OVN_DB_SCHEMA_DIR/vswitch.ovsschema
echo -e "${green}[DONE]${none}"

#echo -ne "${orange}Create OVN databases for northbound and southbound${none}"
#sudo ovsdb-tool create $OVN_DB_FILE_DIR/ovnnb_db.db $OVN_DB_SCHEMA_DIR/ovn-nb.ovsschema
#sudo ovsdb-tool create $OVN_DB_FILE_DIR/ovnsb_db.db $OVN_DB_SCHEMA_DIR/ovn-sb.ovsschema
#echo -e "${green}[DONE]${none}"

echo -e "${orange}Create DB_SOCK for the databases"
echo -ne "${orange} -> OVS..."
sudo ovsdb-server --remote=punix:$OVN_SOCKET_DIR/db.sock \
                  --remote=db:Open_vSwitch,Open_vSwitch,manager_options \
                  --pidfile --detach
echo -e "${green}[DONE]${none}"

#echo -ne "${orange} -> OVN northbound..."
#sudo ovsdb-server --detach --monitor -vconsole:off \
#             --log-file=$OVN_LOG_DIR/ovsdb-server-nb.log \
#             --remote=punix:$OVN_SOCKET_DIR/ovnnb_db.sock \
#             --pidfile=$OVN_PID_DIR/ovnnb_db.pid \
#             --remote=db:OVN_Northbound,NB_Global,connections \
#             --remote=ptcp:6641:$CENTRAL_IP \
#             --unixctl=ovnnb_db.ctl \
#             --private-key=db:OVN_Northbound,SSL,private_key \
#             --certificate=db:OVN_Northbound,SSL,certificate \
#             --ca-cert=db:OVN_Northbound,SSL,ca_cert \
#             $OVN_DB_FILE_DIR/ovnnb_db.db
#echo -e "${green}[DONE]${none}"

#echo -ne "${orange} -> OVN southbound..."
#sudo ovsdb-server --detach --monitor -vconsole:off \
#             --log-file=$OVN_LOG_DIR/ovsdb-server-sb.log \
#             --remote=punix:$OVN_SOCKET_DIR/ovnsb_db.sock \
#             --pidfile=$OVN_PID_DIR/ovnsb_db.pid \
#             --remote=db:OVN_Southbound,SB_Global,connections \
#             --remote=ptcp:6642:$CENTRAL_IP \
#             --unixctl=ovnsb_db.ctl \
#             --private-key=db:OVN_Southbound,SSL,private_key \
#             --certificate=db:OVN_Southbound,SSL,certificate \
#             --ca-cert=db:OVN_Southbound,SSL,ca_cert \
#             $OVN_DB_FILE_DIR/ovnsb_db.db
#echo -e "${green}[DONE]${none}"

echo
echo -e "${orange}Starting pure OVS...${none}"
sudo ovs-vsctl --no-wait \
               init
sudo ovs-vswitchd unix:$OVN_SOCKET_DIR/db.sock \
                  --pidfile=$OVN_PID_DIR/ovsvswitchd.pid \
                  --detach
echo -e "${green}[DONE]${none}"

echo -e "${orange}Getting SYSTEM_ID from /sys/class/dmi/id/product_id...${none}"
SYSTEM_ID=$(sudo cat /sys/class/dmi/id/product_uuid)
echo -e "${green}[DONE]${none}"


echo -e "${orange}Setting SYSTEM_ID in OVS DB...${none}"
sudo ovs-vsctl set Open_vSwitch . external_ids:system-id="${SYSTEM_ID}"
echo -e "${green}[DONE]${none}"

#echo
#echo -e "${orange}Starting ovn northd...${none}"
#sudo $OVN_CTL start_northd
#echo -e "${green}[DONE]${none}"

#echo -e "${orange}Starting ovn controller...${none}"
#sudo $OVN_CTL start_controller
#echo -e "${green}[DONE]${none}"


#echo -e "${orange}Create OVNKUBE networking${none}"
#sudo kubectl create -f  ovnkube-rbac.yaml
#echo -e "${green}[DONE]${none}"

# getting secret for the freshly created ovnkube
#SECRET=`kubectl get secret | grep ovnkube | awk '{print $1}'`
#TOKEN=`kubectl get secret/$SECRET -o yaml |grep "token:" | cut -f2  -d ":" | sed 's/^  *//' | base64 -d`
#echo $TOKEN > token

TOKEN=$(cat token)
if [ -z "$TOKEN" ]
then
  echo -e "${red}variable TOKEN does not exists! Get token of ovnkube from server and save as a text file called 'token' here!${none}"
  echo -e "Example: kubectl get secret|grep ovnkube"
  exit -1
else
  echo -e "${orange}Starting ovn-controller...${none}"
  sudo ovn-controller
  echo -e "${orange}Starting OVNKUBE...${none}"
  sudo ovnkube -loglevel=8 \
               -logfile="${OVN_LOG_DIR}/ovnkube.log" \
               -k8s-apiserver="https://$CENTRAL_IP:6443" \
               -k8s-cacert=/etc/kubernetes/pki/ca.crt \
               -init-node=$NODE_NAME \
               -nodeport \
               -nb-address="tcp://${CENTRAL_IP}:6641" \
               -sb-address="tcp://${CENTRAL_IP}:6642" \
               -k8s-token="$TOKEN" \
               -init-gateways \
               -gateway-interface=$IFNAME \
               -gateway-nexthop=$GW_IP \
               -service-cluster-ip-range=$SERVICE_IP_RANGE \
               -cluster-subnet=$POD_IP_RANGE #2>&1 &
#               -k8s-cacert=/etc/kubernetes/pki/ca.crt \
#               -gateway-localnet 2>&1 &
  sleep 2
  echo -e "${green}[DONE]${none}"
  echo -e "${green} --- FINISHED --- ${none}"

  echo -e "${green}Freshesh output log of ovnkube:${none}"

  sudo cat $OVN_LOG_DIR/ovnkube.log

  echo

fi

