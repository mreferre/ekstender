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
: ${MESH_REGION:=${REGION}}
: ${MINNODES:=2}  # the min number of nodes in the ASG
: ${MAXNODES:=6}  # the max number of nodes in the ASG
: ${EXTERNALDASHBOARD:=yes}  
: ${EXTERNALPROMETHEUS:=yes}  
: ${DEMOAPP:=yes}  
: ${KUBEFLOW:=no}
: ${NAMESPACE:="kube-system"}
: ${MESH_NAME:="ekstender-mesh"}
export MESH_NAME
export MESH_REGION
###########################################################
###########           END OF USER INPUTS        ###########
###########################################################

###########################################################
###########    EXTRACTING REQUIRED PARAMETERS   ###########
###########################################################
# scripts read $1 as clustername. If $1 is not used it defaults to eks1
if [ -z "$1" ]; then "Please specify the cluster you want to EKStend!"; exit; else export CLUSTERNAME=$1; fi
export STACK_NAME=$(eksctl get nodegroup --cluster $CLUSTERNAME --region $REGION  -o json | jq -r '.[].StackName')
: ${NODE_INSTANCE_ROLE:=$(aws cloudformation describe-stack-resources --region $REGION --stack-name $STACK_NAME | jq -r '.StackResources[] | select(.LogicalResourceId=="NodeInstanceRole") | .PhysicalResourceId' )}  # the IAM role assigned to the worker nodes
: ${AUTOSCALINGGROUPNAME:=$(aws cloudformation describe-stack-resources --region $REGION --stack-name $STACK_NAME | jq -r '.StackResources[] | select(.LogicalResourceId=="NodeGroup") | .PhysicalResourceId')}  # the name of the ASG

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
  logger "red" "*************************************************"
  logger "red" "***  Do not run this on a production cluster  ***"
  logger "red" "*** This is solely for demo/learning purposes ***"
  logger "red" "*************************************************"
  logger "green" "You are about to EKStend your EKS cluster"
  logger "green" "These are the environment settings that are going to be used:"
  logger "yellow" "Cluster Name          : $CLUSTERNAME"
  logger "yellow" "AWS Region            : $REGION"
  logger "yellow" "Node Instance Role    : $NODE_INSTANCE_ROLE"
  logger "yellow" "Kubernetes Namespace  : $NAMESPACE"
  logger "yellow" "ASG Name              : $AUTOSCALINGGROUPNAME"
  logger "yellow" "Min Number of Nodes   : $MINNODES"
  logger "yellow" "Max Number of Nodes   : $MAXNODES"
  logger "yellow" "External Dashboard    : $EXTERNALDASHBOARD"
  logger "yellow" "External Prometheus   : $EXTERNALPROMETHEUS"
  logger "yellow" "Mesh Name             : $MESH_NAME"
  logger "yellow" "Demo application      : $DEMOAPP"
  logger "yellow" "Kubeflow              : $KUBEFLOW"
  logger "green" "Press [Enter] to continue or CTRL-C to abort..."
  read -p " "
}

preparenamespace() {
  ns=`kubectl get namespace $NAMESPACE --output json | jq --raw-output .metadata.name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $ns = $NAMESPACE ]]; 
      then logger "blue" "Namespace exists. Skipping..."; 
      else kubectl create namespace $NAMESPACE >> "${LOG_OUTPUT}" 2>&1
      logger "blue" "Namespace created...";
  fi
}

admin_sa() {
  logger "green" "Creation of the generic eks-admin service account is starting..."
  template=`cat "./configurations/eks-admin-service-account.yaml" | sed -e "s/NAMESPACE/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "Creation of the generic eks-admin service account has completed..."
}

