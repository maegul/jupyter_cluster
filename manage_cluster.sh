#! /bin/bash

# Generic Jupyter Cluster Manager: gjc_...
# source this file to use!

# > todo ...
	# add new admin users to the cluster
	# create notebook viewer server

# > globals
# version of kubernetes on the cluster
# range of acceptable versions depends on the versions of kubectl and eksctl installed
# as well as what AWS EKS supports
user_kubernetes_version_config_file='user_kubernetes_version_config'
# user defined variables for the jupyterhub chart
user_jupyterhub_chart_config_file='user_jupyterhub_chart_config'

base_node_group_name='base-ng'  # name of the initial nodegroup in the cluster
# tag key for marking resources created specifically for the cluster
cluster_resource_key='charmers-cluster-id'
helm_chart_config_file='config.yaml'
helm_chart_config_template_file='config_template.yaml'

cluster_autoscaler_config_file_source="https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml"
cluster_autoscaler_config_file='cluster-autoscaler-autodiscover.yaml'
cluster_autoscaler_policy_config_file="cluster_autoscaler_policy.yaml"
# note: name "cluster-autoscaler" is (and MUST match) the name of the actual service or pod that is
# created when the autoscaler is set up (through a parameter "name" in a helm chart
# or other template).
cluster_autoscaler_service_name='cluster-autoscaler'


# >> Text Formatting
function gjc_RGBcolor {
	echo "16 + $1 * 36 + $2 * 6 + $3" | bc
}

# >>> preddefined colours
# Predefined colors
gjc_fmt_reset=$(tput sgr0)
gjc_fmt_bold=$(tput bold)
gjc_fmt_undln=$(tput smul)
# gjc_fmt_red=$(tput setaf $(gjc_RGBcolor 4 1 1))
gjc_fmt_grn=$(tput setaf 2)
gjc_fmt_ppl=$(tput setaf 4)
gjc_fmt_fnc=${gjc_fmt_grn}
gjc_fmt_raw=${gjc_fmt_ppl}${gjc_fmt_undln}
gjc_fmt_hd=${gjc_fmt_undln}${gjc_fmt_bold}


gjc_globals_print(){
	printf "\n${gjc_fmt_hd}Globals${gjc_fmt_reset}:\n"
	printf "\nkubernetes_version_config: \t\t$user_kubernetes_version_config_file"
	printf "\nbase_node_group_name: \t\t\t$base_node_group_name"
	printf "\ncluster_resource_key: \t\t\t$cluster_resource_key"
	printf "\nhelm_chart_config_file: \t\t$helm_chart_config_file"
	printf "\njupyterhub_chart_version_config_file: \t$user_jupyterhub_chart_config_file"
	printf "\ncluster_autoscaler_config_file: \t$cluster_autoscaler_config_file"
	printf "\ncluster_autoscaler_policy_config_file: \t$cluster_autoscaler_policy_config_file"
	printf "\ncluster_autoscaler_service_name: \t$cluster_autoscaler_service_name"
}

# > Help functions

gjc_tldr(){
	printf "
${gjc_fmt_hd}TL;DR:${gjc_fmt_reset}
	* ${gjc_fmt_fnc}gjc_info${gjc_fmt_reset} (check accounts and context)
	* check user config files
		- ${gjc_fmt_raw}$user_kubernetes_version_config_file${gjc_fmt_reset} (version of kubernetes)
		- ${gjc_fmt_raw}$user_jupyterhub_chart_config_file${gjc_fmt_reset} (jupyterhub parameters incl https)
	* ${gjc_fmt_fnc}gjc_cluster_create${gjc_fmt_reset}
	* ${gjc_fmt_fnc}gjc_cluster_autoscaler_create${gjc_fmt_reset}
	* ${gjc_fmt_fnc}gjc_efs_create${gjc_fmt_reset}
	* ${gjc_fmt_fnc}gjc_cluster_efs_deploy${gjc_fmt_reset}
	* ${gjc_fmt_fnc}gjc_helm_jupyterhub_chart_deploy${gjc_fmt_reset}
	* IF using HTTPS:
		- ${gjc_fmt_fnc}gjc_cluster_proxy_public_url${gjc_fmt_reset} (get public URL)
		- Add record to DNS
		- Ensure ${gjc_fmt_raw}$user_jupyterhub_chart_config_file${gjc_fmt_reset} contains host name
		- ${gjc_fmt_fnc}gjc_https_reset${gjc_fmt_reset} (once DNS propagated, restart letsencrypt process)
	* ${gjc_fmt_fnc}gjc_cluster_auth_admin_accounts_add${gjc_fmt_reset}
	* ${gjc_fmt_fnc}gjc_cluster_tear_down${gjc_fmt_reset} (tear down and delete cluster)
	"
}

