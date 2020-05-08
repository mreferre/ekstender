#!/bin/bash

# Massimo Re Ferre' massimo@it20.info

###########################################################
###########                README               ###########
###########################################################
# This script adds a set of tooling on top of a vanilla EKS cluster
# This script is made available for demo and/or test purposes only
# DO NOT USE THIS SCRIPT IN A PRODUCTION EKS CLUSTER 
# If a cluster already exists, it is assumed your client environment is already pointing to it
###########################################################
###########            End of  README           ###########
###########################################################

###########################################################
###########              USER INPUTS            ###########
###########################################################
: ${REGION:=$(aws configure get region)}
: ${AWS_REGION:=${REGION}} 
: ${EXTERNALDASHBOARD:=yes}  
: ${EXTERNALPROMETHEUS:=yes}  
: ${DEMOAPP:=yes}  
: ${NAMESPACE:="kube-system"}
: ${MESH_NAME:="ekstender-mesh"}
: ${MESH_REGION:=${REGION}} 
export REGION
export AWS_REGION
export EXTERNALDASHBOARD
export EXTERNALPROMETHEUS
export DEMOAPP
export NAMESPACE
export MESH_NAME
export MESH_REGION
###########################################################
###########           END OF USER INPUTS        ###########
###########################################################

###########################################################
###########    EXTRACTING REQUIRED PARAMETERS   ###########
###########################################################
# scripts read $1 as clustername. If $1 is not used it exits
if [ -z "$1" ]; then "Please specify the cluster you want to EKStend!"; exit; else export CLUSTER_NAME=$1; fi
# export STACK_NAME=$(eksctl get nodegroup --cluster $CLUSTER_NAME --region $REGION  -o json | jq -r '.[].StackName')
export ACCOUNT_ID=$(aws sts get-caller-identity --output json | jq -r '.Account') # the AWS Account ID 
export NODE_INSTANCE_ROLE:=$(aws cloudformation describe-stack-resources --region $REGION --stack-name $STACK_NAME | jq -r '.StackResources[] | select(.LogicalResourceId=="NodeInstanceRole") | .PhysicalResourceId' )  # the IAM role assigned to the worker nodes
# export AUTOSCALINGGROUPNAME:=$(aws cloudformation describe-stack-resources --region $REGION --stack-name $STACK_NAME | jq -r '.StackResources[] | select(.LogicalResourceId=="NodeGroup") | .PhysicalResourceId')  # the name of the ASG
export CLUSTER_VERSION=$(aws eks describe-cluster --name $CLUSTER_NAME | jq --raw-output .cluster.version) # the major/minor version of the EKS cluster
export VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME | jq --raw-output .cluster.resourcesVpcConfig.vpcId) # the VPC ID of the EKS cluster
###########################################################
## DO NOT TOUCH THESE UNLESS YOU KNOW WHAT YOU ARE DOING ##
###########################################################
export LOG_OUTPUT="ekstender.log"
###########################################################
###########                                     ###########
###########################################################

logger() {
  LOG_TYPE=$1
  MSG=$2

  COLOR_OFF="\x1b[39;49;00m"
  case "${LOG_TYPE}" in
      green)
          # Green
          COLOR_ON="\x1b[32;01m";;
      blue)
          # Blue
          COLOR_ON="\x1b[36;01m";;
      yellow)
          # Yellow
          COLOR_ON="\x1b[33;01m";;
      red)
          # Red
          COLOR_ON="\x1b[31;01m";;
      default)
          # Default
          COLOR_ON="${COLOR_OFF}";;
      *)
          # Default
          COLOR_ON="${COLOR_OFF}";;
  esac

  TIME=$(date +%F" "%H:%M:%S)
  echo -e "${COLOR_ON} ${TIME} -- ${MSG} ${COLOR_OFF}"
  echo -e "${TIME} -- ${MSG}" >> "${LOG_OUTPUT}"
}

errorcheck() {
   if [ $? != 0 ]; then
          logger "red" "Unrecoverable generic error found in function: [$1]. Check the log. Exiting."
      exit 1
   fi
}