calico() {
  logger "green" "Calico setup is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/calico.html 
  template=`curl -sS https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/v1.4/calico.yaml | sed -e "s/kube-system/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  logger "green" "Waiting for Calico pods to come up..."
  #this would need a proper check instead of a sleep 
  sleep 10
  logger "green" "Calico has been installed properly!"
}

tiller() {
  logger "green" "Helm setup is starting..."
  curl -o get_helm.sh https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get >> "${LOG_OUTPUT}" 2>&1 
  chmod +x get_helm.sh >> "${LOG_OUTPUT}" 2>&1 
  ./get_helm.sh >> "${LOG_OUTPUT}" 2>&1 
  template=`cat "./configurations/tiller-service-account.yaml" | sed "s/NAMESPACE/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  /usr/local/bin/helm init --service-account tiller --tiller-namespace $NAMESPACE >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  # we apparently need to sync the helm client and server (reference: https://github.com/helm/charts/issues/5239)
  # wonder what the ramifications of a complex production setup may be
  /usr/local/bin/helm init --upgrade >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "Waiting for the tiller pod to come up..."
  tillerpodline=`kubectl get pod -A | grep tiller` >> "${LOG_OUTPUT}" 2>&1 
  tillerpod=`echo $tillerpodline | awk '{print $2}'` >> "${LOG_OUTPUT}" 2>&1 
  while [[ $(kubectl get pods -n $NAMESPACE $tillerpod -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for $tillerpod pod" && sleep 1; done >> "${LOG_OUTPUT}" 2>&1 
  logger "green" "Tiller has been installed properly!"
}

metricserver() {
  logger "green" "Metric server deployment is starting..."
  echo "Updating Helm repo" >> "${LOG_OUTPUT}" 2>&1
  /usr/local/bin/helm repo update >> "${LOG_OUTPUT}" 2>&1 
  chart=`/usr/local/bin/helm list metric-server --output json | jq --raw-output .Releases[0].Name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $chart = "metric-server" ]]; 
      then logger "blue" "Metric server is already installed. Skipping..."; 
      else /usr/local/bin/helm install stable/metrics-server --name metric-server --version 2.0.4 --namespace $NAMESPACE >> "${LOG_OUTPUT}" 2>&1 ;
  fi
  errorcheck ${FUNCNAME}
  logger "green" "Metric server has been installed properly!"
}

dashboard() {
  logger "green" "Dashboard setup is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/dashboard-tutorial.html
  template=`curl -sS https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml | sed -e "s/kube-system/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  template=`curl -sS https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/heapster.yaml | sed -e "s/kube-system/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  template=`curl -sS https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/influxdb.yaml | sed -e "s/kube-system/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}  
  template=`curl -sS https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/rbac/heapster-rbac.yaml | sed -e "s/kube-system/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}    
  if [[ $EXTERNALDASHBOARD = "yes" ]]; 
      then kubectl get service kubernetes-dashboard-external -n $NAMESPACE >> "${LOG_OUTPUT}" 2>&1
           if [[ $? = 0 ]];
                then logger "blue" "The Kubernetes dashboard is already exposed to the Internet. Skipping...";
                else kubectl expose deployment kubernetes-dashboard --type=LoadBalancer --name=kubernetes-dashboard-external -n $NAMESPACE >> "${LOG_OUTPUT}" 2>&1 ; 
                     errorcheck ${FUNCNAME}
                     logger "blue" "Warning: I am exposing the Kubernetes dashboard to the Internet...";
           fi;
      else logger "blue" "The Kubernetes dashboard is not being exposed to the Internet......";
  fi
  # If you opted not expose the dashboard via the ELB, start the proxy like this: kubectl proxy --port=8080 --accept-hosts="^*$" 
  # and connect to: http://localhost:8080/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login
  # grab the token: kubectl -n kube-system describe secret $(kubectl -n kube-system get secret | grep eks-admin | awk '{print $1}')
  logger "green" "Dashboard has been installed properly!"
}

albingresscontroller() {
  logger "green" "ALB Ingress controller setup is starting..."
  # source: https://kubernetes-sigs.github.io/aws-alb-ingress-controller/guide/controller/setup/ 
  aws iam put-role-policy --role-name $NODE_INSTANCE_ROLE --policy-name ALB-Ingress-Policy-For-Worker --policy-document file://./configurations/alb-ingress-policy.json >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  template=`cat "configurations/alb-ingress-service-account.yaml" | sed -e "s/NAMESPACE/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  template=`cat "./configurations/alb-ingress-controller.yaml" | sed -e "s/CLUSTERNAME/$CLUSTERNAME/g" -e "s/NAMESPACE/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  sleep 15
  # background: https://github.com/pahud/eks-alb-ingress 
  logger "green" "ALB Ingress controller has been installed properly!"
}

prometheus() {
  logger "green" "Prometheus setup is starting..."
  #template=`cat "./configurations/prometheus-storageclass.yaml" | sed -e "s/NAMESPACE/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1
  #errorcheck ${FUNCNAME}
  #echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  #errorcheck ${FUNCNAME}
  chart=`/usr/local/bin/helm list prometheus --output json | jq --raw-output .Releases[0].Name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $chart = "prometheus" ]]; 
      then logger "blue" "Prometheus is already installed. Skipping..."; 
      else if [[ $EXTERNALPROMETHEUS = "yes" ]]; 
                then /usr/local/bin/helm install stable/prometheus \
                                      --name prometheus \
                                      --namespace $NAMESPACE \
                                      --set alertmanager.persistentVolume.storageClass="gp2" \
                                      --set server.persistentVolume.storageClass="gp2" \
                                      --set server.service.type=LoadBalancer >> "${LOG_OUTPUT}" 2>&1 
                    errorcheck ${FUNCNAME}
                    logger "blue" "Prometheus is being exposed to the Internet......";
                else /usr/local/bin/helm install stable/prometheus \
                                      --name prometheus \
                                      --namespace $NAMESPACE \
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
  chart=`/usr/local/bin/helm list grafana --output json | jq --raw-output .Releases[0].Name`  >> "${LOG_OUTPUT}" 2>&1
  if [[ $chart = "grafana" ]]; 
      then logger "blue" "Grafana is already installed. Skipping..."; 
      else # /usr/local/bin/helm install -f configurations/grafana-values.yaml stable/grafana --name grafana --namespace $NAMESPACE >> "${LOG_OUTPUT}" 2>&1
          /usr/local/bin/helm install stable/grafana \
            --name grafana \
            --namespace $NAMESPACE \
            --set persistence.storageClassName="gp2" \
            --set adminPassword="EKS!sAWSome" \
            --set datasources."datasources\.yaml".apiVersion=1 \
            --set datasources."datasources\.yaml".datasources[0].name=Prometheus \
            --set datasources."datasources\.yaml".datasources[0].type=prometheus \
            --set datasources."datasources\.yaml".datasources[0].url=http://prometheus-server.$NAMESPACE.svc.cluster.local \
            --set datasources."datasources\.yaml".datasources[0].access=proxy \
            --set datasources."datasources\.yaml".datasources[0].isDefault=true \
            --set service.type=LoadBalancer >> "${LOG_OUTPUT}" 2>&1 ;
  fi
  errorcheck ${FUNCNAME}
  logger "green" "Grafana has been installed properly!"
}

cloudwatchcontainerinsights() {
  logger "green" "CloudWatch Containers Insights setup is starting..."
  aws iam attach-role-policy --role-name $NODE_INSTANCE_ROLE --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  curl -O https://s3.amazonaws.com/cloudwatch-agent-k8s-yamls/kubernetes-monitoring/cwagent-serviceaccount.yaml >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  template=`cat "./cwagent-serviceaccount.yaml" | sed -e "s/amazon-cloudwatch/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  curl -O https://s3.amazonaws.com/cloudwatch-agent-k8s-yamls/kubernetes-monitoring/cwagent-configmap.yaml >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  template=`cat "./cwagent-configmap.yaml" | sed -e "s/amazon-cloudwatch/$NAMESPACE/g" -e "s/{{cluster_name}}/$CLUSTERNAME/g"` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME} 
  curl -O https://s3.amazonaws.com/cloudwatch-agent-k8s-yamls/kubernetes-monitoring/cwagent-daemonset.yaml >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  template=`cat "./cwagent-daemonset.yaml" | sed -e "s/amazon-cloudwatch/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME} 
  # ------
  clusterinfo=`kubectl get configmap cluster-info -n $NAMESPACE --output json --ignore-not-found | jq --raw-output .metadata.name` >> "${LOG_OUTPUT}" 2>&1
  if [[ $clusterinfo = "cluster-info" ]]; 
      then logger "blue" "The cluster-info configmap is already there. Skipping..."; 
      else kubectl create configmap cluster-info --from-literal=cluster.name=$CLUSTERNAME --from-literal=logs.region=$REGION -n $NAMESPACE  >> "${LOG_OUTPUT}" 2>&1 ;
  fi
  errorcheck ${FUNCNAME}
  curl -O https://s3.amazonaws.com/cloudwatch-agent-k8s-yamls/fluentd/fluentd.yml >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  template=`cat "./fluentd.yml" | sed -e "s/amazon-cloudwatch/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME} 
  logger "green" "CloudWatch Containers Insights has been installed properly!"
}

clusterautoscaler() {
  logger "green" "Cluster Autoscaler deployment is starting..."
  # the iam policy ASG-Policy-For-Worker may be redundant if the cluster is installed with eksctl and the --asg-access flag 
  aws iam put-role-policy --role-name $NODE_INSTANCE_ROLE --policy-name ASG-Policy-For-Worker --policy-document file://./configurations/k8s-asg-policy.json >> "${LOG_OUTPUT}" 2>&1 
  template=`cat "./configurations/cluster_autoscaler.yaml" | sed -e "s/AUTOSCALINGGROUPNAME/$AUTOSCALINGGROUPNAME/g" -e "s/MINNODES/$MINNODES/g" -e "s/MAXNODES/$MAXNODES/g" -e "s/AWSREGION/$REGION/g" -e "s/NAMESPACE/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "Cluster Autoscaler has been installed properly!"
}

appmesh() {
  logger "green" "Appmesh components setup is starting..."
  # https://docs.aws.amazon.com/app-mesh/latest/userguide/mesh-k8s-integration.html
  curl -o ./configurations/appmeshall.yaml https://raw.githubusercontent.com/aws/aws-app-mesh-controller-for-k8s/master/deploy/all.yaml  >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  aws iam attach-role-policy --role-name $NODE_INSTANCE_ROLE --policy-arn arn:aws:iam::aws:policy/AWSAppMeshFullAccess >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  template=`cat "./configurations/appmeshall.yaml"` >> "${LOG_OUTPUT}" 2>&1   
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  curl -o install.sh https://raw.githubusercontent.com/aws/aws-app-mesh-inject/master/scripts/install.sh >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  echo "The mesh name is: " $MESH_NAME >> "${LOG_OUTPUT}" 2>&1
  chmod +x install.sh  >> "${LOG_OUTPUT}" 2>&1
  ./install.sh  >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  # for now I am enabling only the default namespace to inject the sidecar automatically
  # given the default namespace I am deploying to (and the only one that works today) is 'kube-system' I don't want to enable that label there 
  kubectl label namespace default appmesh.k8s.aws/sidecarInjectorWebhook=enabled --overwrite >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "Appmesh components have been installed properly"
}

demoapp() {
  logger "green" "Demo application setup is starting..."
  if [ ! -d yelb ]; then git clone https://github.com/mreferre/yelb >> "${LOG_OUTPUT}" 2>&1
  fi 
  errorcheck ${FUNCNAME}
  kubectl apply -f ./yelb/deployments/platformdeployment/Kubernetes/yaml/yelb-k8s-ingress-alb.yaml --namespace=$NAMESPACE >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  # without the following sleep a potential race condition creating the demo app ingress and the kubeflow ingress (below) is noticed
  # this sleep may be possibly reduced but this would require further investigation and a potentially more elegant solution   
  sleep 120 
  logger "green" "Demo application has been installed properly!"
}

kubeflow () {
  logger "green" "Kubeflow setup is starting..."
  if [ ! -d kubeflow-aws ]; then 
    mkdir ./kubeflow-aws >> "${LOG_OUTPUT}" 2>&1
    errorcheck ${FUNCNAME}
    cd kubeflow-aws >> "${LOG_OUTPUT}" 2>&1
    errorcheck ${FUNCNAME}
    export KUBEFLOW_SRC=$(pwd)
    export KUBEFLOW_TAG=v0.5-branch
    curl -sS https://raw.githubusercontent.com/kubeflow/kubeflow/${KUBEFLOW_TAG}/scripts/download.sh | bash >> "${LOG_OUTPUT}" 2>&1
    errorcheck ${FUNCNAME}
    export KFAPP=kfapp
    cd ${KUBEFLOW_SRC} >> "${LOG_OUTPUT}" 2>&1
    errorcheck ${FUNCNAME}
    ${KUBEFLOW_SRC}/scripts/kfctl.sh init ${KFAPP} --platform aws \
    --awsClusterName ${CLUSTERNAME} \
    --awsRegion ${REGION} \
    --awsNodegroupRoleNames ${NODE_INSTANCE_ROLE} >> "${LOG_OUTPUT}" 2>&1
    errorcheck ${FUNCNAME}
    cd ${KFAPP} >> "${LOG_OUTPUT}" 2>&1
    errorcheck ${FUNCNAME}
    ${KUBEFLOW_SRC}/scripts/kfctl.sh generate platform  >> "${LOG_OUTPUT}" 2>&1
    errorcheck ${FUNCNAME}
    ${KUBEFLOW_SRC}/scripts/kfctl.sh apply platform >> "${LOG_OUTPUT}" 2>&1
    errorcheck ${FUNCNAME}
    ${KUBEFLOW_SRC}/scripts/kfctl.sh generate k8s >> "${LOG_OUTPUT}" 2>&1
    errorcheck ${FUNCNAME}
    ${KUBEFLOW_SRC}/scripts/kfctl.sh apply k8s >> "${LOG_OUTPUT}" 2>&1
    errorcheck ${FUNCNAME}
    cd ../..
    sleep 120 
    logger "green" "Kubeflow has been installed properly!";
    else logger "blue" "Kubeflow seems to be already installed. Skipping..."; 
    fi;
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
  if [[ $KUBEFLOW = "yes" ]]; then KUBEFLOWALBURL=`kubectl get ingress -n istio-system --output json | jq --raw-output .items[0].status.loadBalancer.ingress[0].hostname`; fi >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "Congratulations! You made it!"
  logger "green" "Your EKStended kubernetes environment is ready to be used"
  logger "green" "------"
  logger "yellow" "Grafana UI           : http://"$GRAFANAELB 
  logger "yellow" "Prometheus UI        : http://"$PROMETHEUSELB
  logger "yellow" "Kubernetes Dashboard : https://"$DASHBOARDELB":8443" 
  logger "yellow" "Demo application     : http://"$DEMOAPPALBURL
  logger "yellow" "Kubeflow             : http://"$KUBEFLOWALBURL
  logger "green" "------"
  logger "green" "Note that it may take several minutes for these end-points to be fully operational"
  logger "green" "If you see a <null> or no value you specifically opted out for that particular feature or the LB isn't ready yet (check with kubectl)"
  logger "green" "Enjoy!"
}

main() {
  welcome
  preparenamespace
  admin_sa
  calico
  tiller
  metricserver
  dashboard
  albingresscontroller
  prometheus
  grafana 
  cloudwatchcontainerinsights
  clusterautoscaler
  appmesh
  if [[ $DEMOAPP = "yes" ]]; then demoapp; fi;
  if [[ $KUBEFLOW = "yes" ]]; then kubeflow; fi;
  congratulations
}

main 
