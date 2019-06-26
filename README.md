#### What is it?

`EKStender` is a tool that extends a vanilla Amazon EKS cluster with a number of add-on OSS projects.

#### What problem does EKStender solve?

The tool is aimed at bridging the gap that exists between a vanilla K8s deployment (too basic for some operational requirements) and very opinionated platforms built on top of K8s (too opinionated for many use cases).

`EKStender` is not intended to be a production tool nor a product per se. It is more of a prototype (or EKSperiment?) that intercept the needs of developers and IT of building something that sits in between a CaaS and a PaaS (for lack of better terminology). 

Without `EKStender` users of EKS would need to deploy manually the add-on components they need. `EKStender` automates those tasks by enabling said tools. See below for a list of these add-ons.  

#### What's the status of EKStender?

Claiming that this is WIP is an euphemism. It's likely never going to be "done". In its current shape and form this tool should only be considered a basis for something that could be picked up by (and embedded into) more structured utilities, some of which are already shipping with [eksutils](https://github.com/mreferre/eksutils). Such as, for example, [eksctl](https://github.com/weaveworks/eksctl). 

The bash code included in `ekstender.sh` is no magic and comes from multiple sources. A good source has proven to be the [eksworkshop](https://eksworkshop.com/). Other sources have been the official EKS documentation as well as how-to guides of the various OSS projects. The largest amount of time has been spent on building the deployment flow. 

Note: while `EKStender` may come handy for quick tests, demos and learning sessions, some of the default choices in the deployment flow do not follow standard best practices (e.g. exposing the Kubernetes Dashboard via an external load balancer). Do not do this in a production setup! 

`EKStender` would/should work with a regular upstream K8s setup but this was only tested with Amazon EKS (and in particular with setups done with [eksctl](https://github.com/weaveworks/eksctl)).

#### What stack does EKStender deploy?

This is a list of modules, features and configurations that `EKStender` enables on a vanilla EKS cluster (deployed with eksctl):

-  CloudWatch Container Insights
-  Helm tiller service
-  Kubernetes Dashboard (by default it is also exposed through a Load Balancer, but you can opt out)
-  ALB Ingress controller 
-  Calico network policy engine  
-  Prometheus (by default it is NOT exposed through a Load Balancer, not that it should!)
-  Grafana (exposed through a Load Balancer)
-  Metric Server (to allow for Horizontal Autoscaler to work)
-  Cluster Autoscaler 
-  The [yelb](https://github.com/mreferre/yelb) demo application (exposed through the ALB Ingress Controller)

In addition to the above, a multi-purpose `eks-admin` Service Account is created: it can be used to login into the Dashboard via grabbing its token. 

The following picture shows a graphical representation of the outcome of running `EKStender`

![Ekstender](ekstender.png)

#### What other modules and tools are under consideration?

Other modules and tools that are under considerations to be added and enabled are:

- AWS Service Operator for Kubernetes
- AppMesh 
- Istio
- Kiali (https://aws.amazon.com/blogs/opensource/observe-service-mesh-kiali/)
- X-Ray
- efs-provisioner 
- spekt8 (https://github.com/spekt8/spekt8) 
- Spinnaker
- JenkinsX
- Kubeflow 

Any feedback is greatly appreciated.

#### Getting started

It is assumed that a cluster exists and that kubectl can talk to it without further configurations (e.g. no need to specify the `--kubeconfig` option). It is suggested leveraging `eksctl` to create the cluster and this is a good starting point:
```
eksctl create cluster --name=eks1 --nodes=3 --nodes-min=2 --nodes-max=4 --ssh-public-key=<key name> --region=<region> --asg-access
```

The best way to use `EKStender` is from within an [eksutils](https://github.com/mreferre/eksutils) shell. 

Clone the EKStender project with `git clone https://github.com/mreferre/ekstender`, move inside the `ekstender` directory and edit the `ekstender.sh` file. 

You need to check the variable session at the beginning. At a minimum, you should set the `REGION`, `CLUSTERNAME`, `NAMESPACE`, `AUTOSCALINGGROUPNAME` and `NODE_INSTANCE_ROLE` variables to values that represents your specific setup. The `NODE_INSTANCE_ROLE` variable should be set to the value of the `NodeInstanceRole` output in the nodegroup Cloudformation stack. (see the known issues and limitations below for more information).

A convenient alternative to edit the script is to set these variables in the shell before launching it. The script will check if the variables exist and, if they do, it won't try to set them again. This is an example of how you would set those variables:

```
export REGION=us-west-2
export CLUSTERNAME=eks1
export NODE_INSTANCE_ROLE=eksctl-eks1-nodegroup-ng-XXXXXXX-NodeInstanceRole-XXXXXXXXXXXX
export AUTOSCALINGGROUPNAME=eksctl-eks1-nodegroup-ng-XXXXXXX-NodeGroup-XXXXXXXXXXX
export MINNODES=2 
export MAXNODES=4
export EXTERNALDASHBOARD=yes 
export EXTERNALPROMETHEUS=no 
export DEMOAPP=yes 
export NAMESPACE="kube-system"
```

Once this is done, you can run `./ekstender.sh` from the `eksutil` shell. `EKStender` should work from other shells (provided you have all the tools configured e.g. kubectl, AWS CLI, jq, helm, etc. etc.). Note that `EKStender` logs by default to a file called `ekstender.log` in the directory where you launch it. If you use it from within `eksutil` note that the file will not persist when you exit the container (you can easily fix it by mounting a directory and log there instead).

A good by-product of using kubectl to deploy these add-ons is that it makes the script idempotent by nature. You can run it multiple times against the same cluster. Since some of the tools use Helm (which is deployed by `EKStender` early in the flow) for their own setup, it required a bit of if-then-else logic to make the script fully idempotent. 

The repo includes an experimental `cleanup_ekstender.sh` script that is intended to roll-back the setup of the `EKStender` modules. Never run this cleanup script (nor `./ekstender.sh` for that matter) on a production cluster.

#### Known issues and limitations

There are just too many to list all of them. Some notable limitations are:

- The file `ekstender.sh` needs to be manually edited to enter the name of the cluster, the instance role name and the region for it to work properly. Some level of automation can be achieved to extract these info but there are lot of corner cases (e.g. an environment with multiple clusters/contexts defined) where this may be difficult to achieve properly
- Because some of the tools and projects require additional IAM policies to be attached to the nodes, `EKStender` adds those policies to the IAM roles identified by the `NODE_INSTANCE_ROLE`. The script only supports one role and hence one `eksctl` nodegroup. If you have more than one nodegroup you could try to add those policies manually to the other roles
- Perhaps it would make more sense to be able to selectively deploy what a user needs Vs. deploying everything regardless. This could be achieved by either creating an interactive setup (e.g. "chose what you want to deploy from this list") or by setting environmental variables inside the script in the user inputs section (e.g. what has already been done with `export DASHBOARD=yes`)
- In theory you should be able to deploy in a namespace that is not `kube-system`. In practice deploying into a namespace that is not `kube-system` won't work. Right now all deployments are being done in `kube-system`


