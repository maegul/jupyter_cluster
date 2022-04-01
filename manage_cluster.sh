#! /bin/bash

# Generic Jupyter Cluster Manager: gjc_...
# source this file to use!



# echo "eksctl version: $(eksctl version)"

# printf "kubectl version:\n"
# kubectl version --short=true

# echo "Helm version: $(helm version --short)"

# > globals

# tag key for marking resources created specifically for the cluster
base_node_group_name='base-ng'  # name of the initial nodegroup in the cluster
cluster_resource_key='charmers-cluster-id'
helm_chart_config_file='config.yaml'
cluster_autoscaler_config_file='cluster-autoscaler-autodiscover.yaml'

gjc_globals_print(){
	printf "\nGlobals:\n"
	printf "\nbase_node_group_name: \t\t$base_node_group_name"
	printf "\ncluster_resource_key: \t\t$cluster_resource_key"
	printf "\nhelm_chart_config_file: \t$helm_chart_config_file"
	printf "\ncluster_autoscaler_config_file: \t$cluster_autoscaler_config_file"
}

# > Help function

gjc_help(){
	printf "
Help with Generic Jupyterhub Cluster!

Most functions will provide speicific help with argument: -h

* Make sure you're using the right aws profile:
	gjc_aws_profile_default_print ...\t print current
	gjc_aws_profile_list ... \t\t list all in config
	gjc_aws_profile_default_set ... \t set default profile to one from list

* create a cluster!:
	gjc_cluster_create ... \t\t creates a cluster using eksctl, REQUIRES ARGUMENTS
	gjc_cluster_list ... \t\t list all clusters under current profile

* Add an EFS:
	gjc_efs_create ... \t\t Adds an efs to the cluster's VPC with appropriate security group
	gjc_cluster_efs_deploy ... \t Adds the EFS to the cluster

* Deploy the jupyterhub helm chart
	gjc_helm_jupyterhub_repo_add_update ... \t update the helm charts (every so often)
	gjc_helm_chart_deploy ... \t\t\t Apply the jupyterhub chart to the current cluster

	... should make sure the version of the chart being used matches what the pod
	image relies on ... use these utilities ...
	gjc_helm_jupyterhub_chart_version_get
	gjc_helm_jupyterhub_chart_version_set

* Add the admin users
	gjc_cluster_admin_users_get ... \t\t Check that admin usernames extracted correctly
	gjc_cluster_auth_admin_accounts_add ... \t add admin users with provided password
		If using HTTPS (which is likely, you will need to provide the url ... see help with -h)

* Get the URL
	gjc_cluster_url ... \t prints the public url of the jupyterhub server
							(unless DNS records are used)
	"

	return 0
}

gjc_info(){
	gjc_aws_profile_default_details

	printf "\nClusters (from eksctl):\n"

	eksctl get cluster

	printf "\nKubectl Context: \n$(kb_context)"
}


# checks exit code
# if not 0, prints out message (first arg) and returns "1" exit code
# use after commands whose errors you want to catch:
	# CODE
	# gjc_utils_check_exit_code "aws is down" || return 1
gjc_utils_check_exit_code(){
	local exit_code=$?
	local msg=$1

	if [ $exit_code != 0 ]; then
		printf "\nGJC ERROR: $msg (exit code $exit_code)\n\n"
		return 1
	fi

	return 0

}


# > aws profiles

gjc_aws_profile_list(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	aws configure list-profiles | awk '{print FNR ": " $1}'
}

gjc_aws_profile_get(){
	if [ "$1" = "-h" ]; then
		printf "
Utility Function:
provide the integer from gjc_aws_profile_list corresponding
to the desired profile, and this will simply return that profile
		"
		return 0
	fi
	gjc_aws_profile_list | awk -v x=$1 'FNR == x {print $2}'
}

gjc_aws_profile_default_print(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	echo "Current Default AWS Profile: $AWS_DEFAULT_PROFILE"
}

