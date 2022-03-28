#! /bin/bash

# Generic Jupyter Cluster Manager: gjc_...
# source this file to use!

# globals
cluster_resource_key='charmers-cluster-id'

# > aws profiles

gjc_aws_profile_list(){
	aws configure list-profiles | awk '{print FNR ": " $1}'
}

gjc_aws_profile_get(){
	gjc_aws_profile_list | awk -v x=$1 'FNR == x {print $2}'
}

gjc_aws_profile_default_print(){
	echo "Current Default Profile: $AWS_DEFAULT_PROFILE"
}

gjc_aws_profile_default_set(){
	if [ "$1" = "-h" ]; then
		printf "
		Sets the default aws profile in this shell \n
		Provide an integer corresponding to those listed \n
		by each profile in the output of gjc_aws_profile_list
		"
	fi

	AWS_DEFAULT_PROFILE=$(gjc_aws_profile_get $1)
	gjc_aws_profile_default_print
}

gjc_aws_profile_default_details(){
	if [ "$1" = "-h" ]; then
		echo "Prints account details of current default profile"
	fi

	gjc_aws_profile_default_print

	aws sts get-caller-identity
}


gjc_aws_region_default_print(){
	if [ "$1" = "-h" ]; then
		ehco "Print region of current default profile"
	fi

	# aws configure get region

	# a reliable way (?) to get whatever region the CLI is using
	aws ec2 describe-availability-zones \
		--output text \
		--query 'AvailabilityZones[0].[RegionName]'
}

# > Kubectl functions

# list current contest
kb_context(){
  kubectl config current-context
}

# list all contexts and highlight current
kb_context_list_all(){
  # awkwardly, the first column is empty when not current, so first column is col name for not current
  kubectl config get-contexts | tail -n +2 | awk '{print ($1 == "*" ? FNR "-> " $2 : FNR "   " $1)}'
}

# utility ... of all contexts, return nth context (1-based)
kb_context_get(){
  # awkwardly, the first column is empty when not current, so first column is col name for not current
  kubectl config get-contexts | tail -n +2 | awk -v x=$1 'FNR == x {print ($1 == "*" ? $2 : $1 )}'
}

# macOS only
kb_context_cp(){
  kb_context_get $1 | tr -d '\n'| pbcopy
}

# set context to nth context from list_all (1-based)
kb_context_set(){
  kubectl config use-context $(kb_context_get $1)
}

# set current context to use the provided namespace as default
kb_context_default_namespace(){
  kubectl config set-context --current --namespace=$1
}

# presumes only one hub pod ... which is the case most of the time
alias kb_hubpod_get_name='kubectl get pod | awk "/hub/ {print \$1}"'


# presumes all user pods have a name that starts with "jupyter"
alias kb_pods_get_jupyter_names="kubectl get pod | awk '/^jupyter/ NR>1 {print $1}'"

alias kb_pods='kubectl get pod'

alias kb_pods_watch='kubectl get pod --watch'

# > eksctl functions

# How set a cluster name?
	# use contexts ... set a namespace early?

	# Currently ... using global $cluster_name ... FOR NOW

gjc_cluster_create(){

	echo "$(gjc_aws_profile_default_print)"
	echo ""

	local clustername node_type max_n_nodes
	echo -n "Cluster name, unique (lowercase alpha char + hyphens only)?: "
	read cluster_name

	echo -n "Node instance tpye (eg, default t3a.large)?: "
	read node_type

	if [ "$node_type" = "" ]; then
		node_type='t3a.large'
		echo "node_type = $node_type"
	fi

	echo -n "Max number of nodes (default is 100)?:"
	read max_n_nodes

	if [ "$max_n_nodes" = "" ]; then
		max_n_nodes=100
		echo "max_n_nodes = $max_n_nodes"
	fi

	printf "
	Cluster Name:\t\t$cluster_name
	Node Type:\t\t$node_type
	Max n Nodes:\t\t$max_n_nodes"

	printf "... Waiting 5 seconds ... cancel now if something is wrong"
	sleep 5


	eksctl create cluster -n $cluster_name \
		--nodegroup-name base-ng \
		--node-type $node_type \
		--nodes 1 \
		--nodes-min 1 \
		--nodes-max $max_n_nodes && \
		# IMPORTANT ... use the namespace in the context to record the name of the cluster
		# this is then used as a tag on all associated resources
		# if the cluster creation fails, this won't run
		# presumes that eksctl adds the necessary context and sets it to default
		kubectl create namespace $cluster_name && \
		kb_context_default_namespace $cluster_name && \
		printf "\nCreated and Set default namespace to ... $cluster_name"

}

