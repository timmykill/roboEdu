#!/bin/sh


retrieve_ip() {
	jq -r ".resources[] | select(.name == \"myVps\") | .instances[].attributes.ipv4_address" $TFSTATE
}

make_inventory() {
	printf '%s ansible_user=root ansible_ssh_private_key_file="%s"\n' `retrieve_ip` $PRIV_KEY > $INVENTORY
	logd inventory creato
}

logd() {
	TIMESTAMP=$(date -Iseconds)
	echo $TIMESTAMP - $@
}

wait_machines() {
	ip=$(retrieve_ip)
	logd "aspetto l'ip $ip"
	# Reset the saved keys
	set +e
	ssh-keygen -R "$ip" 1>/dev/null 2>/dev/null
	set -e
	echo -n "waiting"
	for WAITED_SECONDS in $(seq 0  120); do
		if ssh -q -n -i "$PRIV_KEY" \
				-o PasswordAuthentication=no \
				-o StrictHostKeyChecking=no "root@$ip" 'true'; then
			echo -e '\n\n'
			logd "Success! $ip is ready."
			break
		else
			echo -n "."
			sleep 1
		fi
	done
	echo ""
	sleep 10
}


screenshot() {
	counter=$1
	id=$2
	end=$3
	tempo=$(printf '(%s - 300)  - %s\n' `date -d $end '+%s'` `date '+%s'` | bc) # no screenshot gli ultimi 15 minuti
	while test $tempo -gt 0; do
		ssh -i $PRIV_KEY -o StrictHostKeyChecking=no root@`retrieve_ip` 'DISPLAY=:99 import -window root /root/yolo.png'
		scp -i $PRIV_KEY -o StrictHostKeyChecking=no root@`retrieve_ip`:/root/yolo.png "$ROOT/screencaps/$NOME_CORSO-$ANNO-$id-$counter.png"
		sleep 60
		tempo=$(printf '(%s - 300)  - %s\n' `date -d $end '+%s'` `date '+%s'` | bc) 
	done
	rm "$ROOT/screencaps/$NOME_CORSO-$ANNO-$id-$counter.png"
}

record_start() {
	link=$1
	id=$2
	counter=$3

	# create private key
	set +e
	echo 'n' | ssh-keygen -N "" -q -f $PRIV_KEY
	set -e
	
	# make terraform do stuff
	cd ./terraform
	terraform init
	terraform apply -var="anno=$ANNO" -var="corso=$NOME_CORSO" -var="id=$id" -var="counter=$counter" -state $TFSTATE -auto-approve
	cd $ROOT
	
	make_inventory
	wait_machines

	ssh-keygen -R `retrieve_ip`
	ansible-playbook -i $INVENTORY ${ROOT}/ansible/playbook.yml --extra-vars "link=$link test=$PUPTEST"
}

record_stop() {
	counter=$1
	id=$2
	
	ssh -i $PRIV_KEY root@`retrieve_ip` 'killall -INT ffmpeg'
	sleep 10s #in case ffmpeg needed this
	logd Lezione finita, inizio a scaricarla
	scp -i $PRIV_KEY -o StrictHostKeyChecking=no root@`retrieve_ip`:/home/yolo/reg.mkv "$ROOT/regs/$NOME_CORSO-$ANNO-${id}_$(date '+%y%m%d')_$counter.mkv"
	logd Lezione scaricata 
	cd terraform
	terraform destroy -var="anno=$ANNO" -var="corso=$NOME_CORSO" -var="id=$id" -var="counter=$counter" -state $TFSTATE -auto-approve
	cd $ROOT
}