gjc_help(){
	printf "
Help with Generic Jupyterhub Cluster!

Most functions will provide speicific help with argument: -h
* Under each section, \"...\" separates essential commands at the top from
  non-essential/optional commands.

* ${gjc_fmt_hd}Make sure you're using the right aws profile:${gjc_fmt_reset}
	${gjc_fmt_fnc}gjc_aws_profile_default_print${gjc_fmt_reset} ...\t print current
	${gjc_fmt_fnc}gjc_aws_profile_list${gjc_fmt_reset} ... \t\t list all in config
	${gjc_fmt_fnc}gjc_aws_profile_default_set${gjc_fmt_reset} ... \t set default profile to one from list

* ${gjc_fmt_hd}create a cluster!:${gjc_fmt_reset}
	${gjc_fmt_fnc}gjc_cluster_create${gjc_fmt_reset} ... \t\t creates a cluster using eksctl, REQUIRES ARGUMENTS
	...
	${gjc_fmt_fnc}gjc_cluster_list${gjc_fmt_reset} ... \t\t list all clusters under current profile

* ${gjc_fmt_hd}add autoscaler (using full config):${gjc_fmt_reset}
	${gjc_fmt_fnc}gjc_cluster_autoscaler_create${gjc_fmt_reset} ... \t\t Create autoscaler on the cluster with appropriate permissions
	...
	${gjc_fmt_fnc}gjc_cluster_autoscaler_permissions_create${gjc_fmt_reset} ... \t create permissions for autoscaler

* ${gjc_fmt_hd}Add an EFS:${gjc_fmt_reset}
	${gjc_fmt_fnc}gjc_efs_create${gjc_fmt_reset} ... \t\t Adds an efs to the cluster's VPC with appropriate security group
	${gjc_fmt_fnc}gjc_cluster_efs_deploy${gjc_fmt_reset} ... \t Adds the EFS to the cluster

* ${gjc_fmt_hd}Deploy the jupyterhub helm chart${gjc_fmt_reset}
	${gjc_fmt_fnc}gjc_helm_jupyterhub_chart_deploy${gjc_fmt_reset} ... \t\t\t Apply the jupyterhub chart to the current cluster
	...
	... should make sure the version of the chart being used matches what the pod
	image relies on ... use these utilities to check and set if needed...
	${gjc_fmt_fnc}gjc_helm_jupyterhub_chart_version_get${gjc_fmt_reset}

* ${gjc_fmt_hd}Add the admin users${gjc_fmt_reset}
	${gjc_fmt_fnc}gjc_cluster_admin_users_get${gjc_fmt_reset} ... \t\t Check that admin usernames extracted correctly
	${gjc_fmt_fnc}gjc_cluster_auth_admin_accounts_add${gjc_fmt_reset} ... \t add admin users with provided password
		If using HTTPS (which is likely, you will need to provide the url ... see help with -h)

* ${gjc_fmt_hd}Get the URL${gjc_fmt_reset}
	${gjc_fmt_fnc}gjc_cluster_url${gjc_fmt_reset} ... \t prints the public url of the jupyterhub server
							(unless DNS records are used)

* ${gjc_fmt_hd}Remove the cluster${gjc_fmt_reset}
	${gjc_fmt_fnc}gjc_cluster_tear_down${gjc_fmt_reset} ... \t\t Tears down the cluster and associated resources created by this script
	"


	return 0
}

alias gjc_aws_cli_version="aws --version | awk '{print \$1}' | awk -F '\/' '{print \$2}'"
alias gjc_kubectl_client_version="kubectl version --short --client | awk -F ': ' '{print \$2}'"
alias gjc_eksctl_version="eksctl version"
alias gjc_helm_version="helm version --short"

gjc_depends(){
	if [ "$1" = "-h" ]; then
		printf "
	Print dependancies
		"
		return 0
	fi

	printf "AWS CLI:\n  $(gjc_aws_cli_version)\n  $(which aws)\n"
	printf "kubectl:\n  $(gjc_kubectl_client_version)\n  $(which kubectl)\n"
	printf "eksctl:\n  $(gjc_eksctl_version)\n  $(which eksctl)\n"
	printf "helm:\n  $(gjc_helm_version)\n  $(which helm)"
}


gjc_info(){
	gjc_aws_profile_default_details

	printf "\nClusters (from eksctl):\n"

	eksctl get cluster

	printf "\nKubectl Context: \n$(kb_context)"

	printf "\n------\n"
	gjc_depends
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
		# if no message provided, then no output, just return ...
		# ... for error handling while needing to maintain clean output
		if [ "$msg" = "" ]; then
			return 1
		else
			printf "\nGJC ERROR: $msg (exit code $exit_code)\n\n"
			return 1
		fi
	fi

	return 0

}

# > kubernetes version

gjc_kubernetes_version_get(){
	if [ "$1" = "-h" ]; then
		printf "
	What version of kubernetes to use derived from config file $user_kubernetes_version_config_file
		"
		return 0
	fi

	cat $user_kubernetes_version_config_file | awk '/cluster_kubernetes_version/ {print $2}'

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

	aws sts get-caller-identity --output table
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
Creates a namespace on the cluster with the same name as the cluster ...
and sets this namespace as the default namespace.

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
	sleep 10 || return 1

	printf "\n ... lets rock!  \nCan take ~30 minutes!\n"

	local kubernetes_version=$(gjc_kubernetes_version_get)
	gjc_utils_check_exit_code "Failed to get version from config" || return 1
	printf "\nCreating a cluster with kubernetes v$kubernetes_version\n"

	# Note ... using --asg-access ... helps setup autoscaling ... ?
	eksctl create cluster -n $cluster_name \
		--version $kubernetes_version \
		--nodegroup-name $base_node_group_name \
		--node-type $node_type \
		--nodes 1 \
		--nodes-min 1 \
		--nodes-max $max_n_nodes && \
		# >> Using namespace for easier automation
		# IMPORTANT ... use the namespace in the context to record the name of the cluster
		# this is then used as a tag on all associated resources
		# if the cluster creation fails, this won't run
		# presumes that eksctl adds the necessary context and sets it to default
	kubectl create namespace $cluster_name && \
	kb_context_default_namespace_set $cluster_name && \

	printf "\nCreated and Set default namespace to ... $cluster_name"

}

