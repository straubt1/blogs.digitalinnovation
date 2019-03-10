---
layout: post
post_title: Dockerize DevOps Workflows
---

"It works on my machine" is often associated with application development when a developer makes a change that works locally but ends up breaking something in production. We have all been there, trying to run a command line utility and something isn't right, something has changed, and your peer responds with "I can run it from my machine".  Sound familiar?

While working on DevOps in Azure I am constantly using the Azure CLI, Terraform, and Ansible. The Azure CLI and Ansible both require Python, and it just so happens that they can use different versions as well. Of course Python versions can run side by side with each other and for a long time things just worked. Until they didn’t… So how can Docker help?

What if we build a docker image that can be used to setup an environment that is purpose built for the utility we are trying to run?

Hers is a breakdown the problems we are trying to solve:

* Running workflows locally doesn’t always work.
* Working with a new tool that may take some time to get setup and we need to ensure the team can easily use that workflow.
* Enable a workflow to run on a build server.
* Changes can be made to the workflow without breaking everything.

Docker to the rescue.

Let's go through an example that is "for the sake of argument/blog post" and just so happens to be real and something I use everyday.

I am a member of a Cloud DevOps team that is responsible for creating, configuring and maintaining cloud infrastructure in Azure. A common and very powerful tool at my disposal is the Azure CLI 2.0. My goal is to create a docker image that my team and I can use.

The high level steps that I will perform are as follows, keep in mind that these steps could be done regardless of what utility you wish to "dockerize":

1. Create a github repo that contains a `Dockerfile`.
2. Build and test the image locally to ensure things are working as expected.
3. Create a DockerHub repo to store the docker image for all to see and use.
4. Setup continuous image building to capture changes to the image.
5. Share with the team.

Let's get started.

## Setup Docker