gjc_aws_profile_default_set(){
	if [ "$1" = "-h" ]; then
		printf "
Sets the default aws profile in this shell. \n
Provide an integer corresponding to those listed
by each profile in the output of gjc_aws_profile_list.\n
Sets the env variable AWS_DEFAULT_PROFILE, which is used by
the AWS CLI.
		"
		return 0
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

alias gjc_aws_profile_default_get_account_id="aws sts get-caller-identity --query 'Account' --output text"
alias gjc_aws_profile_default_get_arn="aws sts get-caller-identity --query 'Arn' --output text"


gjc_aws_region_default_print(){
	if [ "$1" = "-h" ]; then
		printf "\nPrint region of current default profile"
		return 0
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
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	kubectl config current-context
}

# list all contexts and highlight current
kb_context_list(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	# awkwardly, the first column is empty when not current, so first column is col name for not current
	kubectl config get-contexts | tail -n +2 | awk '{print ($1 == "*" ? FNR "-> " $2 : FNR "   " $1)}'
}

# utility ... of all contexts, return nth context (1-based)
kb_context_get(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	# awkwardly, the first column is empty when not current, so first column is col name for not current
	kubectl config get-contexts | tail -n +2 | awk -v x=$1 'FNR == x {print ($1 == "*" ? $2 : $1 )}'
}

# macOS only
kb_context_cp(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	kb_context_get $1 | tr -d '\n'| pbcopy
}

# set context to nth context from list_all (1-based)
kb_context_set(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	kubectl config use-context $(kb_context_get $1)
}

kb_context_default_namespace_get(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	kubectl config view --minify -o jsonpath='{.contexts[].context.namespace}'
}

# set current context to use the provided namespace as default
kb_context_default_namespace_set(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	kubectl config set-context --current --namespace=$1
}

# presumes only one hub pod ... which is the default config for jupyterhub
alias kb_hubpod_get_name='kubectl get pod | awk "/hub/ {print \$1}"'


# presumes all user pods have a name that starts with "jupyter" (default)
# need to escape $ in aliases
alias kb_pods_get_jupyter_names="kubectl get pod | awk '/^jupyter/ NR>1 {print \$1}'"

alias kb_pods_list='kubectl get pod'

alias kb_pods_watch='kubectl get pod --watch'

alias kb_nodes_list='kubectl get node'

kb_pods_list_sort_by_node(){
	kubectl get pod -o wide | awk 'NR>1{ print $1, $7, $5}' | sort -k 2 | rs _ 3
}

alias kb_nodes_watch='kubectl get node --watch'

alias kb_hubpod_logs='kubectl logs -f $(kb_hubpod_get_name)'

kb_scale_replicas(){
	if [ "$1" = "-h" ]; then
		printf "
	Set the number of user placeholders pods with arg: n (a number)
		"
		return 0
	fi

	kubectl scale statefulsets/user-placeholder --replicas=$1
}

# > eksctl functions

gjc_cluster_create(){

	local clustername node_type max_n_nodes

	if [ "$1" = "-h" ]; then
		printf "
Creates a cluster!

Uses the currently set default aws profile!
Uses eksctl to create the cluster.

Takes positional arguments, which are passed to eksctl ...
... see eksctl create cluster --help for details.

If no args are provided, they'll be prompted for:

	* cluster_name:
		This becomes both the cluster name and the kubernetes namespace
		for all the jupyter pods and services etc.
		Also is used as the marker on any custom aws resources such as efs.
		Limit to lowercase alpha char + hyphens only.

	* node_type:
		the EC2 instance type to be used as the nodes

	* max_n_nodes:
		The maximum number of nodes (ie instances) that the cluster will create
		when autoscaling.  Not sure this is too relevant, but good to put a ceiling
		anyway.
		"
		return 0
	fi

	gjc_aws_profile_default_print
	echo ""

	# no args passed ... use prompt
	if [ "$*" = "" ]; then

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

	# collecting positional arguments
	else
		local cluster_name=$1
		local node_type=$2
		local max_n_nodes=$3

		# if some are blank ... exit
		if [ "$cluster_name" = "" ] || [ "$node_type" = "" ] || [ "$max_n_nodes" = "" ]; then
			printf "
	You must provide all the positional arguments!
	Use -h to see the help on what is required
			"
			return 0
		fi
	fi


	printf "
	Cluster Name:\t\t$cluster_name
	Node Type:\t\t$node_type
	Max n Nodes:\t\t$max_n_nodes
	"

	printf "\n... Waiting 10 seconds ... cancel now if something is wrong\n"
	sleep 10

	printf "\n ... lets rock!  \nCan take ~30 minutes!\n"

	eksctl create cluster -n $cluster_name \
		--nodegroup-name $base_node_group_name \
		--node-type $node_type \
		--asg-access \
		--nodes 1 \
		--nodes-min 1 \
		--nodes-max $max_n_nodes && \
		# IMPORTANT ... use the namespace in the context to record the name of the cluster
		# this is then used as a tag on all associated resources
		# if the cluster creation fails, this won't run
		# presumes that eksctl adds the necessary context and sets it to default
		kubectl create namespace $cluster_name && \
		kb_context_default_namespace_set $cluster_name && \
		printf "\nCreated and Set default namespace to ... $cluster_name"

}

alias gjc_cluster_list='eksctl get cluster'

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
	kb_context_default_namespace_get
}