gjc_cluster_nodes_scale(){
	if [ "$1" = "-h" ]; then
		printf "
	Scale the number of nodes(/EC@ instances) to the provided number

	Can scale down to 0 and back up to a positive number!
	It may take some time for all resources to be drained and terminated if scaling
	down to 0 nodes.

	Scaling to 0 will not kill the cluster.
	Scaling back up can be done just with this command (provided the kubectl context etc are correct)
		"
		return 0
	fi

	local cluster_name=$(gjc_cluster_name_get)

	eksctl scale nodegroup \
		--cluster $cluster_name \
		--name $base_node_group_name \
		--nodes $1 \
		--nodes-min 0
}

gjc_cluster_kubernetes_server_version_get(){
	if [ "$1" = "-h" ]; then
		printf "
	Gets version of kubernetes running on the cluster

	Should return only major.minor format ... with no patch version
		"
		return 0
	fi
	local kubernetes_version=$(
		kubectl version --short true | \
		awk -F ':' '/Server/ {print $2}' | \
		sed -E 's [[:blank:]]*v([0-9])\.([0-9]+).* \1.\2 g'
		)


	# double check ... as can be important ... use configured version if error
	(echo "$kubernetes_version" | grep '^[0-9]\.[0-9][0-9]*$') || echo $(gjc_kubernetes_version_get)
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

# Functions for getting the policy that eksctl automatically assigns to nodes when the cluster
# is created with the --asg-access flag
# Not necessary when creating the policy yourself as is/might be done in other sections

# getting the policy created automatically by eksctl ... probelmatic method?

# gjc_cluster_nodegroup_role_arn_get(){
# 	if [ "$1" = "-h" ]; then
# 		printf "
# 	Get the arn of the IAM role attached to the nodegroup
# 		"
# 		return 0
# 	fi

# 	local cluster_name=$(gjc_cluster_name_get)

# 	aws eks describe-nodegroup \
# 		--cluster-name $cluster_name \
# 		--nodegroup-name $base_node_group_name \
# 		--query 'nodegroup.nodeRole' \
# 		--output text
# }


# gjc_cluster_nodegroup_role_name_get(){
# 	aws iam list-roles \
# 		--query "Roles[] | [?Arn == '$(gjc_cluster_nodegroup_role_arn_get)'] | [0].RoleName" \
# 		--output text
# }

# gjc_cluster_nodegroup_autoscale_policy_name_get(){
# 	if [ "$1" = "-h" ]; then
# 		printf "
# 	Gets the name of the policy that eksctl should have automatically created
# 	when using the --ags-access flag

# 	Presumes that the policy will have \"Auto\" in its name, which may change over time.
# 		"
# 		return 0
# 	fi
# 	aws iam list-role-policies \
# 		--role-name $(gjc_cluster_nodegroup_role_name_get) \
# 		--query "PolicyNames[?contains(@, 'Auto')] | [0]" \
# 		--output text
# }

# gjc_cluster_nodegroup_autoscale_policy_describe(){
# 	if [ "$1" = "-h" ]; then
# 		printf "
# 	Gets the autoscale policy for the current cluster's nodegroup, including the
# 	allowed actions (the \"PolicyDocument\")
# 		"
# 		return 0
# 	fi
# 	aws iam get-role-policy \
# 		--role-name $(gjc_cluster_nodegroup_role_name_get) \
# 		--policy-name $(gjc_cluster_nodegroup_autoscale_policy_name_get)
# }



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



# > Autoscaler


gjc_cluster_autoscaler_pod_logs(){
	kubectl -n kube-system logs -f deployment.apps/$cluster_autoscaler_service_name
}

gjc_cluster_autoscaler_latest_compatible_version(){
	if [ "$1" = "-h" ]; then
		printf "
	Get the latest version of the autoscaler image that is compatible with
	the version of kubernetes used on the current cluster.

	Relies on the fact that autoscaler versioning now follows kubernetes versions
	to the minor version.
		"
		return 0
	fi

	# using the helm chart version information to determine the latest version
	gjc_helm_autoscaler_repo_add_update > /dev/null
	gjc_utils_check_exit_code "Failed to update helm chart ... maybe retry" || return 1

	local cluster_kb_v=$(gjc_cluster_kubernetes_server_version_get)

	# Using the helm chart here, which may not be the best way foward
	helm search repo -l autoscaler/$cluster_autoscaler_service_name |\
	awk -v x=$cluster_kb_v '$3~x {print $3}' |\
	sort -r |\
	head -n 1

	# if cannot get latest version using helm chart ... use patch version 0
	gjc_utils_check_exit_code || echo "${cluster_kb_v}.0"

}


# >> Permissions and IAM

gjc_cluster_iam_oidc_provider_add(){
	if [ "$1" = "-h" ]; then
		printf "
	Adds an oidc provider to the cluster, which allows AWS IAM roles to be assigned
	to kubernetes service accounts through some form of federated authentication(?),
	where service accounts represent the identities of specific \"services\"
	performed by pods on the cluster ... such as an autoscaler.

	Adding some IAM policies is necessary for setting up the autoscaler.
		"
		return 0
	fi

	local cluster_name=$(gjc_cluster_name_get)

	eksctl utils associate-iam-oidc-provider \
		--cluster=$cluster_name \
		--approve
}

gjc_cluster_iam_oidc_provider_get_arn(){
	if [ "$1" = "-h" ]; then
		printf "
	Gets the arn of the OIDC provider associated with the current cluster, if one
	has been associated.
	Use gjc_cluster_oidc_provider_add to associate one.
		"
		return 0
	fi
	aws iam list-open-id-connect-providers \
		--query 'OpenIDConnectProviderList[].Arn' \
		--output text
}

gjc_cluster_iam_oidc_get_issuer(){
	if [ "$1" = "-h" ]; then
		printf "
	Gets the OIDC issuer for the current cluster (URL) with ID number at the end
	If a cluster is to have an OIDC provider, it should have the same ID as this ...
	... can check with gjc_cluster_iam_oidc_provider_get_arn
		"
		return 0
	fi
	local cluster_name=$(gjc_cluster_name_get)

	aws eks describe-cluster \
		--name $cluster_name \
		--query "cluster.identity.oidc.issuer" \
		--output text

}

gjc_cluster_autoscaler_iam_policy_name(){
	if [ "$1" = "-h" ]; then
		printf "
	Convenience function for generating the autoscaling policy name
	using the current cluster's name (appended to the end).

	This is so that multiple clusters can be running independently of each other
		"
		return 0
	fi

	local cluster_autoscaler_policy_name="AmazonEKSClusterAutoscalerPolicy"
	local cluster_name=$(gjc_cluster_name_get)
	echo "$cluster_autoscaler_policy_name-$cluster_name"
}

# can't create again if exists ... need to pull from eksctl autocreated policy, delete, and push
# up again to ensure renewal?
gjc_cluster_autoscaler_iam_policy_create(){
	if [ "$1" = "-h" ]; then
		printf "
	Creates a policy from $cluster_autoscaler_policy_config_file for cluster autoscaling

	Given the policy name $cluster_autoscaler_policy_name-CLUSTER_NAME

	May exist already, in which case it will not be overwritten ... must remove then
	create again
		"
		return 0
	fi

	local policy_name=$(gjc_cluster_autoscaler_iam_policy_name)
	aws iam create-policy \
		--policy-name $policy_name \
		--policy-document "file://$cluster_autoscaler_policy_config_file"
}

gjc_cluster_autoscaler_iam_policy_get_arn(){
	if [ "$1" = "-h" ]; then
		printf "
	Gets arn of iam policy created for autoscaling with name $cluster_autoscaler_policy_name-CLUSTER_NAME
		"
		return 0
	fi
	local policy_name=$(gjc_cluster_autoscaler_iam_policy_name)
	aws iam list-policies \
		--query "Policies[?contains(PolicyName, '$policy_name')].Arn" \
		--output text
}

gjc_cluster_autoscaler_iam_policy_remove(){
	if [ "$1" = "-h" ]; then
		printf "
	Remove iam policy with name $cluster_autoscaler_policy_name-CLUSTER_NAME, which would have been
	created by this script for autoscaling on the cluster
		"
		return 0
	fi
	local policy_arn=$(gjc_cluster_autoscaler_iam_policy_get_arn)
	gjc_utils_check_exit_code "Failed to get policy arn" || return 1

	aws iam delete-policy \
		--policy-arn $policy_arn
}

gjc_cluster_autoscaler_iam_role_create(){
	if [ "$1" = "-h" ]; then
		printf "
	Add the autoscaling IAM policy to the cluster's service accounts.

	Presumes that the policy has been created.

	May associate the role with the autoscaler automatically such that no further
	action, apart from creating the autoscaler pod itself, is necessary, for it to be bound
	with this role.  This is because (?) the serviceaccount, if created with the appropriate
	parameters, esepcially the --name parameter, is basically 'part' of the autoscaler.
		"
		return 0
	fi

	local cluster_name=$(gjc_cluster_name_get)
	local policy_arn=$(gjc_cluster_autoscaler_iam_policy_get_arn)

	# note: name "cluster-autoscaler" is the name of the actual service or pod that is
	# created when the autoscaler is set up (through a parameter "name" in a helm chart
	# or other template).
	eksctl create iamserviceaccount \
		--cluster=$cluster_name \
		--namespace=kube-system \
		--name=$cluster_autoscaler_service_name \
		--attach-policy-arn=$policy_arn \
		--override-existing-serviceaccounts \
		--approve
}

gjc_cluster_autoscaler_iam_role_get_arn(){
	if [ "$1" = "-h" ]; then
		printf "
	Get arn of the iam service account created on the cluster
		"
		return 0
	fi

	local cluster_name=$(gjc_cluster_name_get)

	eksctl get iamserviceaccount --cluster $cluster_name | \
	awk -v x=$cluster_autoscaler_service_name '$2~x {print $3}'
}


# >>> All permissions in one function
gjc_cluster_autoscaler_permissions_create(){
	if [ "$1" = "-h" ]; then
		printf "
	Set up the OIDC, IAM policies and roles required for the autoscaler to function
		"
		return 0
	fi

	# oidc provider
	gjc_cluster_iam_oidc_provider_add
	gjc_utils_check_exit_code "Failed to add OIDC Provider to cluster" || return 1

	# IAM policy
	local extant_policy_arn=$(gjc_cluster_autoscaler_iam_policy_get_arn)

	if [ ! "$extant_policy_arn" ]; then
		echo "No extant autoscaler policy found: $extant_policy_arn"
		echo "Creating a new one"
		gjc_cluster_autoscaler_iam_policy_create
		gjc_utils_check_exit_code "Failed to create IAM policy" || return 1
	else
		echo "Extant policy found: $extant_policy_arn"
		echo "Removing and creating a new one"
		gjc_cluster_autoscaler_iam_policy_remove
		gjc_cluster_autoscaler_iam_policy_create
		gjc_utils_check_exit_code "Failed to create IAM policy" || return 1
	fi

	# IAM Role
	gjc_cluster_autoscaler_iam_role_create
	gjc_utils_check_exit_code "Failed to create the IAM serviceaccount Role" || return 1
}

# >> Using AWS Full Config approach
# see userguide: https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html

gjc_cluster_autoscaler_config_create(){
	if [ "$1" = "-h" ]; then
		printf "
	Downloads a default config to the current directory at $cluster_autoscaler_config_file.

	Then subtitutes the cluster name into the marked field (maked with <YOUR CLUSTER NAME>)
		"
		return 0
	fi
	local cluster_name=$(gjc_cluster_name_get)
	curl -o "${cluster_autoscaler_config_file}" $cluster_autoscaler_config_file_source

	gjc_utils_check_exit_code "Failed to download config file" || return 1
	echo "Downloaded config file to ${cluster_autoscaler_config_file}.tmp"

	# comes with a place holder in the tags section for the current cluster name
	# use sed in two steps for easy and portable in-place substitution
	local new_config=$(sed "s/<YOUR CLUSTER NAME>/$cluster_name/g" "${cluster_autoscaler_config_file}")
	echo "$new_config" > $cluster_autoscaler_config_file
	gjc_utils_check_exit_code "Failed to edit config file $cluster_autoscaler_config_file" || return 1

	# can also replace the command with the necessary/recommended flags as in the sed command below
	# but it is more readable to do so with a kubectl patch which requires easier to read JSON

	# local new_config=$(
	# 	sed '/\.\/cluster-autoscaler/,/.*:/d' $cluster_autoscaler_config_file |\
	# 	sed "s/command:/command: [\"\.\/cluster-autoscaler\", \"--v=4\", \"--stderrthreshold=info\", \"--cloud-provider=aws\", \"--skip-nodes-with-local-storage=false\", \"--expander=least-waste\", \"--balance-similar-node-groups\", \"--skip-nodes-with-system-pods=false\", \"--node-group-auto-discovery=asg:tag=k8s.io\/cluster-autoscaler\/enabled,k8s.io\/cluster-autoscaler\/$cluster_name\"]/g")
	# echo "$new_config" > $cluster_autoscaler_config_file
	# gjc_utils_check_exit_code "Failed to edit config file $cluster_autoscaler_config_file" || return 1

	echo "Edited config file with current cluster name"
}

gjc_cluster_autoscaler_config_apply(){

	gjc_info

	printf "\n\nApplying autoscale config at $cluster_autoscaler_config_file\n"
	printf "\n ... Waiting 10 seconds ... cancel now if anything is wrong"
	sleep 10 || return 1

	kubectl apply -f $cluster_autoscaler_config_file
}

gjc_cluster_autoscaler_pod_add_iam(){
	if [ "$1" = "-h" ]; then
		printf "
	Add an annotation to the autoscaler's serviceaccount specifying the IAM role
	that it should use (ie, the one created by this script).

	This *should* not be necessary, as the role creation function in this script (which uses eksctl)
	should add this annotation automatically.
		"
		return 0
	fi
	local role_arn=$(gjc_cluster_autoscaler_iam_role_get_arn)
	local iam_role_ref="eks.amazonaws.com/role-arn=$role_arn"

	kubectl annotate serviceaccount $cluster_autoscaler_service_name \
		-n kube-system "$iam_role_ref"

}

gjc_cluster_autoscaler_pod_evict_policy_patch(){
	kubectl patch deployment $cluster_autoscaler_service_name \
	-n kube-system \
	-p '{"spec":{"template":{"metadata":{"annotations":{"cluster-autoscaler.kubernetes.io/safe-to-evict": "false"}}}}}'
}

gjc_cluster_autoscaler_pod_command_patch(){
	if [ "$1" = "-h" ]; then
		printf "
	Alter the entry command for the autoscaler pod with some additional flags
	and the appropriate tags for discovering node instances

	Uses kubectl patch and JSON
		"
		return 0
	fi

	local cluster_name=$(gjc_cluster_name_get)

	# concatenating strings in shell by juxtaposition
	# as kubectl patch requires single quotation marks and we want to do some variable substitution
	#    |    1   |  sub |2| ---> 1 and 2 are concatenated with the var sub in the middle
	# so 'param: "'"$var"'"' is equivalent to "param: \"$var\""
	# name must be provided to patch the correct item in the array of containers
	kubectl patch deployment $cluster_autoscaler_service_name \
	-n kube-system \
	-p '{"spec":{"template":{"spec":{"containers":[{
		"name": "'"$cluster_autoscaler_service_name"'",
		"command":[
			"./cluster-autoscaler",
			"--v=4",
			"--stderrthreshold=info",
			"--cloud-provider=aws",
			"--skip-nodes-with-local-storage=false",
			"--expander=least-waste",
			"--balance-similar-node-groups",
			"--skip-nodes-with-system-pods=false",
			"--node-group-auto-discovery=asg:tag=k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/'"$cluster_name"'"
			]
			}]}}}}'
}

