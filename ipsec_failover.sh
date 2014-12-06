#!/bin/bash
#########################################################################
# IPSEC FAILOVER TRANSITION SCRIPT FOR EDGEOS WAN LOAD BALANCING
#########################################################################

#########################################################################
# CUSTOMIZE THE FOLLOWING VARIABLES TO YOUR ENVIRONMENT
# IF USING DHCP WAN, LIST DHCP (ALL CAPS) AS IP1/IP2 RESPECTIVELY
# MAKE SURE WAN1 = IP1 AND WAN2 = IP2
# YOU CAN LIST AS MANY PEERS AS NEEDED MAKE SURE THEY HAVE THE SAME NAME
# AS YOUR ROUTER CONFIG
#########################################################################

#####
# PRIMARY WAN, SHOULD BE THE ONE YOU CONFIGURED IN YOUR IPSEC CONFIG
WAN1="eth0"
#####
# FAILOVER WAN, SHOULD BE THE ONE LISTED AS YOUR FAILOVER IN LOAD BALANCING
WAN2="eth1"
#####
# THE IP ADDRESS (OR DHCP) OF WAN1
IP1="DHCP"
#####
# THE IP ADDRESS (OR DHCP) OF WAN2
IP2="2.2.2.2"
#####
# IPSEC PEERS KEEP BETWEEN () AND SEPARATE WITH A SINGLE SPACE
# CAN USE A MIXTURE OF DOMAIN NAME AND IP ADDRESS
# MUST MATCH YOUR IPSEC PEER CONFIGURATION
PEERS=(site1.domain.com 3.3.3.3 site3.domain.com 5.5.5.5)

#####
# CHANGE IF YOU WANT YOUR LOGFILE IN A DIFFERENT LOCATION
LOGFILE="/var/log/ipsec_failover"
#####
# SET TO FALSE IF YOU DONT WANT A LOG
USELOG=true

#####
# CHANGE IF YOU WANT YOUR DEBUG FILE IN A DIFFERENT LOCATION
DEBUGFILE="/var/log/ipsec_failover_debug"
#####
# SET TO TRUE IF YOU WANT DEBUG TURNED ON, WILL ONLY OUTPUT COMMANDS TO DEBUG 
# FILE INSTEAD OF MAKING CONFIG CHANGES
DEBUG=true


#################################################################
# DONT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU ARE DOING
#################################################################
GROUP=$1
INTERFACE=$2
STATUS=$3
is_dhcp=
is_old_dhcp=

source /opt/vyatta/etc/functions/script-template
OPRUN=/opt/vyatta/bin/vyatta-op-cmd-wrapper

TS=$(date +"%Y-%m-%d %T")
log_debug(){
  echo "${TS} :[DEBUG]: $1">>$DEBUGFILE
}
log_error(){
  if [ $DEBUG ]; then
    echo "${TS} :[DEBUG][ERROR]: $1 LB-Group: $GROUP  Interface: $INTERFACE ($STATUS)">>$DEBUGFILE
  else
    if [ $USELOG ] ; then
      echo "${TS} :[ERROR]: $1 LB-Group: $GROUP  Interface: $INTERFACE ($STATUS)">>$LOGFILE   
    fi 
  fi
}

log_status(){
  if [ $DEBUG ]; then  
    echo "${TS} :[DEBUG][STATUS]: $1 LB-Group: $GROUP Interface: $INTERFACE">>$DEBUGFILE
  else
    if [ $USELOG ] ; then
      echo "${TS} :[STATUS]: $1 LB-Group: $GROUP Interface: $INTERFACE">>$LOGFILE
    fi
  fi
}

log_action(){
  if [ $DEBUG ]; then 
    echo "${TS} :[DEBUG][ACTION]: $1 $2, Change to $3 $4">>$DEBUGFILE
  else
    if [ $USELOG ] ; then
      echo "${TS} :[ACTION]: $1 $2, Change to $3 $4">>$LOGFILE
    fi
  fi
}
delete_local(){
  if [ $DEBUG ]; then
    log_debug "delete vpn ipsec site-to-site peer $1 local-address"
  else
    delete vpn ipsec site-to-sitepeer $1 local-address
  fi
}
set_local(){
  if [ $DEBUG ]; then 
    log_debug "set vpn ipsec site-to-site peer $1 local-address $2"
  else
    set vpn ipsec site-to-site peer $1 local-address $2
  fi
}
delete_dhcp(){
  if [ $DEBUG ]; then
    log_debug "delete vpn ipsec site-to-site peer $1 dhcp-interface"
  else
    delete vpn ipsec site-to-site peer $1 dhcp-interface
  fi
}
set_dhcp(){
  if [ $DEBUG ]; then
    log_debug "set vpn ipsec site-to-site peer $1 dhcp-interface $2"
  else
    set vpn ipsec site-to-site peer $1 dhcp-interface $2
  fi
}

check_dhcp(){
  if [ "$1" == "DHCP" ]; then
    echo "true"
  else 
    echo "false"
  fi
}

change_peers(){
  if [ $DEBUG ]; then
    log_debug "configure"
  else
    configure
  fi

  if [ "$1" == "$IP1" ]; then 
    old_address=$IP2
  else 
    old_address=$IP1
  fi

  is_dhcp=$( check_dhcp $1 )
  is_old_dhcp=$( check_dhcp $old_address )

  if ! [ "$is_dhcp" = true ] && ! [ "$is_old_dhcp" = true ]; then
    for(( i = 0; i < ${#PEERS[*]}; i++ )); do
      PEER=${PEERS[i]}
      set_local $PEER $1
    done
  elif [ "$is_dhcp" = true ] && ! [ "$is_old_dhcp" = true ]; then
    for(( i = 0; i < ${#PEERS[*]}; i++ )); do
      PEER=${PEERS[i]}  
      delete_local $PEER
      set_dhcp $PEER $2
    done
  elif [ "$is_dhcp" = true ] && [ "$is_old_dhcp" = true ]; then
    for(( i = 0; i < ${#PEERS[*]}; i++ )); do
      PEER=${PEERS[i]}
      set_dhcp $PEER $2
    done
  elif ! [ "$is_dhcp" = true ] && [ "$is_old_dhcp" = true ]; then
    for(( i = 0; i < ${#PEERS[*]}; i++ )); do
      PEER=${PEERS[i]}  
      delete_dhcp $PEER
      set_local $PEER $1
    done
  fi
  if [ $DEBUG ]; then
    log_debug "commit"
    log_debug "restart vpn"
  else
    commit
    $OPRUN restart vpn
  fi
}

case "$STATUS" in
  active)
    log_status active
    if [ "$INTERFACE" == "$WAN1" ]; then
      log_action $WAN1 ACTIVE $WAN1 $IP1
      change_peers $IP1 $WAN1
    fi
    ;;
  inactive)
    log_status inactive
    if [ "$INTERFACE" == "$WAN1" ]; then
      log_action $WAN1 INACTIVE $WAN2 $IP2
      change_peers $IP2 $WAN2
    fi
    ;;
  failover)
    log_status failover
    if [ "$INTERFACE" == "$WAN1" ]; then
      log_action $WAN1 FAILOVER $WAN2 $IP2
      change_peers $IP2 $WAN2
    fi
    ;;
  *)
    log_error "Unknown Status"
    ;;
esac

exit 0