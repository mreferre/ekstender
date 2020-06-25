#!/bin/bash

# Massimo Re Ferre' massimo@it20.info

###########################################################
###########                README               ###########
###########################################################
# This script adds a set of tooling on top of a vanilla EKS cluster
# This script is made available for demo and/or test purposes only
# DO NOT USE THIS SCRIPT WITH A PRODUCTION EKS CLUSTER 
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
: ${EXTERNALPROMETHEUS:=no}  
: ${DEMOAPP:=yes}  
: ${CALICO:=no}  
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
# ------------------
figlet -k EKStender
# ------------------
echo "Gathering data about the cluster to EKStend..."
echo 
# scripts read $1 as clustername. If $1 is not used it exits
if [ -z "$1" ]; then echo "Please specify the cluster name you want to EKStend!"; exit; else export CLUSTER_NAME=$1; fi
if [ -z "$REGION" ]; then echo "Please configure the region in your CLI or export the variable REGION" & exit; fi
export ACCOUNT_ID=$(aws sts get-caller-identity --output json | jq -r '.Account') # the AWS Account ID 
export STACK_NAME=$(eksctl get nodegroup --cluster $CLUSTER_NAME --region $REGION  -o json | jq -r '.[].StackName')
export NODE_INSTANCE_ROLE=$(aws cloudformation describe-stack-resources --region $REGION --stack-name $STACK_NAME | jq -r '.StackResources[] | select(.LogicalResourceId=="NodeInstanceRole") | .PhysicalResourceId' )  # the IAM role assigned to the worker nodes
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

banner()
{
  echo "+------------------------------------------+"
  printf "| %-40s |\n" "`date`"
  echo "|                                          |"
  printf "|`tput bold` %-40s `tput sgr0`|\n" "$@"
  echo "+------------------------------------------+"
}

errorcheck() {
   if [ $? != 0 ]; then
          logger "red" "Unrecoverable generic error found in function: [$1]. Check the log. Exiting."
      exit 1
   fi
}

welcome() {
  logger "red" "*************************************************"
  logger "red" "***  Do not run this on a production cluster  ***"
  logger "red" "*** This is solely for demo/learning purposes ***"
  logger "red" "*************************************************"
  logger "green" "These are the environment settings that are going to be used:"
  logger "yellow" "Account ID            : $ACCOUNT_ID"
  logger "yellow" "Cluster name          : $CLUSTER_NAME"
  logger "yellow" "Cluster version       : $CLUSTER_VERSION"
  logger "yellow" "AWS region            : $REGION"
  logger "yellow" "Node instance role    : $NODE_INSTANCE_ROLE"
  logger "yellow" "External dashboard    : $EXTERNALDASHBOARD"
  logger "yellow" "External Prometheus   : $EXTERNALPROMETHEUS"
  logger "yellow" "Mesh name             : $MESH_NAME"
  logger "yellow" "Demo application      : $DEMOAPP"
  logger "yellow" "Calico                : $CALICO"
  logger "green" "--------------------------------------------------------------"
  logger "green" "You are about to EKStend your EKS cluster with the following add-ons"
  logger "blue" "* A generic admin Service Account (eks-admin))"
  logger "blue" "* Calico (network policy engine)"
  logger "blue" "* Metrics server"
  logger "blue" "* CSI EBS drivers"
  logger "blue" "* CSI EFS drivers"
  logger "blue" "* CSI FSx drivers"
  logger "blue" "* ALB ingress controller"
  logger "blue" "* Cluster autoscaler"
  logger "blue" "* Vertical pod autoscaler"
  logger "blue" "* Kubernetes dashboard"
  logger "blue" "* Prometheus"
  logger "blue" "* Grafana"
  logger "blue" "* CloudWatch Container Insights"
  logger "blue" "* AppMesh controller and sidecar injector"
  logger "blue" "* Demo application (Yelb)"
  logger "yellow" "Press [Enter] to continue or CTRL-C to abort..."
  read -p " "
}