gjc_cluster_vpc_get_id(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	local cluster_name=$(gjc_cluster_name_get)
	aws eks describe-cluster \
		--name $cluster_name \
		--query "cluster.resourcesVpcConfig.vpcId" \
		--output text

}

gjc_cluster_sg_main_get_id(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	aws eks describe-cluster --name $(gjc_cluster_name_get) \
		--query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
		--output text
}

# >> nodegroup IAM roles and policies

gjc_cluster_iam_oidc_provider_add(){
	if [ "$1" = "-h" ]; then
		printf "
	Adds an oidc provider to the cluster, which allows a \"handshake\" like process
	to occur that allows IAM policies/permissions to be applied to the cluster.

	Adding some IAM policies is necessary for setting up the autoscaler.
		"
		return 0
	fi

	local cluster_name=$(gjc_cluster_name_get)

	eksctl utils associate-iam-oidc-provider \
		--cluster=$cluster_name \
		--approve
}

gjc_cluster_nodegroup_role_arn_get(){
	if [ "$1" = "-h" ]; then
		printf "
	Get the arn of the IAM role attached to the nodegroup
		"
		return 0
	fi

	local cluster_name=$(gjc_cluster_name_get)

	aws eks describe-nodegroup \
		--cluster-name $cluster_name \
		--nodegroup-name $base_node_group_name \
		--query 'nodegroup.nodeRole' \
		--output text
}

gjc_cluster_nodegroup_role_name_get(){
	aws iam list-roles \
		--query "Roles[] | [?Arn == '$(gjc_cluster_nodegroup_role_arn_get)'] | [0].RoleName" \
		--output text
}

gjc_cluster_nodegroup_autoscale_policy_name_get(){
	if [ "$1" = "-h" ]; then
		printf "
	Gets the name of the policy that eksctl should have automatically created
	when using the --ags-access flag

	Presumes that the policy will have \"Auto\" in its name, which may change over time.
		"
		return 0
	fi
	aws iam list-role-policies \
		--role-name $(gjc_cluster_nodegroup_role_name_get) \
		--query "PolicyNames[?contains(@, 'Auto')] | [0]" \
		--output text
}