wait_and_record() {
	#parse string
	counter=$1; shift
	start=$1; shift
	end=$1; shift
	teams=$1; shift
	id=$1; shift
	note=$1; shift
	nome="$@"

	if test -n "$FILTER_CORSO" && ! (echo "$FILTER_CORSO_STRING" | grep $id > /dev/null); then
		logd skipped corso $id - not corso $FILTER_CORSO_STRING
		exit
	fi
	if test -n "$FILTER_NOTE" -a $note = "_${FILTER_NOTE_STRING}_"; then
		logd skipped note $FILTER_NOTE_STRING
		exit
	fi

	#make variables
	PRIV_KEY=${ROOT}/secrets/ssh/$NOME_CORSO-$ANNO-$id-$counter-key
	NOME_MACCHINA=$NOME_CORSO-$ANNO-$id-$counter-client
	INVENTORY="${ROOT}/ansible/inventory/$NOME_CORSO-$ANNO-$id-$counter.ini"
	TFSTATE="${ROOT}/terraform/states/$NOME_CORSO-$ANNO-$id-$counter.tfstate"
	export ANSIBLE_HOST_KEY_CHECKING="False"
		
	seconds_till_start=$(printf '%s - (%s + 600)\n' `date -d $start '+%s'` `date '+%s'` | bc)
	link_goodpart=$(echo $teams | grep -oE 'meeting_[^%]+')
	link="https://teams.microsoft.com/_\#/pre-join-calling/19:${link_goodpart}@thread.v2"
	seconds_till_end=$(printf '(%s + 600)  - %s\n' `date -d $end '+%s'` `date '+%s'` | bc)

	if test $seconds_till_end -lt 0; then
		logd skipping $nome - alredy ended
		exit
	fi
	
	logd waiting for $seconds_till_start secondi
	logd per lezione: $nome - $id
	test $seconds_till_start -gt 0 && sleep $seconds_till_start
	record_start $link $id $counter


	seconds_till_end=$(printf '(%s + 600)  - %s\n' `date -d $end '+%s'` `date '+%s'` | bc)
	logd waiting for $seconds_till_end secondi
	logd per lezione: $nome - $id

	screenshot $counter $id $end &
	sleep $seconds_till_end
	record_stop $counter $id

	logd tutto finito
	
	#remove created files:
	rm $PRIV_KEY $INVENTORY $TFSTATE
}

destroy_all() {
	set +e
	#get piano for today
	oggi=$(date '+%Y-%m-%d')
	counter=0
	kill -TERM -$(cat $ROOT/logs_and_pid/$NOME_CORSO-$ANNO.pid)
	rm $ROOT/logs_and_pid/$NOME_CORSO-$ANNO.pid
	curl -s "https://corsi.unibo.it/laurea/$NOME_CORSO/orario-lezioni/@@orario_reale_json?anno=$ANNO&curricula=&start=$oggi&end=$oggi" | jq -r '.[] | .cod_modulo' |\
		while read line; do
			counter=$(($counter + 1))
			id=$line
			# destroy terraform stuff
			TFSTATE="${ROOT}/terraform/states/$NOME_CORSO-$ANNO-$id.tfstate"
			cd terraform
			terraform destroy -var="anno=$ANNO" -var="corso=$NOME_CORSO" -var="id=$id" -var="counter=$counter" -state $TFSTATE -auto-approve
			cd $ROOT
			# remove files
			PRIV_KEY=${ROOT}/secrets/ssh/$NOME_CORSO-$ANNO-$id-$counter-key
			INVENTORY="${ROOT}/ansible/inventory/$NOME_CORSO-$ANNO-$id.ini"
			rm $PRIV_KEY $INVENTORY
			rm $ROOT/logs_and_pid/$NOME_CORSO-${ANNO}_${id}_$(date '+%y%m%d')_$counter.log
			rm $ROOT/logs_and_pid/$NOME_CORSO-$ANNO-$counter.pid
		done 
		exit

}

show_help() {
	echo "Usage: $0 [-d] <nomecorso> <anno> [id]"
	echo -h help
	echo -d destroy
	echo -l localhost
	echo "-v verbose (keep logs)"
	echo "-f filter [id] //this is a positive filter, it will record just that corso" 
	echo "-n filter [note] //this is a negative filter, it will skip selected note" 
	echo "-m 'timeStart timeEnd URL ID' //this records manually from a teams meeting on the day it runs"
	exit
}