gjc_cluster_autoscaler_pod_version_set(){

	local image_version=$(gjc_cluster_autoscaler_latest_compatible_version)

	kubectl set image deployment $cluster_autoscaler_service_name \
		-n kube-system \
		"cluster-autoscaler=k8s.gcr.io/autoscaling/cluster-autoscaler:v$image_version"
}

gjc_cluster_autoscaler_create(){
	if [ "$1" = "-h" ]; then
		printf "
	Create the autoscaler in the current cluster with appropriate permissions

	Involves a number of patches to the autoscaler which means the pod will be re-created
	a few times.
		"
		return 0
	fi

	gjc_cluster_autoscaler_permissions_create
	gjc_utils_check_exit_code "Failed to create permissions for the autoscaler" || return 1

	gjc_cluster_autoscaler_config_create
	gjc_utils_check_exit_code "Failed to create autoscaler config" || return 1
	gjc_cluster_autoscaler_config_apply
	gjc_utils_check_exit_code "Failed to apply autoscaler config to cluster" || return 1

	gjc_cluster_autoscaler_pod_version_set
	gjc_utils_check_exit_code "Failed to patch the image version on the autoscaler" || return 1
	gjc_cluster_autoscaler_pod_command_patch
	gjc_utils_check_exit_code "Failed to patch the image command on the autoscaler" || return 1
	gjc_cluster_autoscaler_pod_evict_policy_patch
	gjc_utils_check_exit_code "Failed to patch eviction policy on autoscaler" || return 1

	# redundant, at the moment, as it seems to be bound already by the creation of the role
	# gjc_cluster_autoscaler_pod_add_iam
	# gjc_utils_check_exit_code "Failed to add annotation assigning the IAM role for the autoscaler" || return 1
}

