#!/bin/sh

retrieve_ip() {
	jq -r ".resources[] | select(.name == \"myVps\") | .instances[].attributes.ipv4_address" $TFSTATE
}

make_inventory() {
	printf '%s ansible_user=root ansible_ssh_private_key_file="%s"\n' `retrieve_ip` $PRIV_KEY > $INVENTORY
}

wait_machines() {
	ip=$(retrieve_ip)
	# Reset the saved keys
	ssh-keygen -R "$ip" 1>/dev/null 2>/dev/null
	echo -n "[ ] Checking if $ip is ready"
	for WAITED_SECONDS in $(seq 0 "$(( $SECONDS_TO_WAIT + 1 ))" ); do
		if ssh -q -n -i "$PRIV_KEY" \
				-o PasswordAuthentication=no \
				-o StrictHostKeyChecking=no "root@$ip" 'true'; then
			echo -e "\n\n[+] Success! $ip is ready."
			break
			else
			echo -n "."
			sleep 1
		fi
	done
	echo ""
	sleep 10
}

record_start() {
	link=$1

	# make terraform do stuff
	cd ./terraform
	terraform init
	terraform apply -var="anno=$ANNO" -var="corso=$NOME_CORSO" -state $TFSTATE -auto-approve
	cd $ROOT
	
	make_inventory
	wait_machines

	# TODO template using the link
	ssh-keygen -R `retrieve_ip`
	ansible-playbook -i $INVENTORY ${ROOT}/ansible/playbook.yml --extra-vars "link=$link"
}

record_stop() {
	counter=$1
	ssh -i $PRIV_KEY root@`retrieve_ip` 'killall -INT ffmpeg'
	sleep 5
	scp -i $PRIV_KEY root@`retrieve_ip`:/root/reg.mkv $ROOT/regs/${NOME_CORSO}-${ANNO}-${ID}_${counter}.mkv
	cd terraform
	terraform destroy -var="anno=$ANNO" -var="corso=$NOME_CORSO" -state $TFSTATE -auto-approve
	cd $ROOT
}

if test $# -lt 2; then
	echo Usage: $0 '<nomecorso> <anno> [id]'
	exit
fi

NOME_CORSO=$1
ANNO=$2
ID='0'
ROOT=$(pwd)
PRIV_KEY=${ROOT}/secrets/${NOME_CORSO}-${ANNO}-${ID}-key
NOME_MACCHINA=${NOME_CORSO}-${ANNO}-${ID}-client
INVENTORY="${ROOT}/ansible/inventory/${NOME_CORSO}-${ANNO}-${ID}.ini"
TFSTATE="${ROOT}/terraform/states/${NOME_CORSO}-${ANNO}-${ID}.tfstate"
export ANSIBLE_HOST_KEY_CHECKING="False"

# create private key
echo 'y' | ssh-keygen -N "" -q -f $PRIV_KEY

#get piano for today
oggi=$(date '+%Y-%m-%d')
counter=0
curl -s "https://corsi.unibo.it/laurea/$NOME_CORSO/orario-lezioni/@@orario_reale_json?anno=$ANNO&curricula=&start=$oggi&end=$oggi" | jq -r '.[] | .start + " " + .end + " " + .teams' |\
	while read i; do
		start=$(echo $i | cut -d' ' -f1)
		end=$(echo $i | cut -d' ' -f2)
		teams=$(echo $i | cut -d' ' -f3)
		link_goodpart=$(echo $teams | grep -oE 'meeting_[^%]+')
		link="https://teams.microsoft.com/_\#/pre-join-calling/19:${link_goodpart}@thread.v2"
		record_start $link
		echo aspetto 2 minuti
		sleep 2m
		record_stop
		counter=$(($counter + 1))
	done 

#TODO delete all the junk left behind
