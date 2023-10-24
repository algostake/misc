#!/usr/bin/bash
# Copyright 2023, Algostake Ltd
# SPDX-License-Identifier: Apache-2.0
#
# polygon_scrape_klingons.sh
#
# Scrapes peer ids for nodes sending unsolicited pooled transaction packets
# from node log and issues admin rpc requests to remove them as peers.
#
URL='http://127.0.0.1:8545'	# local node RPC URL; admin api must be enabled
declare -a BANNED_PEER_IDS=(
    # banned peer ids here
)
declare -i JID=0
declare -i TIMESTAMPED=0

function tail_logs() {
	# output recent lines from server log, edit to suit local installation
	tail -n10000 SERVER_LOG_FILE
}

function json_rpc_body() {
    local method="${1}"
    shift 1
    local message='{"jsonrpc":"2.0","id":"'"${JID}"'","method":"'"${method}"'"'
    if (($#)); then
	local params=("${@}")
	params=("${params[@]/#/\"}")
	params=("${params[@]/%/\"}")
	local IFS=','
	message+=',"params":['"${params[*]}"']'
    fi
    message+='}'
    echo "${message}"
    let JID+=1
}

function json_rpc_request() {
	local HDR='content-type:application/json'
	curl -s -H "${HDR}" -d "$(json_rpc_body "$@")" "${URL}"
}

function scrape_peer_ids_from_logs() {
	egrep 'Unexpected transaction delivery *peer=[0-9a-f]{64}' |
	sed 's/.*peer=//' |
	uniq |
	sort |
	uniq
}

function get_peer_ids_enodes() {
	json_rpc_request admin_peers |
	jq -r '.result[]|(.id,.enode)' |
	paste - - |
	sort
}

for enode in $(join -j1 -o2.2 -t$'\t' \
		    <(cat <(tail_logs | scrape_peer_ids_from_logs) \
			  <(echo "${BANNED_PEER_IDS[@]}") |
			  sort | uniq) \
		    <(get_peer_ids_enodes)); do
    if ((!TIMESTAMPED)); then
	date --rfc-3339=ns
	TIMESTAMPED=1
    fi
    remove_result="$(json_rpc_request admin_removePeer "${enode}" | jq -c .)"
    echo "${enode}: ${remove_result}"
done