welcome() {
# ------------------
  figlet EKStender
# ------------------
  logger "red" "*************************************************"
  logger "red" "***  Do not run this on a production cluster  ***"
  logger "red" "*** This is solely for demo/learning purposes ***"
  logger "red" "*************************************************"
  logger "green" "These are the environment settings that are going to be used:"
  logger "yellow" "Account ID            : $ACCOUNT_ID"
  logger "yellow" "Cluster Name          : $CLUSTER_NAME"
  logger "yellow" "AWS Region            : $REGION"
  logger "yellow" "Node Instance Role    : $NODE_INSTANCE_ROLE"
  logger "yellow" "Kubernetes Namespace  : $NAMESPACE"
  logger "yellow" "External Dashboard    : $EXTERNALDASHBOARD"
  logger "yellow" "External Prometheus   : $EXTERNALPROMETHEUS"
  logger "yellow" "Mesh Name             : $MESH_NAME"
  logger "yellow" "Demo application      : $DEMOAPP"
  logger "green" "--------------------------------------------------------------"
  logger "green" "You are about to EKStend your EKS cluster with the following add-ons"
  logger "blue" "* A generic admin Service Account (eks-admin))"
  logger "blue" "* Calico (network policy engine)"
  logger "blue" "* Metrics server"
  logger "blue" "* CSI EBS drivers"
  logger "blue" "* CSI EFS drivers"
  logger "blue" "* CSI FSx drivers"
  logger "blue" "* Cluster Autoscaler"
  logger "blue" "* Kubernetes Dashboard"
  logger "blue" "* ALB ingress controller"
  logger "blue" "* Prometheus"
  logger "blue" "* Grafana"
  logger "blue" "* CloudWatch Container Insights"
  logger "blue" "* AppMesh controller and sidecar injector"
  logger "blue" "* Demo Application (Yelb)"
  logger "green" "Press [Enter] to continue or CTRL-C to abort..."
  read -p " "
}