admin_sa() {
  banner "Administrator Service account"
  logger "green" "Creation of the generic eks-admin service account is starting..."
  template=`cat "./configurations/eks-admin-service-account.yaml"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "Creation of the generic eks-admin service account has completed..."
}

iam_oidc_provider() {
  banner "OIDC provider"
  logger "green" "Associating IAM OIDC provider..."
  eksctl utils associate-iam-oidc-provider --region=$AWS_REGION --cluster $CLUSTER_NAME --approve >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "Association of the IAM OIDC provider has completed..."
}

helmrepos() {
  banner "Helm repos"
  logger "green" "Importing required Helm repos..."
  helm repo add stable https://kubernetes-charts.storage.googleapis.com/ >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  helm repo add eks https://aws.github.io/eks-charts >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  helm repo update >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "Importing required Helm repos has completed..."
}

calico() {
  banner "Calico"
  logger "green" "Calico setup is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/calico.html 
  template=`curl -sS https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/release-1.6/config/v1.6/calico.yaml` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  logger "green" "Waiting for Calico pods to come up..."
  logger "green" "Waiting for the calico daemonset to come up on all nodes..."
  calicodaemondesired=1 2>&1 
  calicodaemonready=0 2>&1 
  # This loops checks if the DESIRED count is equal to the ACTIVE count
  while [[ $calicodaemondesired != $calicodaemonready ]]; do 
      calicodaemon=`kubectl get ds calico-node -n kube-system | tail -n +2` >> "${LOG_OUTPUT}" 2>&1 
      calicodaemondesired=`echo $calicodaemon | awk '{print $2}'` >> "${LOG_OUTPUT}" 2>&1 
      calicodaemonready=`echo $calicodaemon | awk '{print $4}'` >> "${LOG_OUTPUT}" 2>&1 
      echo "waiting for the calico daemon to start on all nodes ($calicodaemondesire/$calicodaemonready)" >> "${LOG_OUTPUT}" 2>&1 
      sleep 1; 
  done 
  logger "green" "Calico has been installed properly!"
}

metrics-server() {
  banner "Metrics server"
  logger "green" "Metrics server deployment is starting..."
  # source: https://eksworkshop.com/scaling/deploy_hpa/ & https://docs.aws.amazon.com/eks/latest/userguide/metrics-server.html 
  ns=`kubectl get namespace metrics-server --output json --ignore-not-found | jq --raw-output .metadata.name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $ns = metrics-server ]]; 
      then logger "blue" "metrics-server namespace exists. Skipping..."; 
      else kubectl create namespace metrics-server >> "${LOG_OUTPUT}" 2>&1
      logger "blue" "metrics-server namespace created...";
  fi  
  CHART=`helm list --namespace metrics-server --filter 'metrics-server' --output json | jq --raw-output .[0].name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $CHART = "metrics-server" ]]; 
      then logger "blue" "Metrics server is already installed. Skipping..."; 
      else helm install metrics-server stable/metrics-server --version 2.11.1 --namespace metrics-server  >> "${LOG_OUTPUT}" 2>&1 ;
  fi
  errorcheck ${FUNCNAME}
  logger "green" "Metric server has been installed properly!"
}

csiebs() {
  banner "CSI EBS Driver"
  logger "green" "EBS CSI support deployment is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html
  curl -o configurations/ebs-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-ebs-csi-driver/v0.4.0/docs/example-iam-policy.json >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  AMAZON_EBS_CSI_DRIVER_POLICY_ARN=$(aws iam list-policies --region $REGION | jq -r '.Policies[] | select(.PolicyName=="Amazon_EBS_CSI_Driver") | .Arn')
  if [[ $AMAZON_EBS_CSI_DRIVER_POLICY_ARN = "arn:aws:iam::$ACCOUNT_ID:policy/Amazon_EBS_CSI_Driver" ]]; 
      then logger "blue" "Amazon_EBS_CSI_Driver exists already. Skipping..."; 
      else aws iam create-policy --policy-name Amazon_EBS_CSI_Driver --policy-document file://./configurations/ebs-iam-policy.json >> "${LOG_OUTPUT}" 2>&1
           errorcheck ${FUNCNAME};
  fi 
  aws iam attach-role-policy --role-name $NODE_INSTANCE_ROLE --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/Amazon_EBS_CSI_Driver >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master" >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "EBS CSI support has been installed properly!"
}

csiefs() {
  banner "CSI EFS Driver"
  logger "green" "EFS CSI support deployment is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html
  kubectl apply -k "github.com/kubernetes-sigs/aws-efs-csi-driver/deploy/kubernetes/overlays/stable/?ref=master" >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "EFS CSI support has been installed properly!"
}

csifsx() {
  # https://docs.aws.amazon.com/eks/latest/userguide/fsx-csi.html
  banner "CSI FSx Driver"
  logger "green" "FSx CSI support deployment is starting..."
  AMAZON_FSX_LUSTRE_CSI_DRIVER_POLICY_ARN=$(aws iam list-policies --region $REGION | jq -r '.Policies[] | select(.PolicyName=="Amazon_FSx_Lustre_CSI_Driver") | .Arn')
  if [[ $AMAZON_FSX_LUSTRE_CSI_DRIVER_POLICY_ARN = "arn:aws:iam::$ACCOUNT_ID:policy/Amazon_FSx_Lustre_CSI_Driver" ]]; 
      then logger "blue" "The Amazon_FSx_Lustre_CSI_Driver IAM policy exists already. Skipping..."; 
      # A configuration policy file is required because one is not available on GH (the policy file is only available in the docs)
      # Also AWS CLI v2 doesn't support pointint to an URL to grab a file (to check)
      else aws iam create-policy --policy-name Amazon_FSx_Lustre_CSI_Driver --policy-document file://./configurations/fsx-csi-driver.json >> "${LOG_OUTPUT}" 2>&1
           errorcheck ${FUNCNAME};
  fi 
  eksctl create iamserviceaccount --region $REGION --name fsx-csi-controller-sa --namespace kube-system --cluster $CLUSTER_NAME --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/Amazon_FSx_Lustre_CSI_Driver --approve >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME} 
  kubectl apply -k "github.com/kubernetes-sigs/aws-fsx-csi-driver/deploy/kubernetes/overlays/stable/?ref=master" >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME} 
  logger "green" "FSx CSI support has been installed properly!"
}

albingresscontroller() {
  banner "ALB ingress controller"
  logger "green" "ALB Ingress controller setup is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/alb-ingress.html
  ALB_INGRESS_CONTROLLER_POLICY_ARN=$(aws iam list-policies --region $REGION | jq -r '.Policies[] | select(.PolicyName=="ALBIngressControllerIAMPolicy") | .Arn')
  if [[ $ALB_INGRESS_CONTROLLER_POLICY_ARN = "arn:aws:iam::$ACCOUNT_ID:policy/ALBIngressControllerIAMPolicy" ]]; 
      then logger "blue" "The ALBIngressControllerIAMPolicy IAM policy exists already. Skipping..."; 
      # AWS CLI v2 doesn't support pointint to an URL to grab a file (to check)
      else curl -o configurations/alb-ingress-iam-policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/iam-policy.json >> "${LOG_OUTPUT}" 2>&1
           errorcheck ${FUNCNAME}
           aws iam create-policy --policy-name ALBIngressControllerIAMPolicy --policy-document file://./configurations/alb-ingress-iam-policy.json --output json >> "${LOG_OUTPUT}" 2>&1 
           errorcheck ${FUNCNAME};
  fi 
  eksctl create iamserviceaccount --region $REGION --name alb-ingress-controller --namespace kube-system --cluster $CLUSTER_NAME --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/ALBIngressControllerIAMPolicy --approve >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/rbac-role.yaml >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  template=`curl -sS https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.4/docs/examples/alb-ingress-controller.yaml | sed -e "s/# - --cluster-name=devCluster/- --cluster-name=$CLUSTER_NAME/g" -e "s/# - --aws-vpc-id=vpc-xxxxxx/- --aws-vpc-id=$VPC_ID/g" -e "s/# - --aws-region=us-west-1/- --aws-region=$AWS_REGION/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "ALB Ingress controller has been installed properly!"
}