# >> Autoscaler config with Helm Chart
# helm chart has shown to have issues with AWS
# see GitHub issue: https://github.com/kubernetes/autoscaler/issues/4788

gjc_helm_autoscaler_repo_add_update(){
	helm repo add autoscaler https://kubernetes.github.io/autoscaler
	helm repo update autoscaler
}


gjc_cluster_autoscaler_chart_config_create(){
	if [ "$1" = "-h" ]; then
		printf "
	Fills out template config for autoscaler helmchart
		"
		return 0
	fi

	local cluster_name=$(gjc_cluster_name_get)
	local cluster_region=$(gjc_aws_region_default_print)
	local account_id=$(gjc_aws_profile_default_get_account_id)
	local iam_role_arn=$(gjc_cluster_autoscaler_iam_role_get_arn)
	# trickiest part here ... inferring the best version to use
	local autoscaler_image_tag=$(gjc_cluster_autoscaler_latest_compatible_version)

	printf "\nCreating config file for autoscaler from template\n"
	sed "
		s|CLUSTER_NAME|$cluster_name|g;
		s|CLUSTER_REGION|$cluster_region|g;
		s|IMAGE_VERSION|$autoscaler_image_tag|g;
		s|AUTOSCALER_IAM_ROLE_ARN|$iam_role_arn|g;
		" \
		autoscaler_config_template.yaml > autoscaler_config.yaml
}