admin_sa() {
  logger "green" "Creation of the generic eks-admin service account is starting..."
  template=`cat "./configurations/eks-admin-service-account.yaml"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "Creation of the generic eks-admin service account has completed..."
}

iam_oidc_provider() {
  logger "green" "Associating IAM OIDC provider..."
  eksctl utils associate-iam-oidc-provider --region=$AWS_REGION --cluster $CLUSTER_NAME --approve >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "Association of the IAM OIDC provider has completed..."
}

helmrepos() {
  logger "green" "Import of the stable Helm repo..."
  helm repo add stable https://kubernetes-charts.storage.googleapis.com/ >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  helm repo add eks https://aws.github.io/eks-charts >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  helm repo update >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "Import of the stable Helm repo has completed..."
}

calico() {
  logger "green" "Calico setup is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/calico.html 
  template=`curl -sS https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/release-1.6/config/v1.6/calico.yaml` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  logger "green" "Waiting for Calico pods to come up..."
  logger "green" "Waiting for the calico daemonset to come up on all nodes..."
  calicodaemon=`kubectl get ds calico-node -n kube-system` >> "${LOG_OUTPUT}" 2>&1 
  calicodaemondesired=`echo $calicodaemon | awk '{print $3}'` >> "${LOG_OUTPUT}" 2>&1 
  calicodaemonready=`echo $calicodaemon | awk '{print $5}'` >> "${LOG_OUTPUT}" 2>&1 
  while [[ $calicodaemondesired != $calicodaemonready ]]; do 
      calicodaemon=`kubectl get ds calico-node -n kube-system` >> "${LOG_OUTPUT}" 2>&1 
      calicodaemondesired=`echo $calicodaemon | awk '{print $3}'` >> "${LOG_OUTPUT}" 2>&1 
      calicodaemonready=`echo $calicodaemon | awk '{print $5}'` >> "${LOG_OUTPUT}" 2>&1 
      echo "waiting for the calico daemon to start on all nodes ($calicodaemondesire/$calicodaemonready)"
      sleep 1; 
  done >> "${LOG_OUTPUT}" 2>&1  logger "green" "Calico has been installed properly!"
}

metrics-server() {
  logger "green" "Metrics server deployment is starting..."
  # source: https://eksworkshop.com/scaling/deploy_hpa/ & https://docs.aws.amazon.com/eks/latest/userguide/metrics-server.html 
  ns=`kubectl get namespace metrics-server --output json | jq --raw-output .metadata.name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $ns = metrics-server ]]; 
      then logger "blue" "Namespace exists. Skipping..."; 
      else kubectl create namespace metrics-server >> "${LOG_OUTPUT}" 2>&1
      logger "blue" "Namespace created...";
  fi  
  chart=`helm list --namespace metrics-server --filter 'metrics-server' --output json | jq --raw-output .[0].name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $chart = "metric-server" ]]; 
      then logger "blue" "Metrics server is already installed. Skipping..."; 
      else helm install metrics-server stable/metrics-server --version 2.11.1 --namespace metrics-server  >> "${LOG_OUTPUT}" 2>&1 ;
  fi
  errorcheck ${FUNCNAME}
  logger "green" "Metric server has been installed properly!"
}

csiebs() {
  logger "green" "EBS CSI support deployment is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
  curl -o configurations/ebs-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/v0.4.0/docs/example-iam-policy.json >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  aws iam create-policy --policy-name Amazon_EBS_CSI_Driver --policy-document file://./configurations/ebs-iam-policy.json >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  aws iam attach-role-policy --role-name $NODE_INSTANCE_ROLE --policy-arn arn:aws:iam::aws:policy/Amazon_EBS_CSI_Driver >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master"
  errorcheck ${FUNCNAME}
  logger "green" "EBS CSI support has been installed properly!"
}

csiefs() {
  logger "green" "EFS CSI support deployment is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html
  kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master" >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "EFS CSI support has been installed properly!"
}

csifsx() {
  logger "green" "FSx CSI support deployment is starting..."
  # https://docs.aws.amazon.com/eks/latest/userguide/fsx-csi.html
  # A configuration policy file is required because one is not available on GH (the policy file is only available in the docs)
  aws iam create-policy --policy-name Amazon_FSx_Lustre_CSI_Driver --policy-document file://./configurations/fsx-csi-driver.json >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  eksctl create iamserviceaccount --region $REGION --name fsx-csi-controller-sa --namespace kube-system --cluster $CLUSTER_NAME --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/Amazon_FSx_Lustre_CSI_Driver --approve
  errorcheck ${FUNCNAME} 
  kubectl apply -k "github.com/kubernetes-sigs/aws-fsx-csi-driver/deploy/kubernetes/overlays/stable/?ref=master" >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME} 
  FSX_CSI_CONTROLLER_IAM_ROLE=$(eksctl get iamserviceaccount --cluster eks1 --namespace kube-system --name fsx-csi-controller-sa --output json | jq --raw-output `.iam.serviceAccounts[0].status.roleARN`) >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME} 
  # the annotation below is not required when using EKSCTL 
  #kubectl annotate serviceaccount -n kube-system fsx-csi-controller-sa eks.amazonaws.com/role-arn=$FSX_CSI_CONTROLLER_IAM_ROLE --overwrite=true >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME} 
  logger "green" "FSx CSI support has been installed properly!"
}

dashboard() {
  logger "green" "Dashboard setup is starting..."
  # source: installed via helm chart from helm hub
  helm install dashboard  stable/kubernetes-dashboard --namespace kube-system
  errorcheck ${FUNCNAME}
  if [[ $EXTERNALDASHBOARD = "yes" ]]; 
      then helm install dashboard  stable/kubernetes-dashboard --namespace kube-system --set=ingress.enabled=true,ingress.annotations="kubernetes.io/ingress.class: alb" >> "${LOG_OUTPUT}" 2>&1
           errorcheck ${FUNCNAME}
           logger "blue" "Warning: I am exposing the Kubernetes dashboard to the Internet...";
      else helm install dashboard  stable/kubernetes-dashboard --namespace kube-system
           logger "blue" "The Kubernetes dashboard is not being exposed to the Internet......";
  fi
  # If you opted not expose the dashboard via the ELB, start the proxy like this: kubectl proxy --port=8080 --accept-hosts="^*$" 
  # and connect to: http://localhost:8080/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login
  # grab the token: kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')
  logger "green" "Dashboard has been installed properly!"
}

albingresscontroller() {
  logger "green" "ALB Ingress controller setup is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
  aws iam create-policy --policy-name ALBIngressControllerIAMPolicy --policy-document https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/iam-policy.json --output json >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/rbac-role.yaml >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  eksctl create iamserviceaccount --region region-code --name alb-ingress-controller --namespace kube-system --cluster prod --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/ALBIngressControllerIAMPolicy --override-existing-serviceaccounts --approve >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  template=`curl -sS kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/alb-ingress-controller.yaml | sed -e "s/# - --cluster-name=devCluster/- --cluster-name=$CLUSTER_NAME/g" -e "s/# - --aws-vpc-id=vpc-xxxxxx/- --aws-vpc-id=$VPC_ID/g" -e "s/# - --aws-region=us-west-1/- --aws-region=$AWS_REGION/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "ALB Ingress controller has been installed properly!"
}