Visit [https://docs.docker.com/engine/installation/](https://docs.docker.com/engine/installation/) and follow the setup for your operating system.

The folks at docker.com have made it very easy to install Docker so you shouldn’t have any problems here. For this I happen to be using Docker For Windows which allows me to build linux and windows images.

We can ensure docker is running by firing up our favorite terminal and running a `docker version` command.

You should see something like this:

```bash
$ docker version
Client:
 Version:      17.06.2-ce
 API version:  1.30
 Go version:   go1.8.3
 Git commit:   cec0b72
 Built:        Tue Sep  5 20:00:17 2017
 OS/Arch:      linux/amd64

Server:
 Version:      17.06.2-ce
 API version:  1.30 (minimum version 1.12)
 Go version:   go1.8.3
 Git commit:   cec0b72
 Built:        Tue Sep  5 19:59:19 2017
 OS/Arch:      linux/amd64
 Experimental: true
```

## Setup git repository

We need a place to put all of our hard work, so let's create a git repository and push our initial changes to [https://github.com/](https://github.com/).  
This is straight forward but if you need some help head over here for more information [https://help.github.com/articles/create-a-repo/](https://help.github.com/articles/create-a-repo/)  
Once this is set up we are ready to start adding files. It is always a good idea to create a README.md file to describe your repository.

## Dockerfile

A Dockerfile represents how our docker image will be built and there is a lot you can do in a `Dockerfile`, but everything we will do here is going to be very simple so don't stress the specifics. If you need to know more take a look at the docs [https://docs.docker.com/engine/reference/builder/](https://docs.docker.com/engine/reference/builder/).

We need to setup an environment that can run the Azure CLI. Normally this would involve digging into the requirements, python in this case, and adding all the things that the Azure CLI requires. Lucky for us the Azure CLI team has done this already, so we will just layer on top of what they have already done. You can take a deeper look at what they are doing in this image by checking out their [Dockerfile](https://github.com/Azure/azure-cli/blob/master/Dockerfile "Dockerfile").

Rather than repeat what they have done in their image, we will just use their image as our base. This also has the added benefit that we can get any changes that the team developing the azure cli might make in the future. This turns out to be a huge benefit since Azure is constantly adding new resources and the ability to interact with those resources in the Azure CLI quickly is a must.

Here is the start of our `Dockerfile`:

```Dockerfile
FROM azure-cli:latest

CMD bash
```

Let's go ahead and build this and test out what we have. Here we will create our image with the name "azhelper" for easy reference.

```bash
> docker build -t azhelper .
Sending build context to Docker daemon  113.2kB
Step 1/2 : FROM azuresdk/azure-cli-python:latest
 ---> b95f51b22e75
Step 2/2 : CMD bash
 ---> Running in f0009bc62755
 ---> 404cf2421bd4
Removing intermediate container f0009bc62755
Successfully built 404cf2421bd4
Successfully tagged azhelper:latest
```

We can see that our image is now available:

```bash
> docker image list
REPOSITORY           TAG                 IMAGE ID            CREATED             SIZE
azhelper             latest              eaf6edd080b1        2 weeks ago         376MB
```

Now we can create our container which will drop us into the container and at the Bash command line:

```bash
> docker run -it azhelper
bash-4.3#
bash-4.3# ls
azure-cli  dev        home       linuxrc    mnt        root       sbin       srv        tmp        var
bin        etc        lib        media      proc       run        sys        usr
bash-4.3# exit
exit

>
```

Now that we are running a container where we can execute commands from, try to list your azure accounts by calling `az accounts list`.

```bash
bash-4.3# az account list
Please run "az login" to access your accounts.
[]
```

Oops, we need to login, try a `az login`.

```bash
bash-4.3# az login
To sign in, use a web browser to open the page https://aka.ms/devicelogin and enter the code ZZZZZZZZZ to authenticate.
```

Follow the instructions to authenticate against your azure credentials to get access.  
Try again to list your accounts:

```bash
bash-4.3# az account list
[
  {
    "cloudName": "AzureCloud",
    "id": "GUID",
    "isDefault": true,
    "name": "Subscription Name",
    "state": "Enabled",
    "tenantId": "GUID",
    "user": {
      "name": "EMAIL",
      "type": "user"
    }
  }
]
```

---

**Question**: Are we going to have to login every time?  
**Answer**: Yes! If we leave it this way.

---

To fix this problem, lets exit out of our running container and map a volume where our login access tokens can be stored and persisted outside the container.

Make sure we have a local folder to store the Azure CLI files:

```bash
mkdir ${HOME}/.azure
```

Now run the container again but let's add the volume:

```bash
docker run --rm -it -v ${HOME}/.azure:/root/.azure azhelper:latest
```

**NOTE:** If you are running this from a Windows machine you may need to update your syntax to `docker run --rm -it -v %HOME%/.azure:/root/.azure azhelper:latest`.

What are we doing here is mapping a volume to the host machine _into_ the container that can be used by the CLI to store needed information. This will allow us to start/stop the container and not require a login every time. Notice the `-it` which is what creates the interactive session with the Docker container, and the `--rm` which will remove the container once you exit.

At this point you may ask, what have we really done here? Why don’t we just use the azure-cli image directly. To that I say, but there is more!  
If you _just_ wanted the Azure CLI, you could simply use the base image above.

However, what if you wanted to add workflows that _used_ the Azure CLI? That is exactly what we want here and what we will do next.

## Taking another step

As anyone who uses the Azure portal  will tell you it can be a source of relief for quick tasks, and a source of immense pain for repeated tasks. Things quickly fall apart at scale and if you are dealing with hundreds of resources and is exacerbated if they are across multiple subscriptions.

As a DevOps engineer working in Azure, some of the common requests I get are:  
    • Start/Stop/Deallocate/Restart every VM in several resource groups  
    • Check the current power state of all VM's in several resources groups  
    • Given an IP address, what is the name of the VM

Back in our git repo lets add a scripts folder and some common `az` CLI calls. Everything is written in Bash since that is the shell we are using here. We will only cover a few to get us through the overall process, but there is room for expansion.

In the scripts folder I create a file `search.sh` that will contain functions that are related to searching for resources \(namely resource groups and VM's\). The calls here are basic but it should be obvious why having these available to you can save you a lot of time.

```bash
# search for Resource Group by name
function search-group () {
    query=$1
    az group list --query "[?name | contains(@,'$query')].{ResourceGroup:name}" -o table
}

# search for VM by name
function search-vms () {
    query=$1
    az vm list --query "[?name | contains(@,'$query')].{ResourceGroup:resourceGroup,Name:name}" -o table
}
```

**Note:** The query language used by the Azure CLI 2.0 is a standard called [JMESPath  ](http://jmespath.org/)which is a far cry from the where we were with the CLI 1.0 that had no built in querying. Instead you were forced to output in JSON and pipe to something like [jq](https://stedolan.github.io/jq/). Of course you could still use this approach for CLI 2.0, but I find the syntax much easier to follow for JMESPath, it is also a standardize spec.

We need to get this script into the container. We could just copy this single script, but knowing we are going to want to build on these scripts in the future, let's assume that we will have an entire folder of scripts.

```Dockerfile
COPY scripts/ scripts/
```

Next we need a way to load these scripts into the environment so that they are available when we run a container. Let's insert some dynamic Bash awesomeness into our `.bashrc` file so that this gets loaded at runtime.

```bash
RUN echo -e "\
for f in /scripts/*; \
do chmod a+x \$f; source \$f; \
done;" > ~/.bashrc
```

This may look a bit wild, but I assure you it is of the simplest intent. Any time that Bash loads, anything in the `scripts` folder will get sourced and the functions made available.

Our full `Dockerfile`:

```Dockerfile
FROM azuresdk/azure-cli-python:latest

COPY scripts/ scripts/
RUN echo -e "\
for f in /scripts/*; \
do chmod a+x \$f; source \$f; \
done;" > ~/.bashrc

CMD bash
```

Let's fire up another build and start a new container.

```bash
> docker build -t azhelper .

...

> docker run --rm -it -v ${HOME}/.azure:/root/.azure azhelper:latest

bash-4.3# search-group testgroup
ResourceGroup
--------------------------
mytestgroup-1
mytestgroup-2
```
```
bash-4.3# search-group test
ResourceGroup
--------------------------
mytest1
mytest2
mytestgroup-1
mytestgroup-2
bash-4.3#
```

Things are looking good, we push our changes up to github to save all the good work.

## Dockerhub

So we have created this awesome little image to run the Azure CLI from anywhere, and even have room to grow with handy functions for common use. But all this docker building seems a lot like shipping code and requiring the end user to build it, let's address this next.

Remember I told you I was a DevOps Engineer and how good would I be if I left this in a state that required manually building and pushing up any time there was a change?

We are going to use [Dockerhub](https://hub.docker.com/) since this is a completely open source and public image \(we also get automatic builds\), but the same concepts could be applied to a private/on-prem setup.

In Docker for Windows we can login to our Dockerhub account which will let us push our image that we built locally.

```bash
# Tag our local image
docker tag azhelper straubt1/azhelper
# Push our image up to Dockerhub
docker push straubt1/azhelper:latest
```

Login to [Dockerhub](https://hub.docker.com/) and view the dashboard where we should see the image we pushed.

Now lets add an integration to the github repo to allow for automatic builds.

**Note:** Dockerhub will only provide this free service if the github repo and docker image are both publicly available. If this were private/on-prem, similar output could be found by using your build server to handle this for you.

In the Dockerhub repository, click on "Build Settings" and connect the repository to your github repository.

Once the integration is done we can set up triggers to determine when to build a new image and what tags to apply. For this example I am going with the most basic, check-ins on the master branch will result in a new build that is tagged `latest`.

If I go to the "Build Details" pages I can see all the builds and their status.  
![](/assets/Dockerhub-BuildDetails.png)

These steps should look familiar to what you were seeing locally, but now it is all done in the cloud.

> Using two cloud hosted services \(github.com and dockerhub.io\) to build a docker image that contains a CLI tool used for deploying/configuring cloud services

## Conclusion

We took a utility that we use locally, dockerized it, added some additional functionality and now everyone on your team can access it.

Running in this manner should eliminate the "it doesn’t work anymore" problems since everyone is running the same container. As changes to the image are made, all that is needed is a simple `docker pull <image>` from the public dockerhub.

Of course we have also have solved another problem. What if I have a need to access the Azure CLI from a build server? Well, now all you need is this image and the ability to map credentials into the container.

This has been a simple yet powerful example of how to dockerize a utility.

## Resources

github repo - [/straubt1/azhelper](https://github.com/straubt1/azhelper/tree/csg-blog)  
dockerhub repo - [/straubt1/azhelper](https://hub.docker.com/r/straubt1/azhelper/)