gjc_cluster_autoscaler_chart_config_deploy(){
	if [ "$1" = "-h" ]; then
		printf "
	Deploys the autoscaler chart using the config found in \"autoscaler_config.yaml\"

	Presumes that the chart repo has been added and the config setup
		"
		return 0
	fi

	local cluster_name=$(gjc_cluster_name_get)

	printf "\nDeploying chart onto current cluster: $cluster_name\n"
	helm upgrade --cleanup-on-fail \
		--install "${cluster_name}-autoscaler" autoscaler/$cluster_autoscaler_service_name \
		--namespace kube-system \
		--values autoscaler_config.yaml
}

gjc_cluster_autoscaler_chart_deploy(){
	if [ "$1" = "-h" ]; then
		printf "
	Single function to do everything to put an autoscaler into the current cluster
		"
		return 0
	fi

	gjc_helm_autoscaler_repo_add_update
	gjc_utils_check_exit_code "Failed to add or update autoscaler helm chart" || return 1

	gjc_cluster_autoscaler_chart_config_create
	gjc_utils_check_exit_code "Failed to create config from template" || return 1

	gjc_cluster_autoscaler_chart_config_deploy
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
	sleep 10 || return 1

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
		--query "SecurityGroups[?GroupId=='$security_group_id'].IpPermissions[].UserIdGroupPairs[][GroupId, UserId]"

	# >> Compare with the original main cluster security group ingress rules

	printf "
	\n\nIngress rules of cluster's main sg $cluster_sg
	(which should have the GroupIds under UserIdGroupPairs as above)\n"
	aws ec2 describe-security-groups \
		--query "SecurityGroups[?GroupId=='$cluster_sg'].IpPermissions[].UserIdGroupPairs[][GroupId, UserId]"

	printf "\n sleeping 10 seconds"
	sleep 10 || return 1


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
	# aws CLI doesn't allow filtering EFS resources by tags directly with --filters ... :(
	# here ... looking up the tag with key = cluster_resource_key,
	# then checking that its value matches the cluster_name
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
		--filters "Name=tag:$cluster_resource_key,Values=$cluster_name" \
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

# > DNS and Elastic IP

gjc_ipaddress_create(){

	local cluster_name=$(gjc_cluster_name_get)

	local epi_id=$(
		aws ec2 allocate-address \
		--query 'AllocationId' \
		--output text
		)
	gjc_utils_check_exit_code "Failed to create elastic ip address" || return 1

	aws ec2 create-tags \
		--resources $epi_id \
		--tags Key=$cluster_resource_key,Value=$cluster_name

	printf "\nCreated elastic ip address: $epi_id\n"
}

gjc_ipaddress_get_ids(){

	# check only for the tag key, not the value (ie, any value will match due to wild card in Values=*)
	# as ip addresses can be used for multiple clusters
	aws ec2 describe-addresses \
		--filters "Name=tag:$cluster_resource_key,Values=*" \
		--query "Addresses[0].AllocationId" \
		--output text
}

gjc_ipaddress_get_addresses(){
	# local eip_id=$(gjc_ipaddress_get_id)
	aws ec2 describe-addresses \
		--filters "Name=tag:$cluster_resource_key,Values=*" \
		--query "Addresses[].PublicIp" \
		--output text
}

gjc_ipaddress_release(){
	local eip_id=$(gjc_ipaddress_get_id)
	local eip_address=$(gjc_ipaddress_get_address)

	gjc_utils_check_exit_code "Failed to get id and release ip address" || return 1

	aws ec2 release-address --allocation-id "$eip_id"
	gjc_utils_check_exit_code "Failed to release elastic ip address with id $eip_id" || return 1

	printf "\n Released elastic ipaddress:\n  id:\t$epi_id\n  address:\t$epi_address\n"
}

# >> HTTPS services

gjc_https_pod_name_get(){
	kubectl get pod | awk '/autohttps/ {print $1}'
}

gjc_https_pod_delete(){
	if [ "$1" = "-h" ]; then
		printf "
	If https is not working, chances are the process failed before DNS propagated.

	Once DNS has propagated, you need to restart the pods to restart the certification
	process.  A workable retry

	Deleting the pod achieves this (as kubernetes will automatically recreate the pod from scratch)
		"
		return 0
	fi

	kubectl delete pods $(gjc_https_pod_name_get)
}

gjc_https_pod_logs(){
	kubectl logs -f $(gjc_https_pod_name_get) -c secret-sync
}

gjc_https_pod_traefik_logs(){
	kubectl logs -f $(gjc_https_pod_name_get) -c traefik
}

gjc_https_tls_secret_get(){
	kubectl get secret proxy-public-tls-acme -o json
}

gjc_https_tls_secret_delete(){
	if [ "$1" = "-h" ]; then
		printf "
	If https is not working, chances are the process has failed before DNS has propagated.

	Deleting the TLS secret (along with resetting the autohttps pod) will restart the process.
		"
		return 0
	fi

	kubectl delete secret proxy-public-tls-acme
}

gjc_https_reset(){
	if [ "$1" = "-h" ]; then
		printf "
	If HTTPS is not working, resetting the services that create the certificates etc is necessary.

	Usually, the initial failure is because the DNS records hadn't propagated when the
	process was initiated.

	So ... ensure that DNS has propagated before doing this.
		"
		return 0
	fi

	gjc_https_tls_secret_delete
	gjc_utils_check_exit_code "Failed to delete the TLS secret" || return 1

	gjc_https_pod_delete
}

# check if DNS record with ip address exists
	# add DNS record with ipaddress (check exists first!)
# modify config for HTTPS (yes/no) and loadBalancerIP address
	# what happens if no HTTPS but IP address?

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

	cat $user_jupyterhub_chart_config_file | awk '/chart_version/ {print $2}'
}

