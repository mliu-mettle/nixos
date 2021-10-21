assume() {
  arn=$1
  aws_sts=$(aws sts assume-role --role-arn $arn --role-session-name "$(whoami)")
  export AWS_ACCESS_KEY_ID=$(echo $aws_sts | jq -r '.Credentials.AccessKeyId')
  export AWS_SECRET_ACCESS_KEY=$(echo $aws_sts | jq -r '.Credentials.SecretAccessKey')
  export AWS_SESSION_TOKEN=$(echo $aws_sts | jq -r '.Credentials.SessionToken')
}

awshosts() {
  ENV=$1
  NAME=$2
  aws ec2 describe-instances --profile $ENV --output table \
    --filters "Name=tag:Name,Values=$NAME" "Name=instance-state-name,Values=[running,pending,shutting-down,stopping]" \
    --query "Reservations[].Instances[].{AZ:Placement.AvailabilityZone,ID:InstanceId,Type:Tags[?Key=='Name']|[0].Value,IP:PrivateIpAddress,InstanceType:InstanceType,Launched:LaunchTime,State:State.Name} | sort_by(@, &Type)"
}

clearssh() {
  unset SSH_AUTH_SOCK
  eval $(ssh-agent)
}

o_creds() {
  export ONELOGIN_CLIENT_ID=$(eval pass mettle/onelogin/cli/id)
  export ONELOGIN_CLIENT_SECRET=$(eval pass mettle/onelogin/cli/secret)
  export ONELOGIN_OAPI_URL=https://api.eu.onelogin.com
}

gh_creds() {
  export GITHUB_TOKEN=$(eval pass mettle/github/pat)
}

ib_creds() {
  export IB_USER=$(eval pass ib/user)
  export IB_PASS=$(eval pass ib/pass)
}

branch() {
  git stash
  git checkout master
  git pull
  git checkout -b $1
  git stash pop
}

gang() {
  firefox "https://gangway.oidc.$1-mettle.co.uk/login"
  sleep 5
  firefox "https://gangway.oidc.$1-mettle.co.uk/kubeconf"
  sleep 5
  mv ~/Downloads/kubeconf ~/.kube/mettle-$1
  chmod go-r ~/.kube/mettle-$1
  kenv $1
}

kenv() {
  export KUBECONFIG=~/.kube/mettle-$1
}

mon() {
  autorandr -l default --force --default
  ~/.config/polybar/launch.sh
}

clone() {
  git clone "git@github.com:eeveebank/$1.git"
}

a() {
  password=$(eval pass mettle/onelogin/password)
  image=$(eval pass onelogin/image)

  docker run --rm -it -v ~/.aws:/home/mettle/.aws --network host \
  ${image} --profile default -u $(whoami) --onelogin-password ${password}
}

ao() {
  password=$(eval pass mettle/onelogin/password)
  image=$(eval pass onelogin/image)

  docker run --rm -it -v ~/.aws:/home/mettle/.aws --network host \
  ${image} --profile default -u $(whoami) --onelogin-password ${password} --onelogin-app-id 382920
}

bssh() {
  export ENV="${1:-sbx}"
  export KEYNAME="${2:-id_ecdsa}"

  #------------------------------------------------------------------------------
  # Boundary Auth
  #------------------------------------------------------------------------------
  export BOUNDARY_ADDR=https://boundary.platform.${ENV}-mettle.co.uk BOUNDARY_CLI_FORMAT=json
  export BOUNDARY_SCOPE_ID=$(boundary scopes list -scope-id=global | jq -r '.items[].id')
  export BOUNDARY_AUTH_METHOD_ID=$(boundary auth-methods list --filter '"onelogin" in "/item/name"' | jq -r '.items[].id')
  export BOUNDARY_TOKEN=$(boundary authenticate oidc | jq -r '.item.attributes.token')

  #------------------------------------------------------------------------------
  # List Available Targets
  #------------------------------------------------------------------------------
  select TARGETNAME in $(boundary targets list -recursive | jq -r '.items[].name' | sort); do if [ -n "$TARGETNAME" ]; then break; fi; done

  #------------------------------------------------------------------------------
  # Vault Auth - To Enable Signing of SSH Certificate
  #------------------------------------------------------------------------------
  export VAULT_SKIP_VERIFY=true
  boundary connect -exec vault -target-scope-name=platform -target-name=vault_ecs -listen-port=8200 -- login -method=oidc role=platform

  #------------------------------------------------------------------------------
  # Sign Cert & SSH onto target via Boundary
  #------------------------------------------------------------------------------
  boundary connect -exec vault -target-scope-name=platform -target-name=vault_ecs -listen-port=8200 \
           -- write -field=signed_key ssh/sign/client public_key=@$HOME/.ssh/${KEYNAME}.pub | tail -n +2 > ~/.ssh/${KEYNAME}-cert.pub
  boundary connect ssh -target-scope-name=platform -target-name="${TARGETNAME}"
}