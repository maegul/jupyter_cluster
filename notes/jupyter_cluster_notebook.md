
# Running Notebook of developing a Jupyter Kubernetes Cluster

* Uses `JupyterHub_cluster.md` as a reference

<!-- MarkdownTOC indent="\t\t" -->

1. [Check Contexts and AWS profiles](#check-contexts-and-aws-profiles)
1. [Cleaning up](#cleaning-up)
    1. [Remove **if necessary** redundant context from `kubectl` config](#remove-if-necessary-redundant-context-from-kubectl-config)
    1. [⚠️😱 !! DELETE CLUSTER !! 😱⚠️](#%E2%9A%A0%EF%B8%8F%F0%9F%98%B1--delete-cluster--%F0%9F%98%B1%E2%9A%A0%EF%B8%8F)
1. [Make Cluster](#make-cluster)
    1. [Check aws profile](#check-aws-profile)
    1. [Create!](#create)
    1. [Rescale Nodes](#rescale-nodes)
    1. [Autoscaling](#autoscaling)
        1. [Resources](#resources)
        1. [Overview](#overview)
        1. [Steps](#steps)
            1. [Permissions - Conceptual](#permissions---conceptual)
            1. [Permissions - Details](#permissions---details)
            1. [Installation/Deployment - Conceptual](#installationdeployment---conceptual)
            1. [Installation/Deployment - Details](#installationdeployment---details)
        1. [Checking](#checking)
        1. [Allowing Placeholders to be replaced by user pods](#allowing-placeholders-to-be-replaced-by-user-pods)
    1. [Managing User Access](#managing-user-access)
    1. [Delete Cluster](#delete-cluster)
1. [Deploy JupyterHub](#deploy-jupyterhub)
    1. [Get JupyterHub Repo](#get-jupyterhub-repo)
        1. [View jupyterhub Chart Config](#view-jupyterhub-chart-config)
    1. [Create Config and Deploy](#create-config-and-deploy)
        1. [Deploy](#deploy)
        1. [Setting default namespace](#setting-default-namespace)
        1. [Note on Helm Chart Version and user pod images](#note-on-helm-chart-version-and-user-pod-images)
    1. [Check Cluster](#check-cluster)
    1. [Get public URL for `JupyterHub`](#get-public-url-for-jupyterhub)
    1. [Remove Release](#remove-release)
1. [Add Basic Authentication](#add-basic-authentication)
1. [Use Native Authenticator](#use-native-authenticator)
    1. [Patch the Native Authenticator](#patch-the-native-authenticator)
        1. [Python Patch](#python-patch)
        1. [Full Config File](#full-config-file)
        1. [Deploy](#deploy-1)
        1. [Use Admin API](#use-admin-api)
1. [Add EFS Shared Storage](#add-efs-shared-storage)
    1. [Handy Snippets from AWS DOCS](#handy-snippets-from-aws-docs)
    1. [Create EFS](#create-efs)
    1. [Creating EFS with AWS CLI](#creating-efs-with-aws-cli)
        1. [Resources and Snippets](#resources-and-snippets)
        1. [Work](#work)
        1. [Single Script](#single-script)
        1. [Deleting EFS in preparation for cluster tear down](#deleting-efs-in-preparation-for-cluster-tear-down)
    1. [Configuring the Cluster](#configuring-the-cluster)
        1. [Delete persistent volumes](#delete-persistent-volumes)
1. [Providing an Image for user pods](#providing-an-image-for-user-pods)

<!-- /MarkdownTOC -->


## Check Contexts and AWS profiles

* Check AWS Profiles

```shell
aws configure list-profiles

aws sts get-caller-identity
aws sts get-caller-identity --profile PROF
```

* Set default profile

```shell
AWS_DEFAULT_PROFILE='pychm'

echo $AWS_DEFAULT_PROFILE
aws sts get-caller-identity
```


```shell
kb_context

kb_context_list_all
# eksctl delete cluster ??

# to unset a context to non
kubectl config unset current-context
kb_context
```


## Cleaning up

### Remove **if necessary** redundant context from `kubectl` config

```shell
# check contexts
cat ~/.kube/config
kb_context_list_all

kb_context_get N  # N: number of target cluster
# check that targetting right cluster
kubectl config get-contexts "$(kb_context_get N)"
# delete cluster !!!
kubectl config delete-context "$(kb_context_get N)"

# check
kb_context_list_all
cat ~/.kube/config
```

* _Check, also, redundant `users` and `clusters`_
  - With `eksctl`, these seem to be married

```shell
kubectl config get-clusters
kubectl config get-users

# kubectl delete-cluster  # SPECIFIC TO KUBECONFIG
# kubectl delete-user     # SPECIFIC TO KUBECONFIG
```


### ⚠️😱 !! DELETE CLUSTER !! 😱⚠️

```shell
kb_context
eksctl get cluster
eksctl delete cluster -n CLUSTER_NAME -p PROFILE  # specify profile to be safe!
```


## Make Cluster


### Check aws profile

```shell
echo $AWS_DEFAULT_PROFILE "|" $AWS_PROFILE
aws sts get-caller-identity  
```

### Create!

* `eksctl create cluster --help` for help
* can add `--profile PROF` to use specific aws profile
* create ... can take **~20 minutes**

```shell
cluster_name='jhubproto'
echo "making cluster: $cluster_name"

eksctl create cluster -n $cluster_name \
  --nodegroup-name base-ng \
  --node-type t3a.large \
  --nodes 1 \
  --nodes-min 1 \
  --nodes-max 2 
```

* watch (if desired), probably won't work until `kubectl` contexts have been updated by `eksctl`
  - Otherwise ... look at `aws` `Cloudformation` in the console

```shell
# once kube/config updated by ecksctl ... 
kb_context_list_all  # check
kubectl get nodes --watch
```

* Check cluster

```shell
eksctl get cluster
kubectl get nodes
```

### Rescale Nodes

Change the number of nodes (ie, `EC2` instances) ... even to zero (if there aren't bugs around this)

* get and check details

```shell
eksctl get cluster
eksctl get nodegroup --cluster jhubproto
kubectl get nodes
```

* Rescale 

```shell
# down to zero
eksctl scale nodegroup --cluster jhubproto --name base-ng --nodes 0 --nodes-min 0
eksctl scale nodegroup --cluster jhubproto --name base-ng --nodes 2 --nodes-min 1
```

* check ... if no nodes, "no resouces found", but svc will return a resource.

```shell
echo $PS1
echo $PS1
echo $PS1
```

```shell
kubectl get nodes
kubectl get svc
```

* Scale back up

```shell
eksctl scale nodegroup --cluster jhubproto --name base-ng --nodes 1 --nodes-min 1

# in another shell ... watch
kubectl get nodes --watch
```


### Autoscaling


#### Resources

* Not setup by default!!
  - See [AWS Docs on autoscaler](https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html)
  - See [Z2JH Docs on Scaling](https://zero-to-jupyterhub.readthedocs.io/en/latest/jupyterhub/customizing/user-resources.html?highlight=autoscale#amazon-web-services-elastic-kubernetes-service-eks)
  - See [`eksctl` Docs on autoscaling](https://eksctl.io/usage/autoscaling/)
    + Also, [`eksctl` Docs on IAM roles for service accounts](https://eksctl.io/usage/iamserviceaccounts/#how-it-works)
  - See [Kubernetes Autoscaler GitHub Repo](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)
    + [FAQ](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#what-are-the-parameters-to-ca)
    + [Specific section on using on AWS](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws)
    + [Example yaml config for aws](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml)
    + [Helm Chart section of the repo](https://github.com/kubernetes/autoscaler/tree/master/charts/cluster-autoscaler)
      * [Table of parameters/flags available in config `extraArgs` for the autoscaler command at startup](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#what-are-the-parameters-to-ca)
        - These parameters can be set as `extraArgs` if using the helm chart, or as flags to the command if using the full manifest.


#### Overview

* The `autoscaler` is a program that interfaces with the cluster and the cloud provider (AWS)
* It is deployed as a pod on the cluster (much like the `JupyterHub` server and `JupyterLab` user pods).
* The tricky part is that the `autoscaler` also needs permission to provision EC2 instances (which is achieved through IAM policies and roles).
* Additionally, the `autoscaler` needs to be deployed much like the `JupyterHub` resources, which are installed as `helm` `charts` and deployed through `helm`.
* Fortunately, the `autoscaler` is developed and maintained by `kubernetes` themselves as a sort of sub-component, so it _should_ be reliable going forward.

#### Steps

##### Permissions - Conceptual

* Requires the addition of an OIDC (Open ID Connect) provider to the cluster (see the AWS Docs in Resources above).
  - This performs some credential management within the cluster automatically.
* Once there's an OIDC Provider assigned to the cluster, an IAM policy and a role with that policy attached need to be created.  These will provide the permissions to `autoscale` EC2 instances.
* Once the IAM policy and role exist, a `serviceaccount` needs to be created in the cluster, which is much like a normal user account but for services or pods in a cluster.  This `serviceaccount` is then assigned the above IAM role.
* The `autoscaler`, when installed (see below), is "_bound to_" and represented by the `serviceaccount`, and so will have the required permission to `autoscale` and provision EC2 instances.
* The autoscaler "_knows_" which EC2 instances to monitor and scale through an "_auto-discovery_" process, which simply looks to see whether the AWS tags of EC2 instances match those it is configured to target.
  - `eksctl` automatically puts the conventional tags onto the EC2 instances it creates: `k8s.io/cluster-autoscaler/enabled,k8s.io/cluster-autoscaler/"$cluster_name"` (note that there are only keys, no values, as that's all that is looked at).
  - These tags are also specified in the deployment of the autoscaler just for completeness (see below).

##### Permissions - Details

_All of these steps are covered by dedicated functions in the script_

* Add an OIDC provider to the cluster.
  - There's an easy dedicated command in `eksctl` for this.
* Create IAM policy directly from a local file
  - The content of this policy is taken from the [AWS Docs on autoscaler](https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html) (see also the [Specific section on using on AWS](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws)).
* Create an `IAM ServiceAccount` using `eksctl` (which makes it easier) which requires the `ARN` of the IAM policy from above.
  - This creates both an IAM role (with the above policy) and a `serviceaccount` within the cluster and associates the role with the `serviceaccount`.
  - A function in the script can get the ARN of the IAM role created by this process.

##### Installation/Deployment - Conceptual

* Two general ways of deploying the autoscaler:
  - Use `helm` and the helm chart found in the [Helm Chart section of the GitHub repo](https://github.com/kubernetes/autoscaler/tree/master/charts/cluster-autoscaler)
  - Follow the process detailed in the [AWS Docs on `autoscaler`](https://docs.aws.amazon.com/eks/latest/userguide/autoscaling.html) which centers on using the full `kubernetes` `yaml` manifest maintained in the same [`autoscaler` GitHubSpecific section on using on AWS](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/cloudprovider/aws).
    + Note, in my experience (as of 2022-04-09), the instructions in the AWS docs have some flaws and don't always work or make sense ... but once you understand what is actually happening and why (from this document for instance), they should be pretty easy to spot.
* My experience (as of 2022-04-09) was that the helm chart has some bugs when deployed on AWS (see, eg, [my own GitHub issue on the problem I had](https://github.com/kubernetes/autoscaler/issues/4788) and similar issues in the tracker).
* Thus, though using the helm chart would be easier to program, the approach of the script at the moment is to use the full `kubernetes yaml manifest` recommended by AWS (available [here](https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml)).
* Generally, the process is to download this yaml file and make some minor tweaks.

##### Installation/Deployment - Details

* Download `yaml` manifest
* Substitute a placeholder with the name of the cluster (recorded as the default namespace of the cluster in the `.kube/config` file).
* Apply the manifest to the cluster (ie, deploy or install onto the cluster)
* Make some minor tweaks (recommended by the AWS docs) by utilising special `kubectl` commands for altering the config of the cluster.  The tweaks could be done by editing the `yaml` manifest, but that's difficult to do programmatically with a simple script.
  - Add a `safe-to-evict: false` parameter to the `autoscaler`, presumably to prevent the autoscaler for destroying itself (? ... see [FAQ in the autoscaler repo](https://github.com/kubernetes/autoscaler/blob/master/cluster-autoscaler/FAQ.md#what-types-of-pods-can-prevent-ca-from-removing-a-node))
  - Set the version of the autoscaler to use image, where this depends on the version of kubernetes the cluster is using.
    + the autoscaler versioning tracks the kubernetes version down to the minor version (kubernetes: `1.20.x` <--> autoscaler: `1.20.x`), so finding the latest compatible version requires a little bit of munging.  The script currently uses `kubectl` to get the current version on the cluster and uses the autoscaler `helm` chart and `helm` command, as they easily list all versions of the autoscaler, with using a minor version of `0` as a fallback.
  - adjust the flags passed into the `autoscaler` image `entrypoint` command.
    + Unlike the AWS Docs, which recommends manual editing, this is done in the script by a function that uses `kubectl patch`, which requires a `JSON` string.
    + `--skip-nodes-with-system-pods=false` is added, which *should* allow the cluster to be scaled down to zero nodes
    + `--balance-similar-node-groups` is added, which *should* provide an even spread of pods across the nodes.
  - Specify auto-discovery tags with the `--node-group-auto-discovery` flag.  Only the conventional tags are used here (with the cluster's name inserted).  This is essentially redundant, as these are already defined in the full `YAML` manifest, with the cluster name inserted by the script, but is done here just in case the patching process would eliminate this flag.
  - There is also a function in the script for associating the IAM role created for the autoscaler with the deployed autoscaler, but it isn't necessary to run this, as the `eksctl` command used for creating the role also creates the `serviceaccount`, which is automatically associated with the `autoscaler` once it is deployed.
    + **Importantly**, this automatic association occurs because of certain parameters that point to each other.  For our purposes, to ensure that this occurs, it is, _I think_, only important to ensure that the name of the `autoscaler` on the cluster and the name of the `serviceaccount` are the same.  
    + **Accordingly**, the script uses a global variable for this name that currently adopts the name used in the full `YAML` manifest for the `autoscaler`: `cluster-autoscaler`
      * Indeed, I suspect the `helm chart` didn't work because it failed to ensure this correspondence (??)

#### Checking

* Look at the logs of the autoscaler (using a function in the script): `gjc_cluster_autoscaler_pod_logs`
* Scale up the number of replica placeholders (in the script: `kb_scale_replicans N`) and watch the creation of pods and nodes with `kb_pods_watch` and `kb_nodes_watch`.

#### Allowing Placeholders to be replaced by user pods

* See [Z2JH Docs on pod priority config](https://zero-to-jupyterhub.readthedocs.io/en/latest/resources/reference.html?highlight=placeholder#scheduling-podpriority)

* Short story is that some config needs to be added to the chart config yaml file like below
  - It sets the priority of the placeholder pods lower than normal pods so that the autoscaler "knows" to remove placeholder pods when users signin

```yaml
podPriority:
  enabled: true
  globalDefault: false
  defaultPriority: 0
  userPlaceholderPriority: -10
```

### Managing User Access

* See [`eksctl` Docs on commands for managing the `aws-auth` configmap](https://eksctl.io/usage/iam-identity-mappings/)
* See also our `kubectl_admin.md` notes.

### Delete Cluster

```shell
eksctl get cluster

eksctl delete cluster --help
eksctl delete cluster -n jhubproto --profile maegul_user
```

## Deploy JupyterHub

### Get JupyterHub Repo

* list repos

```shell
helm repo list --debug
```

* add jupyterhub repo

```shell
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
```

* update

```shell
helm repo update jupyterhub --debug
```


#### View jupyterhub Chart Config

* Shows all default config values
  - Consult the [Z2JH Reference on these values](https://zero-to-jupyterhub.readthedocs.io/en/stable/resources/reference.html#proxy-https)

```shell
helm repo list

#                 repo     / chart      # V--> or text editor?
helm show values jupyterhub/jupyterhub | less
```

* Generally, to view the final rendered config files from helm

```shell
#                   V-> repo/chart                            V- user config file       V--> or editor
helm install test autoscaler/cluster-autoscaler --dry-run  -f autoscaler_config.yaml | less
```

### Create Config and Deploy

* Create config file
  - It doesn't need to contain anything, as defaults will be fine.
  - Below, custom parameters are defined.

```shell
pwd

mkdir jupyterhub_dev

cd jupyterhub_dev
touch config.yaml
```

#### Deploy

* Deploy up to the cluster
  - Notice use of `helm upgrade`.  This is to upgrade a deployment or `release` (`helm` terminology).
    + In the code below, the `release` name is the first term after `--install`.
  - _But, if the release doesn't exist yet, then it gets installed_, so it's a handy all-in-one ("_declarative?"_) command for installing/updating a `release`.

```shell
helm upgrade --cleanup-on-fail \
  --install jhubproto jupyterhub/jupyterhub \
  --namespace jhub-proto \
  --create-namespace \
  --version=1.1.3 \
  --values config.yaml
```

* watch in other shells

```shell
kubectl get nodes --watch
kubectl get pods -n jhub-proto --watch
```


#### Setting default namespace

* Use aliases/functions from JupyterHub_cluster file.
  - Presumes you are currently in the context to which you want the namespace to apply (use `kb_context` to check)
  - Adds to the config of this context (which you can view in `~/.kube/config`), and simply adds a `namespace` parameter.
  - No longer need to provide `-n jhub-proto` to calls to `kubectl`

```shell
kb_context_default_namespace jhub-proto
```

#### Note on Helm Chart Version and user pod images

* As tabulated in [the jupyterhub helm chart docs](https://jupyterhub.github.io/helm-chart/), each helm chart will use a particular version of `jupyterhub` (listed in the `App. version` column of the linked table, while `version` is the helm chart version).
* For a jupyter pod to work, it must **also have the same version of jupyterhub installed**.
  - This can be ensured by basing the image off of a pre-built jupyter image that uses the required version of `jupyterhub`.
  - The images are tagged on docker hub with such information.  See [Jupyter Docker Stacks Images](https://jupyter-docker-stacks.readthedocs.io/en/latest/using/selecting.html)

### Check Cluster

```shell
kubectl get pods -n jhub-proto
```

* Access shell main hub pod 
  - Need specific name of the pod starting `hub-...`
  - Useful for checking the authentication system

```shell
#                 * hub pod name            * namespace
kubectl exec -it pod/hub-bbd56f6f9-kd5gm -n jhub-proto -- /bin/bash
```

### Get public URL for `JupyterHub`

* EXTERNAL-IP is accessible on the web
  - If using the default chart values (use `helm show values ...`), the `dummy` authenticator should be used, which basically takes any username/password without reservation ... so test away!!

```shell
kubectl --namespace=jhub-proto get svc proxy-public
```


### Remove Release

```shell
helm uninstall jhubproto --namespace jhub-proto
```

## Add Basic Authentication

* Restrict default dummy authenticator
  - restricted users and admin users
  - single password.

* Add the following to the `config.yaml`

```yaml
hub:
  config:
    Authenticator:
      admin_users:
        - errolloyd
        - edschofield
      allowed_users:
        - guido
        - rossum
    DummyAuthenticator:
      password: bill share soup brick
    JupyterHub:
      authenticator_class: dummy
```

* Update the `release`:

```shell
helm upgrade --cleanup-on-fail \
  --install jhubproto jupyterhub/jupyterhub \
  --namespace jhub-proto \
  --create-namespace \
  --version=1.1.3 \
  --values config.yaml

```

* Check everything is running (not really necessary)

```shell
kubectl get pods -n jhub-proto
```

* Restart hub pod

```shell
kubectl delete -h
kubectl get pod -n jhub-proto

kubectl delete pod hub-84554f9768-ggljm -n jhub-proto

kubectl get pod -n jhub-proto
```

* Refresh browser and log in!




## Use Native Authenticator

* alter `config.yaml` to following
  - Set `jupyterlab` to default with `defaultUrl: "/lab"`
  - Two admin users (who are empowered to approve/disapprove new users)

```yaml
singleuser:
  defaultUrl: "/lab"
hub:
  config:
    JupyterHub:
      authenticator_class: nativeauthenticator.NativeAuthenticator
    Authenticator:
      admin_access: true
      admin_users:
        - "errollloyd"
        - "edschofield"
    NativeAuthenticator:
      enable_signup: true
      minimum_password_length: 8
      check_common_password: true
      ask_email_on_signup: false
      allow_2fa: false

```

* Update `release`

```shell
helm upgrade --cleanup-on-fail \
  --install jhubproto jupyterhub/jupyterhub \
  --namespace jhub-proto \
  --create-namespace \
  --version=1.1.3 \
  --values config.yaml

```

* Refresh browser and _signup with one of the admin usernames defined in the config above, including providing a password._


### Patch the Native Authenticator

* Add the python code below under the attribute `hub.extraConfig.my_config.py`, ensuring to use the YAML `|` operator for multiline strings after the final attribute (`my_config.py`).
  - The `my_config.py` is arbitrary.
* This patch does the following:
  - Subclasses the `nativeauthenticator` to create an `AdminNativeAuthenticator` class
  - Adds two new `POST` endpoints intended for script/`web-api` usage:
    + `HUBURL/admin-signup`: Allow an admin user to signup for the first time without using the browser.
    + `HUBURL/admin-user-signup`: Allow an admin user to create and approve a new user.  **This requires admin authentication**, so something like `requests.Session` would probably work best.

#### Python Patch

```python
from nativeauthenticator.nativeauthenticator import (
  NativeAuthenticator, bcrypt)
from nativeauthenticator.handlers import (
    LocalBase, admin_only, UserInfo, web)


class AdminUserSignUpHandler(LocalBase):
    """admin API for adding users"""

    # this will be deprecated in jupyterhub 2.X,
    # which will have more flexible roles
    @admin_only
    async def post(self):

        username = self.get_body_argument('username', strip=False)

        # could add "is_authorized": True ... no need to authorize
        user_info = {
            'username': username,
            'pw': self.get_body_argument('pw', strip=False),
            'is_authorized': True  # this is trusting API, authorize straight away
        }

        taken = self.authenticator.user_exists(user_info['username'])
        # custom create user function `admin_create_user`
        user = self.authenticator.admin_create_user(**user_info)

        message = self.authenticator.create_message(taken, username, user)

        self.finish(message)


class AdminSignUpHandler(AdminUserSignUpHandler):
    '''Allow signup for admin when no signup allowed
    '''

    async def post(self):

        username = self.get_body_argument('username', strip=False)

        # override default behaviour only under these conditions
        username_is_admin = username in self.admin_users
        taken = self.authenticator.user_exists(username)
        special_case = (
            # else, just use normal interface
            (not self.authenticator.enable_signup) and
            (username_is_admin) and
            # only allow admin signup once!
            (not taken)
            )

        self.log.info(f'Admin signup ... special case: {special_case}')
        self.log.info(f'(is admin: {username_is_admin}, taken: {taken})')

        if special_case:
            user_info = {
                'username': username,
                'pw': self.get_body_argument('pw', strip=False),
                'is_authorized': True
            }

            # custom create user function `admin_create_user`
            user = self.authenticator.admin_create_user(**user_info)
            message = self.authenticator.create_message(taken, username, user)

            self.finish(message)
        else:
            raise web.HTTPError(404)


class AdminNativeAuthenticator(NativeAuthenticator):

    def get_handlers(self, app):
        # hope this super call works!
        handlers = super().get_handlers(app)
        handlers.append(
            (r'/admin-signup', AdminSignUpHandler))
        handlers.append(
            (r'/admin-user-signup', AdminUserSignUpHandler))

        return handlers

    def create_message(self, taken, username, user):
        "Create dictionary message for use in lightweight admin API"
        if taken:
            message = {
                'message': "Username {} is taken".format(username),
                'status': 'taken'
                }
        elif user:
            message = {
                # presuming user is a UserInfo object as all other are None
                'message': 'Username {} has been added'.format(user.username),
                'status': 'success'
                }
        else:
            message = {
                'message': "Error, username {} not added".format(username),
                'status': 'error'
                }

        return message

    def admin_create_user(self, username, pw, **kwargs):
        """Simple direct user creation for trustworthy/admin caller

        adapted from nativeauthenticator create_user() method
        """
        # at this stage ... just lowercase
        # NativeAuthenticator and base Authenticator just lower ... could add more
        username = self.normalize_username(username)

        encoded_pw = bcrypt.hashpw(pw.encode(), bcrypt.gensalt())
        infos = {'username': username, 'password': encoded_pw}
        infos.update(kwargs)

        try:
            user_info = UserInfo(**infos)
        except AssertionError:
            return

        self.db.add(user_info)
        self.db.commit()
        return user_info


# perhaps needs to be updated
c.JupyterHub.authenticator_class = AdminNativeAuthenticator
# c.JupyterHub.authenticator_class = 'nativeauthenticator.NativeAuthenticator'

# no signup ... how admin login?
c.Authenticator.enable_signup = False
# c.Authenticator.enable_signup = True

c.Authenticator.admin_users = {'errollloyd'}

```

#### Full Config File

* Config should now be following

```yaml
singleuser:
  defaultUrl: "/lab"
hub:
  config:
    JupyterHub:
      authenticator_class: nativeauthenticator.NativeAuthenticator
    Authenticator:
      admin_access: true
      admin_users:
        - "errollloyd"
        - "edschofield"
    NativeAuthenticator:
      enable_signup: true
      minimum_password_length: 8
      check_common_password: true
      ask_email_on_signup: false
      allow_2fa: false
  extraConfig:
    my_config.py: |
      from nativeauthenticator.nativeauthenticator import (
        NativeAuthenticator, bcrypt)
      from nativeauthenticator.handlers import (
          LocalBase, admin_only, UserInfo, web)


      class AdminUserSignUpHandler(LocalBase):
          """admin API for adding users"""

          # this will be deprecated in jupyterhub 2.X,
          # which will have more flexible roles
          @admin_only
          async def post(self):

              username = self.get_body_argument('username', strip=False)

              # could add "is_authorized": True ... no need to authorize
              user_info = {
                  'username': username,
                  'pw': self.get_body_argument('pw', strip=False),
                  'is_authorized': True  # this is trusting API, authorize straight away
              }

              taken = self.authenticator.user_exists(user_info['username'])
              # custom create user function `admin_create_user`
              user = self.authenticator.admin_create_user(**user_info)

              message = self.authenticator.create_message(taken, username, user)

              self.finish(message)


      class AdminSignUpHandler(AdminUserSignUpHandler):
          '''Allow signup for admin when no signup allowed
          '''

          async def post(self):

              username = self.get_body_argument('username', strip=False)

              # override default behaviour only under these conditions
              username_is_admin = username in self.admin_users
              taken = self.authenticator.user_exists(username)
              special_case = (
                  # else, just use normal interface
                  (not self.authenticator.enable_signup) and
                  (username_is_admin) and
                  # only allow admin signup once!
                  (not taken)
                  )

              self.log.info(f'Admin signup ... special case: {special_case}')
              self.log.info(f'(is admin: {username_is_admin}, taken: {taken})')

              if special_case:
                  user_info = {
                      'username': username,
                      'pw': self.get_body_argument('pw', strip=False),
                      'is_authorized': True
                  }

                  # custom create user function `admin_create_user`
                  user = self.authenticator.admin_create_user(**user_info)
                  message = self.authenticator.create_message(taken, username, user)

                  self.finish(message)
              else:
                  raise web.HTTPError(404)


      class AdminNativeAuthenticator(NativeAuthenticator):

          def get_handlers(self, app):
              # hope this super call works!
              handlers = super().get_handlers(app)
              handlers.append(
                  (r'/admin-signup', AdminSignUpHandler))
              handlers.append(
                  (r'/admin-user-signup', AdminUserSignUpHandler))

              return handlers

          def create_message(self, taken, username, user):
              "Create dictionary message for use in lightweight admin API"
              if taken:
                  message = {
                      'message': "Username {} is taken".format(username),
                      'status': 'taken'
                      }
              elif user:
                  message = {
                      # presuming user is a UserInfo object as all other are None
                      'message': 'Username {} has been added'.format(user.username),
                      'status': 'success'
                      }
              else:
                  message = {
                      'message': "Error, username {} not added".format(username),
                      'status': 'error'
                      }

              return message

          def admin_create_user(self, username, pw, **kwargs):
              """Simple direct user creation for trustworthy/admin caller

              adapted from nativeauthenticator create_user() method
              """
              # at this stage ... just lowercase
              # NativeAuthenticator and base Authenticator just lower ... could add more
              username = self.normalize_username(username)

              encoded_pw = bcrypt.hashpw(pw.encode(), bcrypt.gensalt())
              infos = {'username': username, 'password': encoded_pw}
              infos.update(kwargs)

              try:
                  user_info = UserInfo(**infos)
              except AssertionError:
                  return

              self.db.add(user_info)
              self.db.commit()
              return user_info


      # perhaps needs to be updated
      c.JupyterHub.authenticator_class = AdminNativeAuthenticator
      # c.JupyterHub.authenticator_class = 'nativeauthenticator.NativeAuthenticator'

      # no signup ... how admin login?
      c.Authenticator.enable_signup = False
      # c.Authenticator.enable_signup = True

      c.Authenticator.admin_users = {'errollloyd'}
```


#### Deploy

* Update the `release`

```shell
helm upgrade --cleanup-on-fail \
  --install jhubproto jupyterhub/jupyterhub \
  --namespace jhub-proto \
  --create-namespace \
  --version=1.1.3 \
  --values config.yaml

```

* Delete/restart the hub pod (sometimes necessary to get the new settings to apply)

```shell
kubectl get pods -n jhub-proto

kubectl delete pod hub-5c756bbfd8-9r54w -n jhub-proto

kubectl get pods -n jhub-proto  # check
```

```shell
# just return current hub pod name
alias gethub='kubectl get pod -n jhub-proto | awk "/hub/ {print \$1}"'
```

```shell
kubectl delete pod $(gethub) -n jhub-proto
```

#### Use Admin API

```shell
ipython
```

* Setup
* To get public URL: `kubectl get svc -n $hub_ns proxy-public`

```python
import getpass

import pandas as pd
import requests as req

# need current public URL for cluster
# hub at the end is necessary
base_url = 'http://aba7acd3dc5124bd88f14cb502ae39af-684325676.ap-southeast-2.elb.amazonaws.com/hub'
base_url = 'http://hub.datacharmers.com/hub'
admin_user = 'errol@pythoncharmers.com'

```

* Setup admin password (if necessary, and you don't want to do it through the web GUI)

```python
# admin_password = 'bill share soup brick'
admin_password = getpass.getpass()

r = req.post(base_url+'/admin-signup', data={'username':admin_user, 'pw':admin_password})
r
```

* All admin

```python
# admin_password = getpass.getpass()

admin_users = [
  "errol@pythoncharmers.com", 
  "ed@pythoncharmers.com", 
  "robert@pythoncharmers.com", 
  "henry@pythoncharmers.com"
  ]

for admin_user in admin_users:
  r = req.post(base_url+'/admin-signup', data={'username':admin_user, 'pw':admin_password})
  print(admin_user, r)

```

* Test that endpoints are not accessible without authentication

```python

a = req.get(base_url+'/authorize')
a

a = req.post(base_url+'/admin-user-signup', data={'username':'admin_test', 'pw':'test'})
a
a.reason
```

* Authenticate as admin and add a new user with the api

```python
# admin_password = 'bill share soup brick'
# admin_password = getpass.getpass()
admin_user = 'errol@pythoncharmers.com'

with req.Session() as s:
    l = s.post(base_url+'/login', data={'username': admin_user, 'password': admin_password})
    print('admin login', l)
    a = s.post(base_url+'/admin-user-signup', data={'username':'admin_test2', 'pw':'test'})
    print('add user request', a)
    print(a.json())
    # get the authorize dashboard just for viewing
    a2 = s.get(base_url+'/authorize')
    print('get authorize dashboard', a2)

# > See authorize dashboard ... check if new user is now authorized!
users = pd.read_html(a2.text)[0]
print('authorize dashboard:')
users
```


## Add EFS Shared Storage

* Limiting to a single Availability Zone an issue?
  - See [eksctl docs on zone specific scaling](https://eksctl.io/usage/autoscaling/#zone-aware-auto-scaling)

### Handy Snippets from AWS DOCS

From [AWS EKS Docs on EFS storage](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html#efs-create-filesystem)


```shell
eksctl get cluster

# preview
aws eks describe-cluster \
    --name jhubproto \
    --query "cluster.resourcesVpcConfig" 

# get a cluster's VPC
vpc_id=$(aws eks describe-cluster \
    --name my-cluster \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)

# get cluster security group id (useful for EFS security group)
aws eks describe-cluster \
    --name jhubproto \
    --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
    --output text

# get the other security group id
aws eks describe-cluster \
    --name jhubproto \
    --query "cluster.resourcesVpcConfig.securityGroupIds" \
    --output text


# get CIDR range of VCP
cidr_range=$(aws ec2 describe-vpcs \
    --vpc-ids $vpc_id \
    --query "Vpcs[].CidrBlock" \
    --output text)

# get cluster security group id

# create a security group
security_group_id=$(aws ec2 create-security-group \
    --group-name MyEfsSecurityGroup \
    --description "My EFS security group" \
    --vpc-id $vpc_id \
    --output text)

# Create an inbound rule that allows inbound NFS traffic from the CIDR for your cluster's VPC.
aws ec2 authorize-security-group-ingress \
    --group-id $security_group_id \
    --protocol tcp \
    --port 2049 \
    --cidr $cidr_range
```


### Create EFS

* Follow notes [at Z2JH docs](https://zero-to-jupyterhub.readthedocs.io/en/latest/kubernetes/amazon/efs_storage.html)
  - `eksctl` automatically allows for session management connections to nodes ... get access through the console.
  - From this shell, can mount the EFS.
  - Creating EFS:
    + Putin same VPC as cluster (which will be named with `eksctl` and the cluster name)
    + regional or single AZ?  Single AZ will probably have faster performance?
  - Creating Security Group
    + Put in cluster's VPC
    + Add inbound rule:
      * type: NFS
      * source: the same security group as the _base node of the cluster_
        - go to the cluster in the aws console, node group or instances, then the EC2 instance, find its SG
        - go to all security groups, sort by VPC ID, find all those in the cluster's VPC, one with inbound rules, a description like `EKS created security group applied to ENI that is attached to EKS Control Plane master nodes, as well as any managed workloads.` and a name that is more general and contains terms like `cluster`, `sg`, and the cluster name.
        - If uncertain ... pick one and test by manually mounting the EFS on the main node by connecting with session management (mounting commands are easily found in the EFS console, try the `Attach` button).
      * Also the security group that is for inter-node communication (? can't hurt ?) with description like `Communication between all nodes in the cluster`
  - Add new security group to the EFS
    + network access ... add security group to each availability zone if necessary.
  - Test by manually mounting the EFS on the master node
    + select node from EC2 instances (it is an instance)
    + Select Session management (ssh access depends on `eksctl` options, where allowing session management access is/was the default, ssh access is not unless specified?)
    + You'll get a shell.
    + create a directory `efs`
    + copy the mounting command from the `attach` button from the `EFS` console for the new EFS you've created.
    + `cd` into the directory, touch and write to a file (use `sudo`).  This activity should show up in the `efs` monitoring.
    + delete the file created
    + unmount with `sudo umount efs` (notice, no `un` but `u`!)
    + delete `efs` folder (careful)

### Creating EFS with AWS CLI

#### Resources and Snippets

* [AWS Docs on using EFS CSI with kubernetes with useful CLI snippets](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html#efs-create-filesystem)
* [AWS walkthrough on creating EFS with CLI](https://docs.aws.amazon.com/efs/latest/ug/wt1-create-efs-resources.html#wt1-create-mount-target)

```shell
# get cluster name if necessary
eksctl get cluster 

# get a cluster's VPC
vpc_id=$(aws eks describe-cluster \
    --name jhubproto \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)


aws eks describe-cluster \
    --name jhubproto \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text

aws eks describe-cluster \
    --name jhubproto \
    --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" \
    --output text

# create EFS
aws efs create-file-system \
    --region ap-southeast-2 \
    --performance-mode generalPurpose \
    --tags Key=Name,Value=jhubprotoEFS \
    --query 'FileSystemId' \
    --output text

# can't add VPC directly ... must add mount target


```

#### Work


* Creating mount target
  - Can't simply add to a specific VPC.
  - BUT, must assign mount target(s), one in any availability zone for a particular VPC
  - Requires the following args/information:
    + `file-system-id`: the id of the EFS, from creation above
    + `subnet-id`: the subnet that is specific to an availability zone for a particular VPC. _This is how the EFS is put into a VPC, but at the specificity of an availability zone_.  This can be multiple.
    + `security-groups`: (optional), which security groups to associate with the EFS.  If not provided, defaults to the default security group for the subnet's VPC.
  - Steps
    + get `file-system-id` of created EFS
    + get `vpc-id` of cluster
    + create a security group in the `vpc`
    + Add inbound rules to the above security group
      * NFS (tcp, port 2049)
      * `--source-group` is same as the cluster security group
        - can get (?) by getting cluster security group with `aws describe-cluster` then use `aws ec2 describe-security-groups --group-id XXX` and filter for `IpPermissions[].UserIdGroupPairs[] GroupId`
          + These will be (as of 2022-03-18) the main cluster group and the one for inter-node communication.
          + The inter-node communication sg may not be necessary??

* Create an EFS

```shell
# prints the first system id, may want to assign for later use
efs_id=$(aws efs create-file-system \
    --region ap-southeast-2 \
    --performance-mode generalPurpose \
    --tags Key=Name,Value=jhubprotoEFS \
    --query 'FileSystemId' \
    --output text)
echo "EFS Id: $efs_id"
```

* list all file systems

```shell
# all file systems and the ids
aws efs describe-file-systems --query 'FileSystems[].[FileSystemId, Name]' --output table
```


* get VPC ID of cluster

```shell
# vpc ID
vpc_id=$(aws eks describe-cluster \
    --name jhubproto \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)
echo "VPC ID: $vpc_id"
```

* Create a security group

```shell
security_group_id=$(aws ec2 create-security-group \
    --group-name cluster_efs_sg \
    --description "sg for cluster efs io" \
    --vpc-id $vpc_id \
    --output text)
echo "New Security Group: $security_group_id"
```


* Get cluster security group (the main one)

```shell
cluster_sg=$(aws eks describe-cluster --name jhubproto \
    --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
    --output text
    )
echo "Main Cluster SG: $cluster_sg"
```

* list all security groups under specific VPC

```shell
# double quotes then single around variable
aws ec2 describe-security-groups \
    --query "SecurityGroups[?VpcId=='$vpc_id'][GroupName,Description,GroupId]"
```

* Get inbound rules of main cluster security group
  - we want to replicate this on the EFS
  - _Hopefully the configuration of these security groups doesn't change (??)_

```shell
aws ec2 describe-security-groups \
    --query "SecurityGroups[?GroupId=='$cluster_sg'].IpPermissions[].UserIdGroupPairs[].GroupId" \
    --output text
```

* Assign all security group ids that are the source in the inbound rules for the cluster security group
  - assign to `bash` array of strings

```shell
# assign each sg to a bash string array and then loop through

# capture output text and convert to bash array
ingress_sgs=( $(aws ec2 describe-security-groups \
    --query "SecurityGroups[?GroupId=='$cluster_sg'].IpPermissions[].UserIdGroupPairs[].GroupId" \
    --output text) )

# how many in array
# print each sg

echo "${#ingress_sgs[@]} Security Group Sources:"
for sg in "${ingress_sgs[@]}"; do echo "$sg"; done
```

* For each source security group for the ingress rules of the main cluster security group
  - add to our new security group an ingress rule with the same source security group
  - The `UserId` for each ingress rule `UserIdGroupPair` seems to take
    + You can check with `aws sts get-caller-identity`, where `Account` in the output should correspond to `UserId` for the user/profile being used.

```shell
for sg in "${ingress_sgs[@]}"
  do aws ec2 authorize-security-group-ingress \
    --group-id $security_group_id \
    --protocol tcp \
    --port 2049 \
    --source-group "$sg"
done

```

* Check the new ingress rules

```shell
aws ec2 describe-security-groups \
    --query "SecurityGroups[?GroupId=='$security_group_id'].IpPermissions[]"
```

* Compare with the original main cluster security group ingress rules

```shell
aws ec2 describe-security-groups \
    --query "SecurityGroups[?GroupId=='$cluster_sg'].IpPermissions[]"
```

* **Add this security group to new mount targets**

* Check mount targets

```shell
aws efs describe-mount-targets \
--file-system-id $efs_id \
--region ap-southeast-2
```

* Describe subnets of cluster's `vpc`.

```shell
aws ec2 describe-subnets \
    --query "Subnets[?VpcId =='$vpc_id'][AvailabilityZone, SubnetId, CidrBlock] | sort_by(@, &[0])" \
    --output table
```

* Get only the private subnets

```shell
aws ec2 describe-subnets \
    --query "Subnets[?VpcId =='$vpc_id' && MapPublicIpOnLaunch == \`false\`][AvailabilityZone, SubnetId, CidrBlock, MapPublicIpOnLaunch]" \
    --output table

aws ec2 describe-subnets \
    --query "Subnets[?VpcId =='$vpc_id' && MapPublicIpOnLaunch == \`false\`].SubnetId" \
    --output text

```

* Get all `SubnetId` values in bash array

```shell
subnet_ids=( $(aws ec2 describe-subnets \
    --query "Subnets[?VpcId =='$vpc_id' && MapPublicIpOnLaunch == \`false\`].SubnetId" \
    --output text) )

for sn in "${subnet_ids[@]}"; do echo "$sn"; done
```

* For all subnets, add a mount target for the `efs_id`

```shell
for sn in "${subnet_ids[@]}";
  do aws efs create-mount-target \
    --file-system-id $efs_id \
    --subnet-id $sn \
    --security-groups $security_group_id
done
```

* Get efs DNS

```shell
echo $efs_id
```


#### Single Script



```shell
# > Create an EFS

echo "Setting up EFS on cluster $cluster_name"

# prints the first system id, may want to assign for later use
efs_id=$(aws efs create-file-system \
    --region ap-southeast-2 \
    --performance-mode generalPurpose \
    --tags Key=Name,Value=ClusterEFS \
    --query 'FileSystemId' \
    --output text)
echo "EFS Id: $efs_id"

# > get VPC ID of cluster

vpc_id=$(aws eks describe-cluster \
    --name jhubproto \
    --query "cluster.resourcesVpcConfig.vpcId" \
    --output text)
echo "VPC ID: $vpc_id"

# > Create a security group

security_group_id=$(aws ec2 create-security-group \
    --group-name cluster_efs_sg \
    --description "sg for cluster efs io" \
    --vpc-id $vpc_id \
    --output text)
echo "New Security Group: $security_group_id"


# > Get cluster security group (the main one)

cluster_sg=$(aws eks describe-cluster --name jhubproto \
    --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' \
    --output text
    )
echo "Main Cluster SG: $cluster_sg"

# > Assign all security group ids that are the source in the inbound rules for the cluster security group
#  - assign to `bash` array of strings

# assign each sg to a bash string array and then loop through

# capture output text and convert to bash array
ingress_sgs=( $(aws ec2 describe-security-groups \
    --query "SecurityGroups[?GroupId=='$cluster_sg'].IpPermissions[].UserIdGroupPairs[].GroupId" \
    --output text) )

# how many in array
# print each sg

echo "Found ${#ingress_sgs[@]} Security Group Sources:"
for sg in "${ingress_sgs[@]}"; do echo "$sg"; done

# > Add ingress rules
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

# > Check the new ingress rules

echo "New ingress rules in sg $security_group_id"
aws ec2 describe-security-groups \
    --query "SecurityGroups[?GroupId=='$security_group_id'].IpPermissions[]"

# > Compare with the original main cluster security group ingress rules

echo "Ingress rules of cluster's main sg $cluster_sg (which should be the same)"
aws ec2 describe-security-groups \
    --query "SecurityGroups[?GroupId=='$cluster_sg'].IpPermissions[]"

# > Add this security group to new mount targets

# get private subnets of cluster vpc
subnet_ids=( $(aws ec2 describe-subnets \
    --query "Subnets[?VpcId =='$vpc_id' && MapPublicIpOnLaunch == \`false\`].SubnetId" \
    --output text) )

echo "Private subnets of cluster VPC: $vpc_id"
for sn in "${subnet_ids[@]}"; do echo "$sn"; done

# > For all subnets, add a mount target for the `efs_id`

echo "Adding mount targets in each private subnet for EFS"
for sn in "${subnet_ids[@]}";
  do aws efs create-mount-target \
    --file-system-id $efs_id \
    --subnet-id $sn \
    --security-groups $security_group_id
done

# > Get efs DNS

echo "EFS: $efs_id is set up"
```


#### Deleting EFS in preparation for cluster tear down

* Deleting file system

```shell
aws efs describe-file-systems
```

```shell
echo $AWS_DEFAULT_PROFILE
aws sts get-caller-identity
echo $hub_ns

# if jupyterhub release running ... should remove
# may need to delete pods (can use admin page in jupyterhub)
helm uninstall jhubproto --namespace $cluster_name

mount_tgs=( $(aws efs describe-mount-targets \
    --file-system-id $efs_id \
    --query 'MountTargets[].MountTargetId' \
    --output text) )

for mtg in "${mount_tgs[@]}"; do echo $mtg; done

for mtg in "${mount_tgs[@]}";
  do aws efs delete-mount-target \
      --mount-target-id $mtg
done

aws efs delete-file-system \
    --file-system-id $efs_id

```


* Remove the EFS security group

```shell
echo $security_group_id
aws ec2 delete-security-group \
    --group-id $security_group_id

```

```shell
aws ec2 describe-security-groups \
    --query 'SecurityGroups[][GroupName, GroupId, VpcId]' \
    --output table

```

* After this, the cluster can be torn down


### Configuring the Cluster

* `test_efs.yaml`
  - **Requires the `EFS` `DNS` (copy from the console) or terminal (`$efs_id`)**

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-persist
spec:
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: fs-04b62bc3f1e1652be.efs.ap-southeast-2.amazonaws.com
    path: "/"
```

* Uses `efs_id` from above
* Uses `aws configure get region` to get the region set in your aws configuration using the current default profile.

```bash
cat >./test_efs.yaml <<EOL
apiVersion: v1
kind: PersistentVolume
metadata:
  name: efs-persist
spec:
  capacity:
    storage: 50Gi
  accessModes:
    - ReadWriteMany
  nfs:
    server: $efs_id.efs.$(aws configure get region).amazonaws.com
    path: "/"
EOL
```

* `test_efs_claim.yaml`

```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: efs-persist
spec:
  storageClassName: ""
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 50Gi
```

* Write out the claim ... no metadata needed

```shell
cat >./test_efs_claim.yaml <<EOL
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: efs-persist
spec:
  storageClassName: ""
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 50Gi
EOL
```

* If you haven't deployed the jupyterhub helm chart yet, you can do that afterwards, **but you should first create a namespace for the jupyterhub services/pods etc** with `kubectl create namespace NAMESPACE`

```shell
hub_ns='jhub-proto'
echo "Creating namespace: $hub_ns"

kubectl create namespace $hub_ns

echo "Creating namespace: $cluster_name"

kubectl create namespace $cluster_name
```

* Apply the persistent volume parameters

```shell
kubectl --namespace=$cluster_name apply -f test_efs.yaml
kubectl --namespace=$cluster_name apply -f test_efs_claim.yaml

# check
kubectl get pv
kubectl get pvc -n $cluster_name
```

* Edit config to contain something like the following under `singleuser`
  - best parameters for `EFS` yet to be determined??

```yaml
singleuser:
  ...
  storage:
    type: none
    extraVolumes:
      - name: efs-persist
        persistentVolumeClaim:
          claimName: efs-persist
    extraVolumeMounts:
      - name: efs-persist
        mountPath: /home/shared
```

* update release
  - Good to run `kubectl get pod -n jhub-proto --watch` in another terminal and watch the `hub-...` pod.
  - It will have two stages, an `Init: 0/1` stage, followed by a `PodInitializing` and finally `Running` stage.
  - It can take `~5 mins` and is due to the initial pre-startup pod preparing the new EFS.
  - _If there's an error, or the pod doesn't get beyond `Init: 0/1`, then there's likely a problem, and probably with the setup of the EFS and the cluster's `PV` and `PVC` configuration._

```shell
helm upgrade --cleanup-on-fail \
  --install $cluster_name jupyterhub/jupyterhub \
  --namespace $cluster_name \
  --create-namespace \
  --version=1.1.3 \
  --values config.yaml

```

* Check on cluster

```shell
kubectl get pod -n jhub-proto
```

* Get details about the hub pod ... _especially if there's a problem_
  - Hint ... the efs mounting is a likely issue ... and should be seen in the events ...

```shell
hub_pod_name=$(kubectl get pod -n jhub-proto | grep hub | awk '{print $1}')
kubectl describe pod -n jhub-proto $hub_pod_name
```

* Check on the persistent volumes

```shell
kubectl describe pv -n jhub-proto

kubectl describe pvc -n jhub-proto
```


#### Delete persistent volumes

```shell
# check
kubectl get pv
kubectl get pvc -n jhub-proto
```

```shell

kubectl delete pvc -n jhub-proto efs-persist
kubectl delete pv efs-persist
```

* If `pv` or `pvc` get stuck "terminating", it usually means something hasn't been done in the "correct" order ... these commands/patches might rectify things

```shell
# seems to 
kubectl patch pvc -n jhub-proto efs-persist -p "{\"metadata\":{\"finalizers\":null}}"

kubectl patch pv efs-persist -p "{\"metadata\":{\"finalizers\":null}}"
```


## Providing an Image for user pods

* Add following to `config.yaml`

```yaml
singleuser:
  image:
    name: pythoncharmers/jupyter-docker-stacks
    tag: 6a6ef3eaa02d
# ...
```

* Update the `helm release` (same as usual)
  - This will take longer the first time as the cluster will have to pull the new image from `DockerHub` (or wherever it is installed ... maybe store on AWS somewhere?)
  - You can observe this with `kubectl get pod -n jhub-proto --watch` and pay attention to the `hook-image-puller-XXXX` pod ... it will probably stay in `Init: 1/2` for a while.
  - You could go further and look at the events of the pod with `kubectl describe pod -n jhub-proto hook-image-puller-XXXX`.  You should see the latest even describing that it is pulling the new image ... _be patient 😉_

```shell
helm upgrade --cleanup-on-fail \
  --install jhubproto jupyterhub/jupyterhub \
  --namespace jhub-proto \
  --create-namespace \
  --version=1.1.3 \
  --values config.yaml

```