gjc_helm_jupyterhub_chart_config_https_enabled_get(){
	cat $user_jupyterhub_chart_config_file | awk '/https_enabled/ {print $2}'
}

gjc_helm_jupyterhub_chart_config_https_host_get(){
	cat $user_jupyterhub_chart_config_file | awk '/https_host_domain/ {print $2}'
}

gjc_helm_jupyterhub_chart_config_lets_encrypt_contact_get(){
	cat $user_jupyterhub_chart_config_file | awk '/lets_encrypt_contact_email/ {print $2}'
}

gjc_helm_jupyterhub_config_create(){
	if [ "$1" = "-h" ]; then
		printf "
	Insert variables into the config template file (${helm_chart_config_template_file})
	to create a full config file: ${helm_chart_config_file}
		"
		return 0
	fi

	local https_enabled=$(gjc_helm_jupyterhub_chart_config_https_enabled_get)
	local https_host=$(gjc_helm_jupyterhub_chart_config_https_host_get)
	local lets_encrypt_contact=$(gjc_helm_jupyterhub_chart_config_lets_encrypt_contact_get)

	gjc_utils_check_exit_code "Failed to retrieve variables for the config" || return 1

	printf "\nWriting the following variables to the jupyterhub helm chart config:\n
	local https_enabled ... ${gjc_fmt_raw}$https_enabled ${gjc_fmt_reset}
	local https_host ... ${gjc_fmt_raw}$https_host ${gjc_fmt_reset}
	local lets_encrypt_contact ... ${gjc_fmt_raw}$lets_encrypt_contact ${gjc_fmt_reset}\n\n"

	sed "
		s|HTTPS_ENABLED|$https_enabled|g
		s|HTTPS_HOST_DOMAIN|$https_host|g
		s|LETS_ENCRYPT_CONTACT_EMAIL|$lets_encrypt_contact|g
		" \
		config_template.yaml > config.yaml

	gjc_utils_check_exit_code "Failed to write variables to config file" || return 1

}

gjc_helm_jupyterhub_chart_deploy(){

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

	gjc_helm_jupyterhub_config_create

	printf "\nUsing chart version $chart_version, and $helm_chart_config_file on cluster $cluster_name\n"
	echo "... Waiting for 10 seconds ... cancel now if something is wrong"
	sleep 10 || return 1
	echo "Deploying ... you may want to run kb_pods_watch in another terminal to ... watch"

	gjc_helm_jupyterhub_repo_add_update
	gjc_utils_check_exit_code "Failed to update helm repo" || return 1

	helm upgrade --cleanup-on-fail \
		--install $cluster_name jupyterhub/jupyterhub \
		--namespace $cluster_name \
		--create-namespace \
		--version=$chart_version \
		--values $helm_chart_config_file
}

gjc_cluster_proxy_public_url(){
	if [ "$1" = "-h" ]; then
		printf "
	Get the URL of the cluster's loadbalancer's public URL

	If HTTPS is enabled, this will not be a functional address as HTTPS certification
	will not exist for this URL.  It is an arbitrary AWS URL.
	BUT, it is necessary for setting up a DNS record.
		"
		return 0
	fi
	kubectl get svc proxy-public | awk 'NR > 1 {print $4}'
}

