#!/bin/bash

set -eu

echo "brktizing ami..."

source_ami=$(cat stock-ami/ami)
brktized_ami_file=ami/ami

regex='^(\-\-[A-Za-z\-]+ "?[.0-9A-Za-z=\-]+"? ?)+$'  # matches one or more of --a-flag "letters, number or =.-"

echo "Installing aws-cli & brkt-cli"
pip install awscli 1>/dev/null
pip install brkt-cli 1>/dev/null

curl -L -s -k -o jq "https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64"
chmod +x jq

echo "Getting token from https://api.$SERVICE_DOMAIN:443"
auth_cmd="brkt auth --email $EMAIL --password $PASSWORD --root-url https://api.$SERVICE_DOMAIN:443"
echo "Running command: export BRKT_API_TOKEN=\$(brkt auth --email $EMAIL --password *** --root-url https://api.$SERVICE_DOMAIN:443)"
export BRKT_API_TOKEN=$($auth_cmd)

echo -e "Wrapping stemcell image $source_ami...\n Verifying arguments..."
if [[ -z "$WRAP_ARGS" ]]
then
    echo "No arguments given!"
elif ! [[ $WRAP_ARGS =~ $regex ]]
then
    echo "Arguments: \"$WRAP_ARGS\" does not follow pattern '--flag \"[A-Za-z0-9\-=.]+\"'"
    exit 1
fi

cmd="brkt aws wrap-guest-image --service-domain $SERVICE_DOMAIN --region $REGION --metavisor-version $METAVISOR_VERSION $WRAP_ARGS $source_ami"
echo "Running command: $cmd"
$cmd | tee wrap.log &

# Wait for all background tasks to complete
wait
instance_id=$(tail -1 wrap.log | awk '{print $1}')
sleep 20

instance_ami="$(aws ec2 create-image --region $REGION --instance-id $instance_id --name "$source_ami wrapped by $METAVISOR_VERSION $(python -c 'import time; print time.strftime(" -- %H-%M-%S")')" | ./jq -r ".ImageId")"
if ! [[ $instance_ami =~ ^ami- ]]; then
    echo "Wrapping failed in region $REGION"
    exit 1
fi
echo "Wrapped ami: $instance_ami"
echo "Deleting instances..."
aws ec2 terminate-instances --region $REGION --instance-ids $instance_id

echo "$instance_ami" > $brktized_ami_file