prometheus() {
  logger "green" "Prometheus setup is starting..."
  # source: https://eksworkshop.com/monitoring/deploy-prometheus/ 
  ns=`kubectl get namespace prometheus --output json | jq --raw-output .metadata.name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $ns = prometheus ]]; 
      then logger "blue" "Namespace exists. Skipping..."; 
      else kubectl create namespace prometheus >> "${LOG_OUTPUT}" 2>&1
      logger "blue" "Namespace created...";
  fi
  chart=`helm list --namespace prometheus --filter 'prometheus' --output json | jq --raw-output .[0].name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $chart = "prometheus" ]]; 
      then logger "blue" "Prometheus is already installed. Skipping..."; 
      else if [[ $EXTERNALPROMETHEUS = "yes" ]]; 
                then helm install prometheus stable/prometheus \
                                      --namespace prometheus \
                                      --set alertmanager.persistentVolume.storageClass="gp2" \
                                      --set server.persistentVolume.storageClass="gp2" \
                                      --set server.service.type=LoadBalancer >> "${LOG_OUTPUT}" 2>&1 
                    errorcheck ${FUNCNAME}
                    logger "blue" "Prometheus is being exposed to the Internet......";
                else helm install stable/prometheus \
                                      --name prometheus \
                                      --namespace prometheus \
                                      --set alertmanager.persistentVolume.storageClass="gp2" \
                                      --set server.persistentVolume.storageClass="gp2" >> "${LOG_OUTPUT}" 2>&1 
                      errorcheck ${FUNCNAME}
                      logger "blue" "Prometheus is not being exposed to the Internet......";
           fi   
  fi
  errorcheck ${FUNCNAME}
  logger "green" "Prometheus has been installed properly!"
}

grafana() {
  logger "green" "Grafana setup is starting..."
  # source: https://eksworkshop.com/monitoring/deploy-grafana/ 
  ns=`kubectl get namespace grafana --output json | jq --raw-output .metadata.name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $ns = grafana ]]; 
      then logger "blue" "Namespace exists. Skipping..."; 
      else kubectl create namespace grafana >> "${LOG_OUTPUT}" 2>&1
      logger "blue" "Namespace created...";
  fi  
  chart=`helm list grafana --output json | jq --raw-output .[0].Name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $chart = "grafana" ]]; 
      then logger "blue" "Grafana is already installed. Skipping..."; 
      else helm install grafana stable/grafana \
            --namespace grafana \
            --set persistence.storageClassName="gp2" \
            --set adminPassword="EKS!sAWSome" \
            --set datasources."datasources\.yaml".apiVersion=1 \
            --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
            --set datasources."datasources\.yaml".datasources[0].type=prometheus \
            --set datasources."datasources\.yaml".datasources[0].url=http://prometheus-server.prometheus.svc.cluster.local \
            --set datasources."datasources\.yaml".datasources[0].access=proxy \
            --set datasources."datasources\.yaml".datasources[0].isDefault=true \
            --set service.type=LoadBalancer >> "${LOG_OUTPUT}" 2>&1 ;
  fi
  errorcheck ${FUNCNAME}
  logger "green" "Grafana has been installed properly!"
}