gjc_cluster_url(){
	if [ "$1" = "-h" ]; then
		printf "
	Returns the url at which the jupyterhub server should be available

	When no https is configured, the AWS DNS of the load balancer will be provided

	If https is enabled, the domain listed in the config ($helm_chart_config_file) will be returned
		"
		return 0
	fi

	local https_enabled=$(gjc_helm_jupyterhub_chart_config_https_enabled_get)

	if [ "$https_enabled" = "true" ]; then
		local url=$(gjc_helm_jupyterhub_chart_config_https_host_get)
	else
		local url=$(gjc_cluster_proxy_public_url)
	fi

	echo $url
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
	# 1: delete all lines except those between "admin_users:"" and next line with a colon
	# 2: delete all lines with a colon at the end
	# 3: remove (substitute) leading white space, "-" and opening quotation marks
	# 4: remove closing quotation marks
	sed '/ *admin_users:/,/.*:/!d' $helm_chart_config_file | \
	sed '/.*: */d' | \
	sed 's/^ *- *"//g' | \
	sed 's/" *$//g'
}

gjc_cluster_auth_admin_url(){
	if [ "$1" = "-h" ]; then
		printf "
	Makes a full URL for the cluster's authentication endpoints by using
	gjc_cluster_url and adding a protocol and "/hub" at the end.

	Uses jupyterhub config ($helm_chart_config_file) to determine whether
	https is being used, and if so, what the domain/url is
		"
		return 0
	fi

	local https_enabled=$(gjc_helm_jupyterhub_chart_config_https_enabled_get)

	# setting the protocol
	if [ "$https_enabled" = "true" ]; then
		local url_protocol="https://"
	else
		local url_protocol="http://"
	fi

	local url=$(gjc_cluster_url)

	# this hub is necessary for the authentication endpoints
	# specifics are set by the API code in the cluster set up
	echo "$url_protocol$url/hub/admin-signup"
}

# > Create Admin accounts (for NativeAuthenticator)

gjc_cluster_https_curl_test(){
	if [ "$1" = "-h" ]; then
		printf "
	Tests whether cURL has sufficient certificates for accessing our cluster
	which has been certified with letsencrypt.

	A problem here implies that the certificates that cURL uses need to be updated.
		"
		return 0
	fi

	curl https://letsencrypt.org -sS -o /dev/null
	gjc_utils_check_exit_code "
	${gjc_fmt_hd}cURL cannot access the cluster${gjc_fmt_reset}\n\n

	Most likely problem (especially on macOS) is out of date certificates (since Sep 2021).
	Try downloading new certs from ${gjc_fmt_raw}https://curl.se/docs/caextract.html${gjc_fmt_reset}
	The new pem file will need to be placed at ${gjc_fmt_raw}/etc/ssl/cert.pem${gjc_fmt_reset}
	... or ... its location declared by the env var ${gjc_fmt_raw}CURL_CA_BUNDLE${gjc_fmt_reset}
	" || return 1
}

gjc_cluster_auth_admin_accounts_add(){
	if [ "$1" = "-h" ]; then
		printf "
	Creates the admin user accounts with the provided password.

	Gets user admin usernames with gjc_cluster_admin_users_get

	Will prompt for the password.

	Users can change their password (using the appropriate endpoint on the hub webpage)

	The URL for the cluster's admin auth API endpoint is determined using gjc_cluster_auth_admin_url
		"
		return 0
	fi

	local hub_url=$(gjc_cluster_auth_admin_url)
	printf "\n Using URL: $hub_url\n\n"
	local admin_usernames=( $(gjc_cluster_admin_users_get) )
	printf "\nFound ${#admin_usernames[@]} admin usernames from $helm_chart_config_file:\n"

	for un in "${admin_usernames[@]}";
		do echo $un;
	done

	printf "\nEnter the default password for each admin user\n> "
	local admin_pw
	read -s admin_pw

	printf "\n ... waiting 10 seconds ... if something is wrong ... cancel now\n"
	sleep 10 || return 1

	gjc_cluster_https_curl_test
	gjc_utils_check_exit_code "Failed curl test ... issue needs to be fixed, or certs updated" || return 1

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

	gjc_info

	printf "\n\n\nHoly Smokes Batman!!\n"
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

	sleep 180 || return 1 # exit function here as continuing too early could be bad

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

	printf "\nWaiting 60 seconds ... to allow mount target removals to finalise"
	sleep 60

	echo "Removing EFS $efs_id"
	aws efs delete-file-system --file-system-id $efs_id
	gjc_utils_check_exit_code "Failed to remove EFS $efs_id" || return 1

	echo "Removing security group for EFS"
	aws ec2 delete-security-group --group-id $sg_id
	gjc_utils_check_exit_code "Failed to remove security group $sg_id" || return 1

	# no error check for this as the existence of a policy depends on whether the autoscaler
	# was set up
	echo "Removing IAM policy used for autoscaling (the role to which it was attached should be removed along with the cluster)"
	gjc_cluster_autoscaler_iam_policy_remove

	echo "deleting the cluster"
	eksctl delete cluster -n $cluster_name
}




# > after sourcing

# >> versions

echo "AWS Version: $(aws --version | awk '{print $1}' | awk -F '\/' '{print $2}')"
echo "AWS CLI should probably be >= 2.0.0"


# >> aws profile
gjc_aws_profile_default_print

echo "Current kubectl context: $(kb_context)"

printf "\n\nDependencies:\n\n"
gjc_depends
