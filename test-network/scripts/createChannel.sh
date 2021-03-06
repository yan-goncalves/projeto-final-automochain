#!/bin/bash

source scriptUtils.sh

CHANNEL_NAME="$1"
DELAY="$2"
MAX_RETRY="$3"
VERBOSE="$4"
: ${CHANNEL_NAME:="condominiochannel"}
: ${DELAY:="3"}
: ${MAX_RETRY:="5"}
: ${VERBOSE:="false"}

# import utils
. scripts/envVar.sh

if [ ! -d "channel-artifacts" ]; then
	mkdir channel-artifacts
fi

createChannelTx() {

	set -x
	configtxgen -profile CondominioChannel -outputCreateChannelTx ./channel-artifacts/${CHANNEL_NAME}.tx -channelID $CHANNEL_NAME
	res=$?
	{ set +x; } 2>/dev/null
	if [ $res -ne 0 ]; then
		fatalln "Failed to generate channel configuration transaction..."
	fi

}

createAncorPeerTx() {

	for orgmsp in MontadoraMSP SistemistaMSP; do

	infoln "Generating anchor peer update transaction for ${orgmsp}"
	set -x
	configtxgen -profile CondominioChannel -outputAnchorPeersUpdate ./channel-artifacts/${orgmsp}anchors.tx -channelID $CHANNEL_NAME -asOrg ${orgmsp}
	res=$?
	{ set +x; } 2>/dev/null
	if [ $res -ne 0 ]; then
		fatalln "Failed to generate anchor peer update transaction for ${orgmsp}..."
	fi
	done
}

createChannel() {
	setGlobals Montadora
	# Poll in case the raft leader is not set yet
	local rc=1
	local COUNTER=1
	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
		sleep $DELAY
		set -x
		peer channel create -o localhost:6130 -c $CHANNEL_NAME --ordererTLSHostnameOverride orderer0.montadora.ciag -f ./channel-artifacts/${CHANNEL_NAME}.tx --outputBlock ./channel-artifacts/${CHANNEL_NAME}.block --tls --cafile $ORDERER_CA >&log.txt
		res=$?
		{ set +x; } 2>/dev/null
		let rc=$res
		COUNTER=$(expr $COUNTER + 1)
	done
	cat log.txt
	verifyResult $res "Channel creation failed"
	successln "Channel '$CHANNEL_NAME' created"
}

# queryCommitted ORG
joinChannel() {
  ORG=$1
  setGlobals $ORG $2
	local rc=1
	local COUNTER=1
	## Sometimes Join takes time, hence retry
	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
    sleep $DELAY
    set -x
    peer channel join -b ./channel-artifacts/$CHANNEL_NAME.block >&log.txt
    res=$?
    { set +x; } 2>/dev/null
		let rc=$res
		COUNTER=$(expr $COUNTER + 1)
	done
	cat log.txt
	verifyResult $res "After $MAX_RETRY attempts, peer0.org${ORG} has failed to join channel '$CHANNEL_NAME' "
}

updateAnchorPeers() {
  ORG=$1
  setGlobals $ORG
	local rc=1
	local COUNTER=1
	## Sometimes Join takes time, hence retry
	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
    sleep $DELAY
    set -x
		peer channel update -o localhost:6130 --ordererTLSHostnameOverride orderer0.montadora.ciag -c $CHANNEL_NAME -f ./channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx --tls --cafile $ORDERER_CA >&log.txt
    res=$?
    { set +x; } 2>/dev/null
		let rc=$res
		COUNTER=$(expr $COUNTER + 1)
	done
	cat log.txt
  verifyResult $res "Anchor peer update failed"
  successln "Anchor peers updated for org '$CORE_PEER_LOCALMSPID' on channel '$CHANNEL_NAME'"
  sleep $DELAY
}

verifyResult() {
  if [ $1 -ne 0 ]; then
    fatalln "$2"
  fi
}

FABRIC_CFG_PATH=${PWD}/configtx

## Create channeltx
infoln "Generating channel create transaction '${CHANNEL_NAME}.tx'"
createChannelTx

## Create anchorpeertx
infoln "Generating anchor peer update transactions"
createAncorPeerTx

FABRIC_CFG_PATH=$PWD/../config/

## Create channel
infoln "Creating channel ${CHANNEL_NAME}"
createChannel

## Join all the peers to the channel
infoln "Join peer0.montadora to the channel..."
joinChannel Montadora 0
infoln "Join peer1.montadora to the channel..."
joinChannel Montadora 1
infoln "Join peer2.montadora to the channel..."
joinChannel Montadora 2
infoln "Join peer0.sistemista to the channel..."
joinChannel Sistemista 0
infoln "Join peer1.sistemista to the channel..."
joinChannel Sistemista 1
infoln "Join peer2.sistemista to the channel..."
joinChannel Sistemista 2

## Set the anchor peers for each org in the channel
infoln "Updating anchor peers for Montadora..."
updateAnchorPeers Montadora
infoln "Updating anchor peers for Sistemista..."
updateAnchorPeers Sistemista

successln "Channel successfully joined"

exit 0