manual(){
	# M substitutes counter to specify that it's a manual recording
	counter="M"
	timeStart=$1 
	timeEnd=$2
	url=$3
	ID=$4
	wait_and_record $counter ${oggi}T$1 ${oggi}T$2 $3 $4 __ $NOME_CORSO $ANNO > $ROOT/logs_and_pid/$NOME_CORSO-${ANNO}_${ID}_$(date '+%y%m%d')_$counter.log 2>&1 &
	echo $! > $ROOT/logs_and_pid/$NOME_CORSO-$ANNO-$counter.pid
	set +e
	wait $(cat $ROOT/logs_and_pid/$NOME_CORSO-$ANNO-$counter.pid)
	set -e
	echo $NOME_CORSO-$ANNO-$counter ha finito
	test -z VERBOSE && rm $ROOT/logs_and_pid/${NOME_CORSO}-${ANNO}_*_$(date '+%y%m%d')_${counter}.log
	rm $ROOT/logs_and_pid/$NOME_CORSO-$ANNO-$counter.pid
	set +e
	rm -f $ROOT/screencaps/$NOME_CORSO-$ANNO-*-$counter.png
	set -e
	rm $ROOT/logs_and_pid/$NOME_CORSO-$ANNO.pid
	exit
}

############### 
# ENTRY POINT #
###############

set -e

if test $# -lt 2; then
	show_help
fi

while getopts ":h:d:l:v:m::f::n:" opt; do
	case $opt in
		"h") show_help; exit;;
		"d") echo "destroy" ; shift; DESTROY=true ;;
		"l") echo "localhost" ; shift; LOCALHOST=true ;;
		"v") echo "verbose" ; shift; VERBOSE=true ;;
		"f") FILTER_CORSO=true; FILTER_CORSO_STRING=$OPTARG; shift; shift;;
		"n") FILTER_NOTE=true; FILTER_NOTE_STRING=$OPTARG; shift; shift;;
		"m") MANUAL=true; MANUAL_STRING=$OPTARG; shift; shift;;
	esac
done

NOME_CORSO=$1
ANNO=$2
ROOT=$(pwd)
PUPTEST="teamsTest"

test -n "$DESTROY" && destroy_all

#check if pid alredy exists

#get piano for today
oggi=$(date '+%F')
counter=0

# manual recording
test -n "$MANUAL" && manual $MANUAL_STRING

echo $$ > $ROOT/logs_and_pid/$NOME_CORSO-$ANNO.pid

# no process substitution in P0SIX sh
tmpdir=$(mktemp -d)
exec 3> $tmpdir/fd3

curl -s "https://corsi.unibo.it/laurea/$NOME_CORSO/orario-lezioni/@@orario_reale_json?anno=$ANNO&curricula=&start=$oggi&end=$oggi" | jq -r '.[] | .start + " " + .end + " " + .teams + " " + .cod_modulo + " _" + .note + "_ " + .title' > $tmpdir/fd3
while read line; do
	ID=$(echo $line | cut -d' ' -f4) # sucky hack
	counter=$(($counter + 1))
	wait_and_record $counter $line > $ROOT/logs_and_pid/$NOME_CORSO-${ANNO}_${ID}_$(date '+%y%m%d')_$counter.log 2>&1 &
	echo $! > $ROOT/logs_and_pid/$NOME_CORSO-$ANNO-$counter.pid
done < $tmpdir/fd3

rm -r $tmpdir

while test $counter -gt 0; do
	set +e
	wait $(cat $ROOT/logs_and_pid/$NOME_CORSO-$ANNO-$counter.pid)
	set -e
	echo $NOME_CORSO-$ANNO-$counter ha finito
	test -z VERBOSE && rm $ROOT/logs_and_pid/$NOME_CORSO-${ANNO}_*_$(date '+%y%m%d')_$counter.log
	rm $ROOT/logs_and_pid/$NOME_CORSO-$ANNO-$counter.pid
	set +e
	rm -f $ROOT/screencaps/$NOME_CORSO-$ANNO-*-$counter.png
	set -e
	counter=$(($counter - 1))
done
rm $ROOT/logs_and_pid/$NOME_CORSO-$ANNO.pid