gjc_cluster_nodegroup_autoscale_policy_describe(){
	if [ "$1" = "-h" ]; then
		printf "
	Gets the autoscale policy for the current cluster's nodegroup, including the
	allowed actions (the \"PolicyDocument\")
		"
		return 0
	fi
	aws iam get-role-policy \
		--role-name $(gjc_cluster_nodegroup_role_name_get) \
		--policy-name $(gjc_cluster_nodegroup_autoscale_policy_name_get)
}



# gjc_cluster_nodegroup_autoscale_policy_add(){
# 	if [ "$1" = "-h" ]; then
# 		printf "
# 	Add the autoscaling IAM policy to the cluster's service accounts
# 	The policy should have been created automatically by eksctl and
# 	is retrieved with gjc_cluster_nodegroup_autoscale_policy...
# 		"
# 		return 0
# 	fi

# 	local cluster_name=$(gjc_cluster_name_get)
# 	local account_id=$(gjc_aws_profile_default_get_account_id)
# 	local policy_name=$(gjc_cluster_nodegroup_autoscale_policy_name_get)
# 	local policy_arn="arn:aws:iam::$account_id:policy/$policy_name"

# 	eksctl create iamserviceaccount \
# 		--cluster=$cluster_name \
# 		--namespace=kube-system \
# 		--name=cluster-autoscaler \
# 		--attach-policy-arn=$policy_arn \
# 		--override-existing-serviceaccounts \
# 		--approve
# }


# >> Directly creating the policy

cluster_autoscaler_policy_config_file="cluster_autoscaler_policy.yaml"
cluster_autoscaler_policy_name="AmazonEKSClusterAutoscalerPolicy"

# can't create again if exists ... need to pull from eksctl autocreated policy, delete, and push
# up again to ensure renewal?
gjc_cluster_nodegroup_autoscale_policy_create(){
	aws iam create-policy \
		--policy-name $cluster_autoscaler_policy_name \
		--policy-document "file://$cluster_autoscaler_policy_config_file"
}

gjc_cluster_nodegroup_autoscale_role_create(){
	if [ "$1" = "-h" ]; then
		printf "
	Add the autoscaling IAM policy to the cluster's service accounts
	The policy should have been created automatically by eksctl and
	is retrieved with gjc_cluster_nodegroup_autoscale_policy...
		"
		return 0
	fi

	local cluster_name=$(gjc_cluster_name_get)
	local account_id=$(gjc_aws_profile_default_get_account_id)
	local policy_name=$(gjc_cluster_nodegroup_autoscale_policy_name_get)
	local policy_arn="arn:aws:iam::$account_id:policy/$cluster_autoscaler_policy_name"

	eksctl create iamserviceaccount \
		--cluster=$cluster_name \
		--namespace=kube-system \
		--name=cluster-autoscaler \
		--attach-policy-arn=$policy_arn \
		--override-existing-serviceaccounts \
		--approve
}

gjc_cluster_nodegroup_autoscale_cluster_role_get_arn(){

	local cluster_name=$(gjc_cluster_name_get)

	eksctl get iamserviceaccount --cluster $cluster_name | \
	awk '/arn:/ NR > 1 {print $3}'
}


# >> Autoscaler

gjc_cluster_autoscale_config_create(){
	if [ "$1" = "-h" ]; then
		printf "
	Downloads a default config to the current directory at $cluster_autoscaler_config_file.

	Then subtitutes the cluster name into the marked field (maked with <YOUR CLUSTER NAME>)
		"
		return 0
	fi
	local cluster_name=$(gjc_cluster_name_get)
	curl -o \
	$cluster_autoscaler_config_file \
	https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml

	gjc_utils_check_exit_code "Failed to download config file" || return 1
	echo "Downloaded config file to $cluster_autoscaler_config_file"

	sed -i '' "s/<YOUR CLUSTER NAME>/$cluster_name/g" $cluster_autoscaler_config_file
	gjc_utils_check_exit_code "Failed to add cluster name to config file $cluster_autoscaler_config_file" || return 1
	echo "Edited config file with current cluster name"
}

gjc_cluster_autoscale_config_apply(){

	gjc_info

	printf "\n\nApplying autoscale config at $cluster_autoscaler_config_file\n"
	printf "\n ... Waiting 10 seconds ... cancel now if anything is wrong"
	sleep 10

	kubectl apply -f $cluster_autoscaler_config_file
}

# redundant ... is the autodiscover process and eksctl doing this automatically?
# also ... is the iam_role_ref correct ... the arn seems to be different from this
gjc_cluster_autoscale_pod_add_iam(){
	local account_id=$(gjc_aws_profile_default_get_account_id)
	local role_name=$cluster_autoscaler_policy_name
	local iam_role_ref="eks.amazonaws.com/role-arn=arn:aws:iam::$accounts_id:role/$role_name"

	kubectl annotate serviceaccount cluster-autoscaler \
		-n kube-system "$iam_role_ref"

}


gjc_cluster_autoscale_pod_patch(){
	kubectl patch deployment cluster-autoscaler \
	-n kube-system \
	-p '{"spec":{"template":{"metadata":{"annotations":{"cluster-autoscaler.kubernetes.io/safe-to-evict": "false"}}}}}'
}

gjc_cluster_autoscale_pod_version_set(){

	kubectl set image deployment cluster-autoscaler \
		-n kube-system \
		"cluster-autoscaler=k8s.gcr.io/autoscaling/cluster-autoscaler:v$1"
}

gjc_cluster_autoscale_pod_logs(){
	kubectl -n kube-system logs -f deployment.apps/cluster-autoscaler
}

# > Create an EFS

gjc_efs_create(){

	if [ "$1" = "-h" ]; then
		printf "
	Creates an EFS in the VPC of the current cluster

	Also creates additional resources to allow for the EFS to be mounted within the cluster:
		* security group with NFS ingress rules allowing ingress from cluster security groups
		* Mount targets for the EFS in the cluster's VPC's private subnets

	All resources are tagged with $cluster_resource_key:"CLUSTER_NAME" for future queries,
	relied on largely by gjc_cluster_tear_down to selectively remove them before deleting
	the cluster.

	The key ... $cluster_resource_key ... is defined as a global in this script.

		"
		return 0
	fi

	# the tag $cluster_resource_key:$cluster_name is added to all resources that
	# need to be torn down before the cluster can be torn down

	local current_region=$(gjc_aws_region_default_print)
	local cluster_name=$(gjc_cluster_name_get)

	echo "Setting up EFS on cluster $cluster_name in $current_region"

	echo "Wating 10 seconds ... cancel now if something is wrong"
	sleep 10

	# prints the first system id, may want to assign for later use
	local efs_id=$(aws efs create-file-system \
		--region $current_region \
		--performance-mode generalPurpose \
		--tags Key=Name,Value=ClusterEFS Key=$cluster_resource_key,Value=$cluster_name \
		--query 'FileSystemId' \
		--output text)
	gjc_utils_check_exit_code "Failed to create EFS" || return 1
	echo "EFS Id: $efs_id"

	# >> get VPC ID of cluster
	local vpc_id=$(gjc_cluster_vpc_get_id)
	gjc_utils_check_exit_code "No VPC found for cluster $cluster_name" || return 1
	echo "VPC ID: $vpc_id"

	# >> Create a security group

	local security_group_id=$(aws ec2 create-security-group \
		--group-name cluster_efs_sg \
		--description "sg for cluster efs io" \
		--vpc-id $vpc_id \
		--output text)
	gjc_utils_check_exit_code "Failed to create security group" || return 1
	echo "New Security Group: $security_group_id"

	# add tag (as --tag support isn't available on older versions of aws (eg <2.1))
	aws ec2 create-tags \
		--resources $security_group_id \
		--tags Key=$cluster_resource_key,Value=$cluster_name
	gjc_utils_check_exit_code "Failed to add tags to sg $security_group_id" || return 1
	echo "Added tags to security group"

	# >> Get cluster security group (the main one)

	local cluster_sg=$(gjc_cluster_sg_main_get_id)
	gjc_utils_check_exit_code || return 1
	echo "Main Cluster SG: $cluster_sg"

	# >> Assign all security group ids that are the source in the inbound rules for the cluster security group
	#  - assign to `bash` array of strings

	# assign each sg to a bash string array and then loop through

	# capture output text and convert to bash array
	local ingress_sgs=( $(aws ec2 describe-security-groups \
		--query "SecurityGroups[?GroupId=='$cluster_sg'].IpPermissions[].UserIdGroupPairs[].GroupId" \
		--output text) )
	gjc_utils_check_exit_code "Failed to get ingress rules from $cluster_sg" || return 1

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
	gjc_utils_check_exit_code "Failed to add ingress rule to $security_group_id" || return 1

	# >> Check the new ingress rules

	printf "\nCheck and compare the new ingress rules ...\n"
	echo "New ingress rules in sg new $security_group_id"
	aws ec2 describe-security-groups \
		--query "SecurityGroups[?GroupId=='$security_group_id'].IpPermissions[]"

	# >> Compare with the original main cluster security group ingress rules

	printf "
	\n\nIngress rules of cluster's main sg $cluster_sg
	(which should have the GroupIds under UserIdGroupPairs as above)\n"
	aws ec2 describe-security-groups \
		--query "SecurityGroups[?GroupId=='$cluster_sg'].IpPermissions[]"

	printf "\n sleeping 10 seconds"
	sleep 10


	# >> Add this security group to new mount targets

	# get private subnets of cluster vpc
	local subnet_ids=( $(aws ec2 describe-subnets \
		--query "Subnets[?VpcId =='$vpc_id' && MapPublicIpOnLaunch == \`false\`].SubnetId" \
		--output text) )
	gjc_utils_check_exit_code "Failed to get private subnets of $vpc_id" || return 1

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
	gjc_utils_check_exit_code "Failed to add mount targets for EFS $efs_id" || return 1

	# >> Get efs DNS

	printf "\nEFS: $efs_id is set up for use on the cluster\n"
}



# this gets efs id for the current cluster
# uses tag for cluster_resource_key to filter out
gjc_efs_get_id(){
	if [ "$1" = "-h" ]; then
		printf "
	Gets the FileSystemId of the efs tagged with the current cluster name

	The current cluster name is the default namespace of the current kubectl context
		"
		return 0
	fi
	local cluster_name=$(gjc_cluster_name_get)
	local query="FileSystems[] | [?contains(not_null(Tags[?Key=='$cluster_resource_key'].Value), '$cluster_name')] | [0].FileSystemId"
	aws efs describe-file-systems \
		--query "$query" \
		--output text
}

gjc_efs_sg_get_id(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	local cluster_name=$(gjc_cluster_name_get)
	# use filters as query had trouble with tags (plus, can use filters with ec2 resources)
	# note, also ... presumes only ONE custom sg created by this script!
	# should another be necessary ... more tags will be necessary
	aws ec2 describe-security-groups \
		--filters "Name=tag:$cluster_resource_key,Values=jhubproto" \
		--query 'SecurityGroups[0].GroupId' \
		--output text
}

gjc_efs_mount_targets_get_ids(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	local efs_id=$(gjc_efs_get_id)

	aws efs describe-mount-targets \
		--file-system-id $efs_id \
		--query 'MountTargets[].MountTargetId' \
		--output text
}

# > Configure Cluster for the EFS

gjc_cluster_efs_config_make(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	local efs_id=$(gjc_efs_get_id)
	local region=$(gjc_aws_region_default_print)
	# apparently a set structure for the URL
	local efs_url="$efs_id.efs.$region.amazonaws.com"

	sed "s/EFS_URL/$efs_url/" test_efs_template.yaml > test_efs.yaml && \
	printf "\nWritten out template to test_efs.yaml with appropriate url: $efs_url\n"
}

gjc_cluster_efs_config_apply(){

	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi

	# checking that efs actually deployed
	local efs_id=$(gjc_efs_get_id)

	# aws cli retuns None when query can't find a resource
	if [ "$efs_id" = "None" ]; then
		printf "
	Can't find an efs_id using gjc_efs_get_id
	Have you added one to the cluster
		"
		return 1
	fi

	kubectl apply -f test_efs.yaml
	kubectl apply -f test_efs_claim.yaml
}

gjc_cluster_efs_deploy(){
	if [ "$1" = "-h" ]; then
		printf "
	Adds the EFS to the cluster.
	Prepares the config (using gjc_cluster_efs_config_make)
	Then applies it to the cluster with gjc_cluster_efs_apply
		"
		return 0
	fi

	gjc_cluster_efs_config_make
	gjc_cluster_efs_config_apply
}

gjc_cluster_efs_describe(){

	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	kubectl describe pv
	kubectl describe pvc
}


# > Deploy the JupyterHub Chart Release

alias gjc_helm_repo_list='helm repo list'

gjc_helm_jupyterhub_repo_add_update(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
	helm repo update jupyterhub
}

# using a simple 2 column file to configure the chart version
# and some simple get and set functions

gjc_helm_jupyterhub_chart_version_get(){

	if [ "$1" = "-h" ]; then
		printf "
	Returns the chart version configured in the file jupyterhub_chart_config
		"
		return 0
	fi

	cat jupyterhub_chart_config | awk '/chart_version/ {print $2}'
}

gjc_helm_jupyterhub_chart_version_set(){

	if [ "$1" = "-h" ]; then
		printf "
	Sets the chart version configured in the file jupyter_chart_config
		"
		return 0
	fi

	echo "chart_version $1" > jupyterhub_chart_config
}

gjc_helm_chart_deploy(){

	if [ "$1" = "-h" ]; then
		printf "
	Deploys the jupyterhub helm chart onto the current cluster (given the current kubectl context)

	The version of the chart deployed is important, as it must match with the build of the
	pod image

	For the version used ... see gjc_helm_jupyterhub_chart_version_get and its help
		"
		return 0
	fi

	local chart_version=$(gjc_helm_jupyterhub_chart_version_get)
	local cluster_name=$(gjc_cluster_name_get)

	echo "Using chart version $chart_version, and $helm_chart_config_file on cluster $cluster_name"
	echo "... Waiting for 10 seconds ... cancel now if something is wrong"
	sleep 10
	echo "Deploying ... you may want to run kb_pods_watch in another terminal to ... watch"

	helm upgrade --cleanup-on-fail \
		--install $cluster_name jupyterhub/jupyterhub \
		--namespace $cluster_name \
		--create-namespace \
		--version=$chart_version \
		--values $helm_chart_config_file
}

gjc_cluster_url(){
	if [ "$1" = "-h" ]; then
		printf "
	Doc string
		"
		return 0
	fi
	kubectl get svc proxy-public | awk 'NR > 1 {print $4}'
}

gjc_cluster_is_https(){
	printf "\nCrude of checking whether cluster is HTTPS secured is to check for a pod autohttps\n"
	printf "\nSearched for such pods:...\n"

	kb_pods_list | awk '/https/ {print $1}'
}

gjc_cluster_admin_users_get(){
	if [ "$1" = "-h" ]; then
		printf "
	Gets the admin user usernames from the helm chart config file.

	... Uses slightly messy sed regex ...
	Main issue would be that it presumes no trailing whitespaces
	and indentation with spaces only (which is a YAML req anyway?)

	Presumes location of the config file according to the global
	helm_chart_config_file in this script.

	Currently presumed filename: $helm_chart_config_file
		"
		return 0
	fi
	# 1: delete all lines but between admin_users: and next line with a colon
	# 2: delete all lines with a colon at the end
	# 3: remove (substitute) leading white space, "-" and opening quotation marks
	# 4: remove closing quotation marks
	sed -E '/ *admin_users:/,/.*:/!d' $helm_chart_config_file | \
	sed '/.*: */d' | \
	sed 's/^ *- *"//g' | \
	sed 's/" *$//g'
}

gjc_cluster_auth_admin_url(){
	if [ "$1" = "-h" ]; then
		printf "
	Makes a full URL for the cluster's authentication endpoints by using
	gjc_cluster_url and adding a protocol and "/hub" at the end.

	Optional args:
		* url ... the cluster's url ... necessary when using HTTPS with a DNS record
			the protocol and endpoints will be added.
			If no url provided, the public URL will be used, which will
			only work with no HTTPS
		"
		return 0
	fi

	if [ "$1" = "" ]; then
		local url_protocol="http://"
		local url=$(gjc_cluster_url)
	else
		local url_protocol="https://"
		local url=$1
	fi

	# this hub is necessary for the authentication endpoints
	# specifics are set by the API code in the cluster set up
	echo "$url_protocol$url/hub/admin-signup"
}

# > Create Admin accounts (for NativeAuthenticator)

gjc_cluster_auth_admin_accounts_add(){
	if [ "$1" = "-h" ]; then
		printf "
	Creates the admin user accounts with the provided password.

	Gets user admin usernames with gjc_cluster_admin_users_get

	Will prompt for the password.

	Users can change their password (using the appropriate endpoint on the hub webpage)

	Optional arg:
		* url ... for when using HTTPS and a DNS record.
			Passed directly to gjc_cluster_auth_admin_url.
		"
		return 0
	fi

	local hub_url=$(gjc_cluster_auth_admin_url $1)
	printf "\n Using URL: $hub_url\n"
	local admin_usernames=( $(gjc_cluster_admin_users_get) )
	printf "\nFound ${#admin_usernames[@]} admin usernames from $helm_chart_config_file:\n"

	for un in "${admin_usernames[@]}";
		do echo $un;
	done

	printf "\nEnter the default password for each admin user\n> "
	local admin_pw
	read -s admin_pw

	printf "\n ... waiting 10 seconds ... if something is wrong ... cancel now\n"
	sleep 10

	for un in "${admin_usernames[@]}";
		do curl \
			-d username="$un" \
			-d pw="$admin_pw" \
			-X POST \
			$hub_url
			printf "\n"  # provide some spacing between curl responses
	done
}


gjc_cluster_tear_down(){
	if [ "$1" = "-h" ]; then
		printf "
	Tear down the whole cluster, including the additional resources to get the EFS to work.
		"
		return 0
	fi

	printf "\nHoly Smokes Batman!!\n\n"
	printf "\nWill delete EVERYTHING, INCLUDING THE EFS, associated with the cluster: $cluster_name\n"
	echo -n "Are you sure (yes/no) ? "
	read response

	if [ "$response" != "yes" ]; then
		return 0
	fi

	local cluster_name=$(gjc_cluster_name_get)
	local efs_id=$(gjc_efs_get_id)
	local sg_id=$(gjc_efs_sg_get_id)

	echo "vars:" $cluster_name $efs_id $sg_id

	gjc_utils_check_exit_code "No ids or cluster names found" || return 111

	# force delete all user pods (as helm uninstall seems not capable of this)
	echo "Force Deleting all user pods (starts with jupyter)"
	kb_pods_get_jupyter_names | xargs -I {} kubectl delete pod --force {}
	# could probalby check and wait until they're all cleared rather than just waiting
	sleep 10

	echo "Uninstalling the jupyterhub helm chart release $cluster_name"
	helm uninstall $cluster_name --namespace $cluster_name
	gjc_utils_check_exit_code "Helm failed to uninstall $cluster_name" || return 1

	# need better than just sleeping
	# ... check pods with kb_pods_list and move on only once none are left ...
	printf "\nWaiting 180 seconds ... to allow cluster resources to shut down before deleting EFS\n"
	sleep 180

	echo "Removing mount targets for EFS $efs_id"
	mount_tgs=( $(aws efs describe-mount-targets \
		--file-system-id $efs_id \
		--query 'MountTargets[].MountTargetId' \
		--output text) )
	gjc_utils_check_exit_code "Failed to get mount targets" || return 1

	printf "\nFound mount targets:\n"
	for mtg in "${mount_tgs[@]}";
		do echo $mtg;
	done

	for mtg in "${mount_tgs[@]}";
		do aws efs delete-mount-target --mount-target-id $mtg
	done
	gjc_utils_check_exit_code "Failed to delete mount targets" || return 1

	echo "Removing EFS $efs_id"
	aws efs delete-file-system --file-system-id $efs_id
	gjc_utils_check_exit_code "Failed to remove EFS $efs_id" || return 1

	echo "Removing security group for EFS"
	aws ec2 delete-security-group --group-id $sg_id
	gjc_utils_check_exit_code "Failed to remove security group $sg_id" || return 1

	echo "deleting the cluster"
	eksctl delete cluster -n $cluster_name

	# need to tear down IAM roles and policies for autoscaler?
}




# > after sourcing

# >> versions

echo "AWS Version: $(aws --version | awk '{print $1}' | awk -F '\/' '{print $2}')"
echo "AWS CLI should probably be >= 2.0.0"


# >> aws profile
gjc_aws_profile_default_print

echo "Current kubectl context: $(kb_context)"
