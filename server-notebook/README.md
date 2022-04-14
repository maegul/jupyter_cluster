
Basic additions to jupyter/scipy-notebook.

Main aim is to allow easy management of python packaging via requirements.txt files.

requirements.txt file in this repo is copied to image and installed by pip.

Currently picked a build with v1.2.5 of JupyterLab


## Managing Docker Commands

To ease use (and create a kind of self documenting declarative cheat sheet), `./jupyterHub_docker_aliases` creates bash aliases for most commands necessary to create, test and push an image.

See this file for a quick reference on how to use the `docker` CLI.

Also, if not already done in a system's `.bashrc`, copy `./jupyterHub_docker_aliases` to an appropriate location (probably `~`) and run `source ~/jupyterHub_docker_aliases` to have the aliases available.  OR, preferably, add a line to the `.bashrc` of your system to source the file either directly from this repo or from a copy in `~`.

All the aliases start with `dk_`, after which TAB-complete is your friend.  The order of aliases in the file is __roughly__ in the order of usage in a typical workflow.

## Port forwarding: part 1

Run a new container from the image with:

    sudo docker run -p 8999:8888 pythoncharmers/jupyter-docker-stacks

This forwards port 8888 in the docker container to port 8999 on the EC2 instance.

## Port forwarding: part 2

For local testing / use on your desktop, you can use SSH port forwarding with:

    ssh -i .ssh/my_private_key.pem -NfL localhost:8900:localhost:8999 ubuntu@13.210.62.156

where 8900 is the port on your desktop to forward
      8999 is the port on the EC2 instance (which must also be mapped to the Docker container)
      13.210.... is the IP address of the EC2 instance