cloudwatchcontainerinsights() {
  logger "green" "CloudWatch Containers Insights setup is starting..."
  # source: https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/deploy-container-insights-EKS.html 
  aws iam attach-role-policy --role-name $NODE_INSTANCE_ROLE --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  ns=`kubectl get namespace amazon-cloudwatch --output json | jq --raw-output .metadata.name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $ns = amazon-cloudwatch ]]; 
      then logger "blue" "Namespace exists. Skipping..."
      else template=`curl -sS https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml` >> "${LOG_OUTPUT}" 2>&1 
           errorcheck ${FUNCNAME}
           echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
           errorcheck ${FUNCNAME}
           logger "blue" "Namespace created...";
  fi  
  template=`curl -sS https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-serviceaccount.yaml` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  template=`curl -sS https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-configmap.yaml | sed -e "s/{{cluster_name}}/$CLUSTER_NAME/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME} 
  template=`curl -sS https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME} 
  # ------
  clusterinfo=`kubectl get configmap cluster-info -n amazon-cloudwatch --output json --ignore-not-found | jq --raw-output .metadata.name` >> "${LOG_OUTPUT}" 2>&1
  if [[ $clusterinfo = "cluster-info" ]]; 
      then logger "blue" "The cluster-info configmap is already there. Skipping..."; 
      else kubectl create configmap cluster-info --from-literal=cluster.name=$CLUSTER_NAME --from-literal=logs.region=$REGION -n amazon-cloudwatch  >> "${LOG_OUTPUT}" 2>&1 ;
  fi
  # ------
  errorcheck ${FUNCNAME}
  template=`curl -sS https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluentd/fluentd.yaml` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME} 
  logger "green" "CloudWatch Containers Insights has been installed properly!"
}

clusterautoscaler() {
  logger "green" "Cluster Autoscaler deployment is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html
  # the iam policy ASG-Policy-For-Worker could be redundant if the cluster is installed with eksctl and the --asg-access flag 
  # aws iam put-role-policy --role-name $NODE_INSTANCE_ROLE --policy-name ASG-Policy-For-Worker --policy-document file://./configurations/k8s-asg-policy.json >> "${LOG_OUTPUT}" 2>&1 
  if [[ $CLUSTER_VERSION = 1.12 ]]; then CA_IMAGE_TAG=1.12.8; fi >> "${LOG_OUTPUT}" 2>&1
  if [[ $CLUSTER_VERSION = 1.13 ]]; then CA_IMAGE_TAG=1.13.9; fi >> "${LOG_OUTPUT}" 2>&1
  if [[ $CLUSTER_VERSION = 1.14 ]]; then CA_IMAGE_TAG=1.14.8; fi >> "${LOG_OUTPUT}" 2>&1
  if [[ $CLUSTER_VERSION = 1.15 ]]; then CA_IMAGE_TAG=1.15.6; fi >> "${LOG_OUTPUT}" 2>&1
  if [[ $CLUSTER_VERSION = 1.16 ]]; then CA_IMAGE_TAG=1.16.5; fi >> "${LOG_OUTPUT}" 2>&1
  template=`cat "./configurations/cluster_autoscaler.yaml" | sed -e "s/<YOUR CLUSTER NAME>/$CLUSTER_NAME/g" -e "s/<CA IMAGE TAG>/$CA_IMAGE_TAG/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  kubectl -n kube-system annotate deployment.apps/cluster-autoscaler cluster-autoscaler.kubernetes.io/safe-to-evict="false" >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "Cluster Autoscaler has been installed properly!"
}

