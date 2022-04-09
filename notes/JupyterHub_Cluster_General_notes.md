# Intro

## Building The Image

* server-notebook
* Main points of configuration
  - Which image to base it on (see top of dockerfile)
    + major considerations are: compatibility with jupyterlab and current version of jupyter helm version (see [JupyterHubs Helm Repository Version Table](https://jupyterhub.github.io/helm-chart/)) and compatibility with whatever jupyter tooling we're interested in
  - Installation with requirements and conda-requirements
  - Manual installation throughout the dockerfile


* Push up to pythoncharmers' Docker Hub account for pull down by Kubernetes and AWS/EKS

## Building The Cluster

### General Resources

* [JupyterHub: From Zero to Kubernetes](https://zero-to-jupyterhub.readthedocs.io/en/latest/index.html)
  - [AWS Guide to EKS](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html)
  - [Section on LDAP Authentication](https://zero-to-jupyterhub.readthedocs.io/en/latest/administrator/authentication.html?highlight=ldap#ldap-and-active-directory)
    + [LDAP Authenticator GitHub Repo](https://github.com/jupyterhub/ldapauthenticator)
  - [JupyterHub Helm Chart Reference Docs](https://zero-to-jupyterhub.readthedocs.io/en/stable/resources/reference.html#singleuser-defaulturl)
  - [JupyterHub Helm Chart Defaults](https://github.com/jupyterhub/zero-to-jupyterhub-k8s/blob/HEAD/jupyterhub/values.yaml)
* [JupyterHubs Helm Repository Version Table](https://jupyterhub.github.io/helm-chart/)
  - [GitHub Repo](https://github.com/jupyterhub/zero-to-jupyterhub-k8s)
  - [Changelog on GitHub](https://github.com/jupyterhub/zero-to-jupyterhub-k8s/blob/HEAD/CHANGELOG.md)
  - [JupyterHub Docker Image repo for Kubernetes (Z2K8)](https://github.com/jupyterhub/zero-to-jupyterhub-k8s/tree/main/images/hub)
* [Native Authenticator Documentation](https://native-authenticator.readthedocs.io/en/latest/)
  - [Native Authenticator Repo](https://github.com/jupyterhub/nativeauthenticator)
  - [Old GitHub Issue on use of Native Authenticator](https://github.com/jupyterhub/zero-to-jupyterhub-k8s/issues/1398)
* [Jupyter Docker Stacks Images](https://jupyter-docker-stacks.readthedocs.io/en/latest/using/selecting.html)
* [JupyterHub GitHub Repo](https://github.com/jupyterhub/jupyterhub)
* **AWS and Kubernetes Resources**
  - [eksctl Homepage](https://eksctl.io/introduction/)
  - [`kubectl` cheat sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
  - [kOps Install](https://github.com/kubernetes/kops/blob/HEAD/docs/install.md)
    + New tool for managing Kubernetes clusters recommended by Jupyter people ... _not sure if necessary_
* [Kubernetes docs on init containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)
* [LDAP Image Repo](https://github.com/osixia/docker-openldap#beginner-guide)
* [ArtifactHub Helm Charts Repository](https://artifacthub.io)
  - [LDAP Helm Chart Using Repo Above](https://artifacthub.io/packages/helm/geek-cookbook/openldap)


#### Additional Links and Resources

* [JupyterHub Image Build for Z2JH](https://github.com/jupyterhub/zero-to-jupyterhub-k8s/blob/main/images/hub/requirements.txt)
  - Good for noting what dependencies are available by default




### EKS on AWS

Follow the [Z2JH Guide](https://zero-to-jupyterhub.readthedocs.io/en/latest/kubernetes/amazon/step-zero-aws.html) which mirrors the [AWS Guide to EKS](https://docs.aws.amazon.com/eks/latest/userguide/getting-started.html).

#### Prerequisites

* CLI Tools:
  - `kubectl`: 1.21+
    + Check version: `kubectl version --short --client`
  - `eksctl`: 0.66+
    + Relies on `aws` installed and linked to AWS authentication
  - `helm`: >=3.5
    + See [Helm Installation Docs](https://helm.sh/docs/intro/install/)


```shell
kubectl version --short --client
# information about server is about the actual cluster configured to access (see context)
kubectl version

eksctl version
eksctl info

helm version --short
```

##### kubectl

* Install:  [AWS Installation Guide `kubectl`](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html)

##### eksctl

* Install: [AWS Installation Guide `eksctl`](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html)
* Get help with `eksctl --help` or `eksctl COMMAND --help`

##### helm

* Install: [Helm Installation Docs](https://helm.sh/docs/intro/install/)


#### Create Cluster

* Default steps ...


* Using `eksctl` 
* **Uses the provided aws profile (`-p/--profile PROFILE`) or default**

```shell
eksctl create cluster -n <cluster_name>
````

```shell
eksctl create cluster -n jhubproto \
  --nodegroup-name base-ng \
  --node-type m5.large \
  --nodes 1 \
  --nodes-min 1 \
  --nodes-max 2
```

* Other options available
  - Can also run from yaml file
* Creates nodegroup and nodes and subnets etc

* **Can specify availability zone with `--zone`?**
  - See [eksctl docs on zone aware auto scaling](https://eksctl.io/usage/autoscaling/#zone-aware-auto-scaling)


* `kubectl get nodes` should list nodes
  - `kubectl get nodes --watch`
* `eksctl get cluster --profile <aws_profile>` should work too too
* Can **delete** cluster with `eksctl delete <CLUSTER_NAME> `


#### Configure `kubectl` for cluster

* See [AWS Guide to Create `kubeconfig`](https://docs.aws.amazon.com/eks/latest/userguide/create-kubeconfig.html)
  - `aws eks --region <region-code> update-kubeconfig --name <cluster_name>`
* Should see output with `kubectl get svc`
* Listing all global options: `kubectl options`

##### Testing AWS IAM setup

* `aws` CLI uses IAM with `kubectl`.
* Uses the same credentials that are directly returned by:

```bash
aws sts get-caller-identity --profile PROFILE
```


##### Location of `kubectl` configuration

* See `kubectl config` for automatic help and options
* Configuration gathered from (in this order of precedence, from `kubectl config`):
  - `--kubeconfig PATH` - **only single config file**
  - Merge multiple config files from paths in `$KUBECONFIG` env variable, delimited by convention on OS
  - `else if` ... use only `${HOME}/.kube/config`.


#### List contexts and clusters

```shell
# see current context
kubectl config current-context
# see options
kubectl config --help
# get all available contexts
kubectl config get-contexts
kubectl config get-contexts -o 'name'
# use full name of context to switch
kubectl config use-context arn:aws:eks:ap-southeast-2:863275378519:cluster/JupyterHub
```

Some useful bash functions

```shell
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

```

Usage

```shell
kb_context            # return current context
kb_context_list_all   # enumerate all, highlight current
kb_context_set N      # set context row N from list_all
kb_context
```

##### eksctl

See also ...

```shell
# can use aws profiles
eksctl get cluster --profile pychm
# or use default
eksctl get cluster
```

##### Other kubectl tips

* in `~/.kube/config` are listed all the _clusters_, _contexts_ and _users_ that have been configured with `kubectl` (all configured at the top level).
* The current context is also listed at the top level.
* In the _users_ section is defined how access is authenticated for each cluster.
  - Manipulating this is straightforward if necessary, as it mostly defines what command line command and arguments are run


#### Add Nodes

* Use `eksctl`, or rely on `eksctl` to create automatically when making a cluster the easy way.


#### Reduce or scale nodes


* Can scale nodes to zero (to save money)?
  - This may not be guaranteed to work, but as of 2022-03-13 seems to work?
    + See [AWS Issue](https://github.com/aws/containers-roadmap/issues/724) and somewhat related [kubernetes autoscaler issue on scaling up from 0 nodes](https://github.com/kubernetes/autoscaler/issues/1580)
  - You will probably observe a single instance persisting

```shell
eksctl scale nodegroup --cluster jlabproto2 --name ng-e6dd837d --nodes 0 --nodes-min 0
```

* Can scale back up by providing `--nodes 1` and `--nodes-min 1`


### JupyterHub on Cluster

* Use `helm`
  - **NB** ... uses the current _kubectl context_ ... see `kubectl` notes on how to change context


* Get jupyterhub helm chart

```bash
# list repos
helm repo list

# add jupyterhub repo
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/

# update
helm repo update
```

* **Push chart up to the cluster**
  - `--version`: which version of the helm chart to use (see docs/resources above)
  - `--values config.yaml`: this as local file that you **should make first**
    + See [Z2JH Docs](https://zero-to-jupyterhub.readthedocs.io/en/stable/jupyterhub/installation.html)
    + Doesn't need anything to start, but can add configuration customisations as need be
    + See [Z2JH Docs on Customisation](https://zero-to-jupyterhub.readthedocs.io/en/stable/jupyterhub/customization.html#customization-guide) and [Z2JH Customisation Reference](https://zero-to-jupyterhub.readthedocs.io/en/stable/resources/reference.html#helm-chart-configuration-reference)

```bash
helm upgrade --cleanup-on-fail \
  --install jlabproto2 jupyterhub/jupyterhub \
  --namespace jlabproto2 \
  --create-namespace \
  --version=1.1.3 \
  --values config.yaml
```


* Use `helm list` to list charts/releases
  - **dependent on which context is currently used by `kubectl`**


* Use `kubectl --namespace=jhubproto2 get svc proxy-public` to get URL of 


#### LDAP

* Need to add LDAP node/pod to cluster
* Use a chart from `ArtifactHub`
  - eg https://artifacthub.io/packages/helm/geek-cookbook/openldap/1.2.4
  - These will tend to use the image provided by `osixia`: [openldap image](https://github.com/osixia/docker-openldap#administrate-your-ldap-server)


```shell
# make sure in correct context (kb_context)
helm repo add geek-cookbook https://geek-cookbook.github.io/charts/

# check by listing repos
helm repo list
```

```shell
# install using custom config in ldap_config.yaml and name "ldap-proto" (only dashes "-" and dots "." allowed in name)
helm install -f ldap_config.yaml ldap-proto geek-cookbook/openldap
```

* Server address for the purposes of the JupyterHub config:
  - should be: `<RELEASE_NAME>-openldap.<NAMESPACE>.svc.cluster.local`
  - This follows the basic format of `<service-name>.<namespace>.svc.cluster.local`
    + The service name can be derived from `kubectl` with `kubectl get svc` which will list all services
    + The `CLUSTER_NAME` or `namespace` should be available through `eksctl get cluster` or, for the `namespace`, `kubectl get svc -o json`
      * eg: `kubectl get svc -o json | jq ".items[].metadata | .name, .namespace"`
* ldap server now running as a pod and should be accessible through kubectl port forwarding:
  - eg: `kubectl port-forward svc/<service-name> --namespace default 38900:389` which will provide access on the local machine at 38900
  - You can access the LDAP adminPassword and configPassword using:

```shell
  kubectl get secret --namespace jhubproto2 ldap-proto-openldap -o jsonpath="{.data.LDAP_ADMIN_PASSWORD}" | base64 --decode; echo
  kubectl get secret --namespace jhubproto2 ldap-proto-openldap -o jsonpath="{.data.LDAP_CONFIG_PASSWORD}" | base64 --decode; echo
```

* Interacting with the LDAP server (see general LDAP notes)
  - Can check the credentials of any "account" with the following: 
    + `ldapwhoami -v -h localhost -p 38900 -D mail=errol@pythoncharmers.com,o=pythoncharmers,ou=users,dc=pythoncharmers,dc=com -x -W`
    + Requires that ldap port be forwarded (eg, with `kubectl port-forward ...`)
    + `-W` will prompt for password
    + If password and `dn` (ie, the "account") are correct, a success will be returned, else, a failure


* Interacting with the jupyterhub on the kubernetes cluster

```shell
# log into the hub pod
kubectl exec -it pod/hub-69fdcf79b7-xr946 /bin/bash

# check ldap3 version
cat /usr/local/lib/python3.8/dist-packages/ldap3/version.py
```

* Looking at logs:
  - `kubectl logs hub-7f5fb6d49f-wzj2t -n jhubproto`
  - Can see login issues there too


##### Current Status 2021-09-22

* LDAP running, but couldn't configure!
* Have exported from current ldap into `oldldif.ldif` (in the directory `/Users/errollloyd/Developer/jupyter_hub_kube_proto`) ...**this worked!!**
  - **some top level definitions seem to be missing, so adapting this old ldif could probably work**, as the issue in trying to apply the LDIF before was maybe that there was insufficient boilerplate.
  - 2021-09-29: using a more full ldif by adapting the `oldldif` cited above helped.  Can now access and manipulate the ldap server on the new cluster.  **But**, authentication with jupyterhub is not working.  All attempts to log in get a `500 Server Error`
    + JupyterHub Config is clearly off.  _could be the admin user config that needs to be fixed or even removed?_
    + Maybe remove admin config (compat with ldap issues?)
    + keep auth as simple to just get log in
    + Make sure passwords are working (with, eg, `ldapwhoami ...`)
  - Maybe an SSL or LDAP issue!
    + Downgrade to earlier versions of jupyterhub?
    + Use a different form of authentication?


* See possibilities of ensuring certification [in this openldap issue thread](https://github.com/osixia/docker-openldap/issues/543)
* Maybe the underlying images CA certs are out of date and the chart is pulling an old image? [see issue thread](https://github.com/osixia/docker-openldap/issues/506).
  - Maybe the tls config needs some love!
  - **Note Henry's Config has both tls and CA disabled!!**, maybe do the same!:

```yaml
tls:
  enabled: false
  secret: ""  # The name of a kubernetes.io/tls type secret to use for TLS
  CA:
    enabled: false
    secret: ""
```

* Maybe don't name the service `ldapXXX` ... try `authenticator` or something?
  - There's a problem with kubernetes and `ldap` and collisions with the names
* Maybe try and troubleshoot with attempting direct access to the LDAP server [like in this issues discussion](https://github.com/jupyterhub/ldapauthenticator/issues/194).
* Try older version of the Helm chart
  - ran into problems with older versions of helm (for v0.9.1) ... the load balancer was inappropriately configured.
* Try different LDAP chart
* Try different means of authentication


### Native Authenticator

* Alternative authenticator that runs directly on the `JupyterHub` `hub...` pod, using the main `sqlite` database and a relatively straight-forward codebase.  Good for small-medium user sizes.
* Now included in the **Z2JH JupyterHub Image by default.**
  - See [zero-to-jupyterhub-k8s/images/hub/requirements.txt](https://github.com/jupyterhub/zero-to-jupyterhub-k8s/blob/f0ce9477834e5da73d53b341db845527f352df05/images/hub/requirements.txt)
* Relies on admin users to approve or disapprove prospective users who are, by default, enabled to signup from the main login/signup page.

#### Workflow for New Admin user

* A little clunky.
* An admin user has their username defined in the config for the release
* To login for the first time, they must _signup_ from the main page as though they don't have an account yet.  If they signup with the username reserved for an admin, then the password they provide in the signup process will become their password and their account will have admin privileges.

#### URLs

* `HUBURL/signup`
* `HUBURL/login`
* `HUBURL/change-password`: change your own password
* `HUBURL/authorize`: for **admins only**, dashboard for authorizing new users
* `HUBURL/change-password/SOME_USER_NAME`: **admin only**, change password for a particular user. 
  - should be available via a button in the `authorize` dashboard ?? 



#### Hacking Native Authenticator



* Programmatically adding a user

```python
# HUBURL/signup is url
req.post(url_su, data={'username':'test_hack1', 'pw': 'hack auth test'})
```

* Programmatically authorizing a user:
  - `kubectl exec -it HUB_POD -n cluster namespace -- /bin/bash`
  - `sqlite3 jupyterhub.sqlite`
  - `update users_info set is_authorized = 1 where username = USER_NAME`
  - or ... just use the interface at `DOMAIN/hub/authorize`
    + Could be manipulated through HTTP requests?


```python
import requests
with req.Session() as s:
    # payload is {'username': USERNAME, 'password': PASSWORD}
    p = s.post('https://jhubproto.maegul.net/hub/login', data=payload)
    print(p.status_code, p.reason)

    # once logged in ... simply hit hub/authorize/USERNAME to toggle authorization

    # this is the HTML for the authorization page ... unnecessary as can simply hit URL to toggle
    # p2 = s.get('https://jhubproto.maegul.net/hub/authorize')
    # print(p2.text)

    p3 = s.get('https://jhubproto.maegul.net/hub/authorize/test')
    print(p3)
```


* all user information is stored `jupyterhub.sqlite` on the `hub` pod
  - `users_info` is the table
  - `is_authorized` column is binary ... easily changed to authorize
  - `opt_secret` is a little more complex
    + Uses `onetimepass` package to create secrets that are checked for validity with `onetimepass.valid_totp()`.  They are created with `base64.b32encode(os.urandom(10)).decode('utf-8')` (See `orm.py` in [the codebase](https://github.com/jupyterhub/nativeauthenticator/blob/main/nativeauthenticator/))


* Could just hack together the equivalent of a firstuse authenticator database (looks like it is made just from `dbm` with user and passwords)
  - Add it to the pod at initialisation
  - Import from first use only
  - restart the hub pod?


#### Resources

* [GitHub Issue on Z2JH Repo about NativeAuthenticator Use](https://github.com/jupyterhub/zero-to-jupyterhub-k8s/issues/1398)
* [JupyterHub Image Build for Z2JH](https://github.com/jupyterhub/zero-to-jupyterhub-k8s/blob/main/images/hub/requirements.txt)


#### Attempt at Custom Patch

* To be passed into `extraConfig` as a script
  - See [This example on jupyterhub discourse](https://discourse.jupyter.org/t/error-403-when-trying-to-authenticate-through-ad-fs/10475/7)

```python
"""
Custom Authenticator to use allow admin creation without open signup
"""

from nativeauthenticator.nativeauthenticator import (
  NativeAuthenticator, bcrypt)
from nativeauthenticator.handlers import LocalBase, admin_only, UserInfo

class AdminSignUpHandler(LocalBase):
  """admin API for adding users"""
  # this will be deprecated in jupyterhub 2.X, 
  # which will have more flexible roles
  @admin_only
  async def post(self):

    username = self.get_body_argument('username', strip=False)

    user_info = {
        'username': username,
        'pw': self.get_body_argument('pw', strip=False),
        'email': self.get_body_argument('email', '', strip=False),
        'has_2fa': bool(self.get_body_argument('2fa', '', strip=False))
    }
    taken = self.authenticator.user_exists(user_info['username'])
    # custom create user function `admin_create_user`
    user = self.authenticator.admin_create_user(**user_info)

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

    self.finish(message)


class AdminNativeAuthenticator(NativeAuthenticator):

  def get_handlers(self, app):
    # hope this super call works!
    return super().get_handlers(app).append(
        (r'/admin-signup', AdminSignUpHandler)
      )

  def admin_create_user(self, username, pw, **kwargs):
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
```


#### Custom Patch v2

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
            await super().post()

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


### Adding EFS

#### Resources

* [Z2JH Docs on using EFS (incomplete)](https://zero-to-jupyterhub.readthedocs.io/en/latest/kubernetes/amazon/efs_storage.html)
* [Old GitHub issue on JupyterHub EFS usage, that should be informative as it has some discussion there](https://github.com/jupyterhub/zero-to-jupyterhub-k8s/issues/421)
* [AWS Docs on their new EKS-EFS interface](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)
  - Maybe not the best choice as it might not be stabe??
  - See also [this Jupyter Forum discussion about using this interface](https://discourse.jupyter.org/t/mounting-efs-nfs-to-home-without-root-privileges/9837/4)
  - [AWS Docs on EFS Access Points](https://docs.aws.amazon.com/efs/latest/ug/efs-access-points.html)
* [Kubernetes Docs on why storageClassName is left empty, and PV and PVCs generally](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reserving-a-persistentvolume)
* Some random blogs/"tutorials"
  - https://computingforgeeks.com/eks-persistent-storage-with-efs-aws-service/
  - https://medium.com/survata-engineering-blog/using-efs-storage-in-kubernetes-e9c22ce9b500
  - https://stackoverflow.com/questions/69582999/aws-efs-eks-mount-volume-as-root
* [Kubernetes Docs on Init Containers](https://kubernetes.io/docs/concepts/workloads/pods/init-containers/)

#### Mount Targets and Subnets

* Need one mount target per availability zone.
* This is the case even if there are more than one subnets for a particular availability zone.
* See [AWS Docs on EFS](https://docs.aws.amazon.com/efs/latest/ug/manage-fs-access.html)
* And, to quote from the above:

> The illustration shows three EC2 instances launched in different VPC subnets accessing an Amazon EFS file system. The illustration also shows one mount target in each of the Availability Zones (regardless of the number of subnets in each Availability Zone).

> **You can create only one mount target per Availability Zone**. If an Availability Zone has multiple subnets, as shown in one of the zones in the illustration, **you create a mount target in only one of the subnets**. As long as you have one mount target in an Availability Zone, the EC2 instances launched in any of its subnets can share the same mount target.

#### Private and Public Subnets

* Clusters seem to have a public and private subnet for each availability zone
* Using the CLI, this can be discerned (?) from the `MapPublicIpOnLaunch` parameter (which takes a boolean value).
  - See the [AWS CloudFormation Documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ec2-subnet.html)

#### Custom Pod Image on JupyterHub Cluster

* Edit `config.yaml`:
  - `singleuser/image/[name, tag]`
  - See [Z2JH Customisation Reference for `singleuser`](https://zero-to-jupyterhub.readthedocs.io/en/stable/resources/reference.html#singleuser-image)


### Multiple Selectable Environments

* See [Z2JH Docs on selectable images](https://zero-to-jupyterhub.readthedocs.io/en/latest/jupyterhub/customizing/user-environment.html#using-multiple-profiles-to-let-users-select-their-environment)
  - Seems that the user can select which docker image they want to use

### Misc Tips and Tricks

* Deleting
  - Can use `kubectl delete` but likely to cause issues with helm releases
  - **Instead**, use `helm`: `helm list` and then `helm uninstall <RELEASE>`
  - **To delete a cluster(!!)**: `eksctl get cluster` followed by `eksctl delete <CLUSTER_NAME>`, which has the advantage that it will remove config parameters from `~/.kube/config`
  - To force a pod to delete (when stuck "terminating"): `kubectl delete pod --force --grace-period=0 jupyter-errol-40pythoncharmers-2ecom`

* Watching changes happen
  - add `--watch` flag
    + `kubectl get nodes --watch`
    + `kubectl get pods --watch`

* Viewing logs:
  - `kubectl logs -f POD -n NAMESPACE`
    + `-f` is for streaming (see the help)
  - Using the `describe` command is also useful and will show things `logs` won't, for instance when a pod has failed to start, `describe` will list events in the startup process:
    + `kubectl describe pod -n NAMESPACE POD-NAME`

### CLI Tools

- kOps
- kubectl
- helm

### JupyterHub