gjc_cluster_name_get(){
	if [ "$1" = "-h" ]; then
		printf "
		Gets cluster name from the default namespace of the current context
		If cluster creation was done with gjc_cluster_create, these should
		be set appropriately so that the cluster name is the same as the default
		namespace.

		Can check by running kb_context and eksctl get cluster and comparing."
	fi
	# minify returns only config applicable to current context
	kubectl config view --minify -o jsonpath='{.contexts[].context.namespace}'
}

gjc_cluster_vpc_id_get_id(){
	aws eks describe-cluster \
		--name $(gjc_cluster_name_get) \
		--query "cluster.resourcesVpcConfig.vpcId" \
		--output text
}

gjc_cluster_sg_main_get_id(){
	aws eks describe-cluster --name $(gjc_cluster_name_get) \
		--query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
		--output text
}


# > Create an EFS
gjc_efs_create(){


	# the tag $cluster_resource_key:$cluster_name is added to all resources that
	# need to be torn down before the cluster can be torn down

	local current_region=$(gjc_aws_region_default_print)
	local cluster_name=$(gjc_cluster_name_get)

	echo "Setting up EFS on cluster $cluster_name in $current_region"

	echo "Wating 5 seconds ... cancel now if something is wrong"
	sleep 5

	# prints the first system id, may want to assign for later use
	local efs_id=$(aws efs create-file-system \
		--region $current_region \
		--performance-mode generalPurpose \
		--tags Key=Name,Value=ClusterEFS Key=$cluster_resource_key,Value=$cluster_name \
		--query 'FileSystemId' \
		--output text)
	echo "EFS Id: $efs_id"

	# >> get VPC ID of cluster
	local vpc_id=$(gjc_cluster_vpc_get_id)
	echo "VPC ID: $vpc_id"

	# >> Create a security group

	security_group_id=$(aws ec2 create-security-group \
		--group-name cluster_efs_sg \
		--description "sg for cluster efs io" \
		--vpc-id $vpc_id \
		--tags Key=$cluster_resource_key,Value=$cluster_name \
		--output text)
	echo "New Security Group: $security_group_id"


	# >> Get cluster security group (the main one)

	local cluster_sg=$(gjc_cluster_sg_main_get_id)
	echo "Main Cluster SG: $cluster_sg"

	# >> Assign all security group ids that are the source in the inbound rules for the cluster security group
	#  - assign to `bash` array of strings

	# assign each sg to a bash string array and then loop through

	# capture output text and convert to bash array
	ingress_sgs=( $(aws ec2 describe-security-groups \
		--query "SecurityGroups[?GroupId=='$cluster_sg'].IpPermissions[].UserIdGroupPairs[].GroupId" \
		--output text) )

	# how many in array
	# print each sg

	echo "Found ${#ingress_sgs[@]} Security Group Sources for main cluster sg:"
	for sg in "${ingress_sgs[@]}"; do echo "$sg"; done

	# >> Add ingress rules
	#   - For each source security group for the ingress rules of the main cluster security group
	#   - add to our new security group an ingress rule with the same source security group
	#   - The `UserId` for each ingress rule `UserIdGroupPair` seems to take
	#     + You can check with `aws sts get-caller-identity`, where `Account` in the output should correspond to `UserId` for the user/profile being used.

	for sg in "${ingress_sgs[@]}"
	  do aws ec2 authorize-security-group-ingress \
		--group-id $security_group_id \
		--protocol tcp \
		--port 2049 \
		--source-group "$sg"
	done

	# >> Check the new ingress rules

	printf "\nCheck the new ingress rules ..."
	echo "New ingress rules in sg new $security_group_id"
	aws ec2 describe-security-groups \
		--query "SecurityGroups[?GroupId=='$security_group_id'].IpPermissions[]"

	# >> Compare with the original main cluster security group ingress rules

	echo "Ingress rules of cluster's main sg $cluster_sg (which should be the same)"
	aws ec2 describe-security-groups \
		--query "SecurityGroups[?GroupId=='$cluster_sg'].IpPermissions[]"

	printf "\n sleeping 5 seconds"
	sleep 5


	# >> Add this security group to new mount targets

	# get private subnets of cluster vpc
	local subnet_ids=( $(aws ec2 describe-subnets \
		--query "Subnets[?VpcId =='$vpc_id' && MapPublicIpOnLaunch == \`false\`].SubnetId" \
		--output text) )

	echo "Private subnets of cluster VPC ($vpc_id): "
	for sn in "${subnet_ids[@]}"; do echo "$sn"; done

	# >> For all subnets, add a mount target for the `efs_id`

	echo "Adding mount targets in each private subnet for EFS"
	for sn in "${subnet_ids[@]}";
	  do aws efs create-mount-target \
		--file-system-id $efs_id \
		--subnet-id $sn \
		--security-groups $security_group_id
	done

	# >> Get efs DNS

	echo "EFS: $efs_id is set up"
}