appmesh() {
  logger "green" "Appmesh components setup is starting..."
  # https://docs.aws.amazon.com/app-mesh/latest/userguide/mesh-k8s-integration.html 
  kubectl apply -k https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  ns=`kubectl get namespace appmesh-system --output json | jq --raw-output .metadata.name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $ns = appmesh-system ]]; 
      then logger "blue" "Namespace exists. Skipping..."
      else kubectl create ns appmesh-system >> "${LOG_OUTPUT}" 2>&1
           errorcheck ${FUNCNAME}
           logger "blue" "Namespace created...";
  fi 
  eksctl create iamserviceaccount --cluster $CLUSTER_NAME --namespace appmesh-system --name appmesh-controller --attach-policy-arn  arn:aws:iam::aws:policy/AWSCloudMapFullAccess,arn:aws:iam::aws:policy/AWSAppMeshFullAccess --override-existing-serviceaccounts --approve >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  helm upgrade -i appmesh-controller eks/appmesh-controller --namespace appmesh-system --set region=$AWS_REGION --set serviceAccount.create=false --set serviceAccount.name=appmesh-controller >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  APP_MESH_CONTROLLER_VERSION={kubectl get deployment -n appmesh-system appmesh-controller -o json  | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':'}  >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "The AppMesh controller version is: " $APP_MESH_CONTROLLER_VERSION >> "${LOG_OUTPUT}" 2>&1 
  helm upgrade -i appmesh-inject eks/appmesh-inject --namespace appmesh-system --set mesh.name=$MESH_NAME --set mesh.create=true >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "The mesh name is: " $MESH_NAME >> "${LOG_OUTPUT}" 2>&1
  # for now only the default namespace is enabled to inject the sidecar automatically
  kubectl label namespace default appmesh.k8s.aws/sidecarInjectorWebhook=enabled --overwrite >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "Appmesh components have been installed properly"
}

demoapp() {
  logger "green" "Demo application setup is starting..."
  if [ ! -d yelb ]; then git clone https://github.com/mreferre/yelb >> "${LOG_OUTPUT}" 2>&1
  fi 
  errorcheck ${FUNCNAME}
  kubectl apply -f ./yelb/deployments/platformdeployment/Kubernetes/yaml/yelb-k8s-ingress-alb.yaml --namespace=default >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  sleep 120 
  logger "green" "Demo application has been installed properly!"
}

congratulations() {
  logger "yellow" "Almost there..."
  # instead of the sleep below a selective poll should be created that waits till the endpoints are available.  
  sleep 40
  GRAFANAELB=`kubectl get service grafana -n $NAMESPACE --output json | jq --raw-output .status.loadBalancer.ingress[0].hostname` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}  
  PROMETHEUSELB=`kubectl get service prometheus-server -n $NAMESPACE --output json | jq --raw-output .status.loadBalancer.ingress[0].hostname` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  DASHBOARDELB=`kubectl get service kubernetes-dashboard-external -n $NAMESPACE --output json | jq --raw-output .status.loadBalancer.ingress[0].hostname` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  if [[ $DEMOAPP = "yes" ]]; then DEMOAPPALBURL=`kubectl get ingress yelb-ui -n $NAMESPACE --output json | jq --raw-output .status.loadBalancer.ingress[0].hostname`; fi >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "Congratulations! You made it!"
  logger "green" "Your EKStended kubernetes environment is ready to be used"
  logger "green" "------"
  logger "yellow" "Grafana UI           : http://"$GRAFANAELB 
  logger "yellow" "Prometheus UI        : http://"$PROMETHEUSELB
  logger "yellow" "Kubernetes Dashboard : https://"$DASHBOARDELB 
  logger "yellow" "Demo application     : http://"$DEMOAPPALBURL
  logger "green" "------"
  logger "green" "Note that it may take several minutes for these end-points to be fully operational"
  logger "green" "If you see a <null> or no value you specifically opted out for that particular feature or the LB isn't ready yet (check with kubectl)"
  logger "green" "Enjoy!"
}

main() {
  welcome
  admin_sa #ns = kube-system
  iam_oidc_provider #ns = not applicable
  helmrepos #ns = not applicable
  calico #ns = kube-system
  metrics-server #ns = metrics-server
  csiebs #ns = kube-system
  csiefs #ns = kube-system
  csifsx #ns = kube-system
  dashboard #ns = kube-system
  albingresscontroller #ns = kube-system
  prometheus #ns = prometheus
  grafana #ns = grafana
  cloudwatchcontainerinsights #ns = amazon-cloudwatch
  clusterautoscaler #ns = clusterautoscaler  
  appmesh #ns = appmesh-system + appmesh-inject 
  demoapp #ns = default 
  congratulations
}

main 