clusterautoscaler() {
  banner "Kubernetes cluster autoscaler (CA)"
  logger "green" "Cluster autoscaler (CA) deployment is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html
  # the iam policy ASG-Policy-For-Worker could be redundant if the cluster is installed with eksctl and the --asg-access flag 
  # aws iam put-role-policy --role-name $NODE_INSTANCE_ROLE --policy-name ASG-Policy-For-Worker --policy-document file://./configurations/k8s-asg-policy.json >> "${LOG_OUTPUT}" 2>&1 
  if [[ $CLUSTER_VERSION = 1.12 ]]; then CA_IMAGE="k8s.gcr.io/cluster-autoscaler:v1.12.8"; fi >> "${LOG_OUTPUT}" 2>&1
  if [[ $CLUSTER_VERSION = 1.13 ]]; then CA_IMAGE="k8s.gcr.io/cluster-autoscaler:v1.13.9"; fi >> "${LOG_OUTPUT}" 2>&1
  if [[ $CLUSTER_VERSION = 1.14 ]]; then CA_IMAGE="k8s.gcr.io/cluster-autoscaler:v1.14.8"; fi >> "${LOG_OUTPUT}" 2>&1
  if [[ $CLUSTER_VERSION = 1.15 ]]; then CA_IMAGE="us.gcr.io/k8s-artifacts-prod/autoscaling/cluster-autoscaler:v1.15.6"; fi >> "${LOG_OUTPUT}" 2>&1
  if [[ $CLUSTER_VERSION = 1.16 ]]; then CA_IMAGE="us.gcr.io/k8s-artifacts-prod/autoscaling/cluster-autoscaler:v1.16.5"; fi >> "${LOG_OUTPUT}" 2>&1
  template=`cat "./configurations/cluster_autoscaler.yaml" | sed -e "s/<YOUR CLUSTER NAME>/$CLUSTER_NAME/g" -e "s*<CA IMAGE>*$CA_IMAGE*g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  kubectl -n kube-system annotate deployment.apps/cluster-autoscaler cluster-autoscaler.kubernetes.io/safe-to-evict="false" --overwrite >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "Cluster Autoscaler has been installed properly!"
}

verticalpodautoscaler() {
  banner "Vertical pod autoscaler (VPA)"
  logger "green" "Vertical pod autoscaler (VPA) deployment is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/vertical-pod-autoscaler.html
  VPA_ADMISSION_CONTROLLER=$(kubectl get deployment vpa-admission-controller -n kube-system --ignore-not-found | tail -n +2 | awk '{print $1}')
  if [[ $VPA_ADMISSION_CONTROLLER != "vpa-admission-controller" ]];
    then 
      if [[ ! -d "autoscaler" ]]
        then git clone https://github.com/kubernetes/autoscaler.git >> "${LOG_OUTPUT}" 2>&1
         errorcheck ${FUNCNAME}
        else logger "blue" "The autoscaler repo already exists. Skipping the cloning..."
      fi   
      errorcheck ${FUNCNAME}
      ./autoscaler/vertical-pod-autoscaler/hack/vpa-up.sh >> "${LOG_OUTPUT}" 2>&1
      errorcheck ${FUNCNAME};
    else logger "blue" "The autoscaler pods seem to be deployed already. Skipping the installation..."
  fi
  logger "green" "Vertical pod autoscaler (VPA) installed properly!"
}

dashboard() {
  banner "Kubernetes dashboard"
  logger "green" "The Kubernetes dashboard setup is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/dashboard-tutorial.html
  DASHBOARD=$(kubectl get deployment kubernetes-dashboard -n kubernetes-dashboard --ignore-not-found | tail -n +2 | awk '{print $1}')  >> "${LOG_OUTPUT}" 2>&1
  if [[ $DASHBOARD = "kubernetes-dashboard" ]] 
      then logger "blue" "The Kubernetes dashboard is already installed. Skipping..." 
      else kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.0.0-beta8/aio/deploy/recommended.yaml >> "${LOG_OUTPUT}" 2>&1 
           errorcheck ${FUNCNAME}
           if [[ $EXTERNALDASHBOARD = "yes" ]] 
               then kubectl expose deployment kubernetes-dashboard --type=LoadBalancer --name=kubernetes-dashboard-external -n kubernetes-dashboard >> "${LOG_OUTPUT}" 2>&1 
                    errorcheck ${FUNCNAME}
                    logger "blue" "Warning: I am exposing the Kubernetes dashboard to the Internet..."
               else logger "blue" "The Kubernetes dashboard is not being exposed to the Internet......"
          fi
  fi
  # If you opted not expose the dashboard via the CLB, start the proxy like this: kubectl proxy 
  # and connect to: http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/#!/login
  # (If you are using Cloud 9 do this: kubectl proxy --port=8080 --accept-hosts="^*$"  - and connect to: http://localhost:8080/api/v1/......) 
  # If you opted to expose the dashboard via the CLB, connect to https://<elb-fqdn>:8443
  #HOW TO GET A TOKEN
  # grab the token: kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')
  logger "green" "The Kubernetes dashboard has been installed properly!"
}

prometheus() {
  banner "Prometheus"
  logger "green" "Prometheus setup is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/prometheus.html 
  ns=`kubectl get namespace prometheus --output json --ignore-not-found | jq --raw-output .metadata.name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $ns = prometheus ]]; 
      then logger "blue" "Namespace exists. Skipping..."; 
      else kubectl create namespace prometheus >> "${LOG_OUTPUT}" 2>&1
      logger "blue" "Namespace created...";
  fi
  CHART=`helm list --namespace prometheus --filter 'prometheus' --output json | jq --raw-output .[0].name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $CHART = "prometheus" ]]; 
      then logger "blue" "Prometheus is already installed. Skipping..."; 
      else if [[ $EXTERNALPROMETHEUS = "yes" ]]; 
                then helm install prometheus stable/prometheus \
                                      --namespace prometheus \
                                      --set alertmanager.persistentVolume.storageClass="gp2" \
                                      --set server.service.type=LoadBalancer >> "${LOG_OUTPUT}" 2>&1 
                    errorcheck ${FUNCNAME}
                    logger "blue" "Prometheus is being exposed to the Internet......";
                else helm install prometheus stable/prometheus \
                                      --namespace prometheus \
                                      --set alertmanager.persistentVolume.storageClass="gp2" >> "${LOG_OUTPUT}" 2>&1
                      errorcheck ${FUNCNAME}
                      logger "blue" "Prometheus is not being exposed to the Internet......";
           fi   
  fi
  errorcheck ${FUNCNAME}
  logger "green" "Prometheus has been installed properly!"
}

grafana() {
  banner "Grafana"
  logger "green" "Grafana setup is starting..."
  # source: https://eksworkshop.com/intermediate/240_monitoring/deploy-grafana/
  ns=`kubectl get namespace grafana --output json --ignore-not-found | jq --raw-output .metadata.name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $ns = grafana ]]; 
      then logger "blue" "Namespace exists. Skipping..."; 
      else kubectl create namespace grafana >> "${LOG_OUTPUT}" 2>&1
      logger "blue" "Namespace created...";
  fi  
  CHART=`helm list --namespace grafana --filter 'grafana' --output json | jq --raw-output .[0].name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $CHART = "grafana" ]]; 
      then logger "blue" "Grafana is already installed. Skipping..."; 
      else helm install grafana stable/grafana \
            --namespace grafana \
            --set persistence.storageClassName="gp2" \
            --set persistence.enabled=true \
            --set adminPassword="EKS!sAWSome" \
            --set datasources."datasources\.yaml".apiVersion=1 \
            --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
            --set datasources."datasources\.yaml".datasources[0].type=prometheus \
            --set datasources."datasources\.yaml".datasources[0].url=http://prometheus-server.prometheus.svc.cluster.local \
            --set datasources."datasources\.yaml".datasources[0].access=proxy \
            --set datasources."datasources\.yaml".datasources[0].isDefault=true \
            --set service.type=LoadBalancer >> "${LOG_OUTPUT}" 2>&1 ;
  fi
  logger "green" "Grafana has been installed properly!"
}

cloudwatchcontainerinsights() {
  banner "CloudWatch Container Insights"
  logger "green" "CloudWatch Containers Insights setup is starting..."
  # CW IAM role for EC2 instances 
  aws iam attach-role-policy --role-name $NODE_INSTANCE_ROLE --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  # CW namespace 
  template=`curl -sS https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml`
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}  
  # CW service account 
  template=`curl -sS https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-serviceaccount.yaml` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}  
  # CW agent configmap 
  template=`curl -sS https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-configmap.yaml | sed -e "s/{{cluster_name}}/$CLUSTER_NAME/g"` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME} 
  # CW agent daemonset 
  template=`curl -sS https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cwagent/cwagent-daemonset.yaml` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME} 
  # CW Fluentd 
  # ------
  clusterinfo=`kubectl get configmap cluster-info -n amazon-cloudwatch --output json --ignore-not-found | jq --raw-output .metadata.name` >> "${LOG_OUTPUT}" 2>&1
  if [[ $clusterinfo = "cluster-info" ]]; 
      then logger "blue" "The cluster-info configmap is already there. Skipping..."; 
      else kubectl create configmap cluster-info --from-literal=cluster.name=$CLUSTER_NAME --from-literal=logs.region=$REGION -n amazon-cloudwatch  >> "${LOG_OUTPUT}" 2>&1
           errorcheck ${FUNCNAME}
  fi
  # ------
  template=`curl -sS https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/fluentd/fluentd.yaml` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME} 
  # WARNING - the following section setup the beta for the new Prometheus metrics collection feature - it's a super set of all constructs above 
  # CW Prometheus metrics collection
  template=`curl -sS https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/prometheus-beta/k8s-deployment-manifest-templates/deployment-mode/service/cwagent-prometheus/prometheus-eks.yaml` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME} 
  logger "green" "CloudWatch Containers Insights has been installed properly!"
}


appmesh() {
  banner "App Mesh"
  logger "green" "Appmesh components setup is starting..."
  # https://docs.aws.amazon.com/app-mesh/latest/userguide/mesh-k8s-integration.html 
  kubectl apply -k https://github.com/aws/eks-charts/stable/appmesh-controller/crds?ref=master >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  ns=`kubectl get namespace appmesh-system --output json --ignore-not-found | jq --raw-output .metadata.name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $ns = appmesh-system ]]; 
      then logger "blue" "Namespace 'appmesh-system' exists. Skipping..."
      else kubectl create ns appmesh-system >> "${LOG_OUTPUT}" 2>&1
           errorcheck ${FUNCNAME}
           logger "blue" "Namespace 'appmesh-system' created...";
  fi 
  eksctl create iamserviceaccount --cluster $CLUSTER_NAME --namespace appmesh-system --name appmesh-controller --attach-policy-arn  arn:aws:iam::aws:policy/AWSCloudMapFullAccess,arn:aws:iam::aws:policy/AWSAppMeshFullAccess --override-existing-serviceaccounts --approve >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  helm upgrade -i appmesh-controller eks/appmesh-controller --namespace appmesh-system --set region=$AWS_REGION --set serviceAccount.create=false --set serviceAccount.name=appmesh-controller >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  APP_MESH_CONTROLLER_VERSION=$(kubectl get deployment -n appmesh-system appmesh-controller -o json  | jq -r ".spec.template.spec.containers[].image" | cut -f2 -d ':')  >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "The AppMesh controller version is: " $APP_MESH_CONTROLLER_VERSION >> "${LOG_OUTPUT}" 2>&1 
  echo "The mesh name is: " $MESH_NAME >> "${LOG_OUTPUT}" 2>&1
  # A new namespace called `appmesh-app` is created and tagged to autoinject the envoy proxy
  ns=`kubectl get namespace appmesh-app --output json --ignore-not-found | jq --raw-output .metadata.name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $ns = appmesh-app ]]; 
      then logger "blue" "Namespace 'appmesh-app' exists. Skipping..."
      else kubectl create ns appmesh-app >> "${LOG_OUTPUT}" 2>&1
           errorcheck ${FUNCNAME}
           logger "blue" "Namespace 'appmesh-app' created...";
  fi 
  kubectl label namespace appmesh-app appmesh.k8s.aws/sidecarInjectorWebhook=enabled --overwrite >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "Appmesh components have been installed properly"
}

demoapp() {
  banner "Yelb demo application"
  logger "green" "Demo application setup is starting..."
  YELB_UI=$(kubectl get deployment yelb-ui -n default --ignore-not-found | tail -n +2 | awk '{print $1}')
  if [[ $YELB_UI != "yelb-ui" ]];
    then kubectl apply -n default -f https://raw.githubusercontent.com/mreferre/yelb/master/deployments/platformdeployment/Kubernetes/yaml/yelb-k8s-ingress-alb-ip.yaml >> "${LOG_OUTPUT}" 2>&1
         errorcheck ${FUNCNAME};
         sleep 60 
    else logger "blue" "The demo app is already installed. Skipping the setup..."
  fi
  logger "green" "Demo application has been installed properly!"
}

congratulations() {
  banner "Congratulations!"
  logger "green" "Your cluster has been EKStended! Almost there..."
  # instead of the sleep below a selective poll should be created that waits till the endpoints are available.  
  sleep 30
  GRAFANAELB=`kubectl get service grafana -n grafana --output json | jq --raw-output .status.loadBalancer.ingress[0].hostname` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}  
  PROMETHEUSELB=`kubectl get service prometheus-server -n prometheus --output json | jq --raw-output .status.loadBalancer.ingress[0].hostname` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  DASHBOARDELB=`kubectl get service kubernetes-dashboard-external -n kubernetes-dashboard --output json | jq --raw-output .status.loadBalancer.ingress[0].hostname` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  DEMOAPPALBURL=`kubectl get ingress yelb-ui -n default --output json | jq --raw-output .status.loadBalancer.ingress[0].hostname` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "Congratulations! You made it!"
  logger "green" "Your EKStended kubernetes environment is ready to be used"
  logger "green" "------"
  if [ ! "$GRAFANAELB" = null ]
    then logger "yellow" "Grafana UI           : http://"$GRAFANAELB:80
  fi 
  if [ ! "$PROMETHEUSELB" = null ]
    then logger "yellow" "Prometheus UI        : http://"$PROMETHEUSELB
  fi
  if [ ! "$DASHBOARDELB" = null ] 
    then logger "yellow" "Kubernetes Dashboard : https://"$DASHBOARDELB:8443 
  fi
  if [ ! "$DEMOAPPALBURL" = null ] 
    then logger "yellow" "Demo application     : http://"$DEMOAPPALBURL:80 
  fi
  logger "green" "------"
  logger "green" "Note that it may take several minutes for these end-points to be fully operational"
  logger "green" "Enjoy!"
}

main() {
  welcome
  admin_sa #ns = kube-system
  iam_oidc_provider #ns = not applicable
  helmrepos #ns = not applicable
  if [[ $CALICO = "yes" ]]; then calico; fi; #ns = kube-system
  metrics-server #ns = metrics-server
  csiebs #ns = kube-system
  csiefs #ns = kube-system
  csifsx #ns = kube-system
  albingresscontroller #ns = kube-system
  clusterautoscaler #ns = clusterautoscaler  
  verticalpodautoscaler #ns = kube-system  
  dashboard #ns = kube-system
  prometheus #ns = prometheus
  grafana #ns = grafana
  cloudwatchcontainerinsights #ns = amazon-cloudwatch
  appmesh #ns = appmesh-system + appmesh-app 
  if [[ $DEMOAPP = "yes" ]]; then demoapp; fi; #ns = default 
  congratulations
}

main 