# this gets efs id for the current cluster
# uses tag for cluster_resource_key to filter out
gjc_efs_get_id(){
	aws efs describe-file-systems \
		--query "FileSystems[] | [?contains(not_null(Tags[?Key=='$cluster_resource_key'].Value), $cluster_name)] | [0].FileSystemId" \
		--output text
}

gjc_efs_sg_get_id(){
	local cluster_name=$(gjc_cluster_name_get)
	aws ec2 describe-security-groups \
		--query "SecurityGroups[] | [?contains(not_null(Tags[?Key=='$cluster_resource_key'].Value), $cluster_name)] | [0].GroupId" \
		--output text
}

gjc_efs_mount_targets_get_ids(){
	local efs_id=$(gjc_efs_get_id)

	aws efs describe-mount-targets \
		--file-system-id $efs_id \
		--query 'MountTargets[].MountTargetId' \
		--output text
}

# > Configure Cluster for the EFS

gjc_cluster_efs_config_make(){
	local efs_id=$(gjc_efs_get_id)
	local region=$(gjc_aws_region_default_print)
	# apparently a set structure for the URL
	local efs_url="$efs_id.efs.$region.amazonaws.com"

	sed "s/EFS_URL/$efs_url/" test_efs_template.yaml > test_efs.yaml
}

gjc_cluster_efs_apply(){
	kubectl apply -f test_efs.yaml
	kubectl apply -f test_efs_claim.yaml
}

gjc_cluster_efs_describe(){
	kubectl describe pv
	kubectl describe pvc
}


# > Deploy the JupyterHub Chart Release

alias gjc_helm_repo_list='helm repo list'

gjc_helm_jupyterhub_repo_add_update(){
	helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
	helm repo update jupyterhub
}

gjc_helm_jupyterhub_chart_version_get(){
	cat jupyterhub_chart_config | awk '/chart_version/ {print $2}'
}

gjc_helm_jupyterhub_chart_version_set(){
	echo "chart_version $1" > jupyterhub_chart_config
}

gjc_helm_deploy_release(){

	local chart_version=$(gjc_helm_jupyterhub_chart_version_get)
	echo "Using chart version $chart_version"
	echo "... Waiting for 5 seconds ... cancel now if something is wrong"
	sleep 5

	local cluster_name=$(gjc_cluster_name_get)

	helm upgrade --cleanup-on-fail \
		--install $cluster_name jupyterhub/jupyterhub \
		--namespace $cluster_name \
		--create-namespace \
		--version=$chart_version \
		--values config.yaml
}

gjc_cluster_url(){
	kubectl get svc proxy-public | awk 'NR > 1 {print $4}'
}


gjc_cluster_tear_down(){
	local cluster_name=$(gjc_cluster_name_get)

	printf "\nHoly Smokes Batman!"
	printf "\nWill delete EVERYTHING, INCLUDING THE EFS, in the cluster: $cluster_name"
	echo -n "Are you sure (yes/no) ?"
	read response

	if [ "$respnose" != "yes" ]; then
		return 1
	fi

	# force delete all user pods (as helm uninstall seems not capable of this)
	echo "Force Deleting all user pods (starts with jupyter)"
	kb_pods_get_jupyter_names | xargs -I {} kubectl delete pod --force {}

	# >!! TODO: Remove EFS Resources
	# remove the EFS, SG, Mount points

	# remove the cluster
	# eksctl delete cluster $cluster_name
}
