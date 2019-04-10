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
export REGION=us-west-2
export NODES=6 # this is only used if you want to deploy the cluster as part of the process 
export CLUSTERNAME=amazing-party-1554300136
export NODE_INSTANCE_ROLE=eksctl-amazing-party-1554300136-n-NodeInstanceRole-XXXXXXXXXXX # the IAM role assigned to the worker nodes 
export EXTERNALDASHBOARD=yes 
export EXTERNALPROMETHEUS=no
export NAMESPACE="kube-system"
###########################################################
###########           END OF USER INPUTS        ###########
###########################################################

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
  logger "yellow" "External Dashboard    : $EXTERNALDASHBOARD"
  logger "yellow" "External Prometheus   : $EXTERNALPROMETHEUS"
  logger "green" "Press [Enter] to continue or CTRL-C to abort..."
  read -p " "
}

createcluster() {
  logger "green" "Ekstender launched with the from-scratch switch: EKS cluster creation initiated. This may take a few minutes..."
  eksctl create cluster --name=$CLUSTERNAME --nodes=$NODES --node-ami=auto --region=$REGION >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "EKS cluster creation concluded..."

}

admin-sa() {
  logger "green" "Creation of the generic eks-admin service account is starting..."
  kubectl apply -f configurations/eks-admin-service-account.yaml >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "Creation of the generic eks-admin service account has completed..."
}

logging() {
  logger "green" "Logging configuration is starting..."
  aws iam put-role-policy --role-name $NODE_INSTANCE_ROLE --policy-name Logs-Policy-For-Worker --policy-document file://./configurations/k8s-logs-policy.json >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  template=`cat "./configurations/fluentd.yaml" | sed -e "s/CLUSTERNAME/$CLUSTERNAME/g" -e "s/AWS_REGION/$REGION/g" -e "s/NAMESPACE/$NAMESPACE/g"` >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "Logging has been configured properly!"
}

helm() {
  logger "green" "Helm setup is starting..."
  curl -o get_helm.sh https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get >> "${LOG_OUTPUT}" 2>&1 
  chmod +x get_helm.sh >> "${LOG_OUTPUT}" 2>&1 
  ./get_helm.sh >> "${LOG_OUTPUT}" 2>&1 
  template=`cat "./configurations/tiller-service-account.yaml" | sed "s/NAMESPACE/$NAMESPACE/g"`
  echo "$template" | kubectl apply -f - >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  # for some reasons running helm without the explicit path will cause this function to loop (to be investigated)
  /usr/local/bin/helm init --service-account tiller >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  # we apparently need to sync the helm client and server (reference: https://github.com/helm/charts/issues/5239)
  # wonder what the ramifications of a complex production setup may be
  /usr/local/bin/helm init --upgrade >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  sleep 10
  logger "green" "Helm has been installed properly!"
}

dashboard() {
  logger "green" "Dashboard setup is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/dashboard-tutorial.html
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml >> "${LOG_OUTPUT}" 2>&1  
  errorcheck ${FUNCNAME}
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/heapster.yaml >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/influxdb.yaml >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/rbac/heapster-rbac.yaml >> "${LOG_OUTPUT}" 2>&1
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
      else /usr/local/bin/helm install -f configurations/grafana-values.yaml stable/grafana --name grafana --namespace $NAMESPACE >> "${LOG_OUTPUT}" 2>&1 ;
  fi
  errorcheck ${FUNCNAME}
  logger "green" "Grafana has been installed properly!"
}

calico() {
  logger "green" "Calico setup is starting..."
  # source: https://docs.aws.amazon.com/eks/latest/userguide/calico.html 
  # This one will be installed in kube-system. To change the ns one would need to put the yaml in the configurations directory and parametrize it
  kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/v1.3/calico.yaml >> "${LOG_OUTPUT}" 2>&1 
  errorcheck ${FUNCNAME}
  logger "green" "Calico has been installed properly!"
}

congratulations() {
  GRAFANAELB=`kubectl get service grafana -n $NAMESPACE --output json | jq --raw-output .status.loadBalancer.ingress[0].hostname` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  DASHBOARDELB=`kubectl get service kubernetes-dashboard-external -n $NAMESPACE --output json | jq --raw-output .status.loadBalancer.ingress[0].hostname` >> "${LOG_OUTPUT}" 2>&1
  errorcheck ${FUNCNAME}
  logger "green" "Congratulations! You made it!"
  logger "green" "Your EKStended kubernetes environment is ready to be used now"
  logger "yellow" "Grafana UI           : http://"$GRAFANAELB 
  logger "yellow" "Kubernetes Dashboard : https://"$DASHBOARDELB":8443" 
  logger "green" "Enjoy!"
}

main() {
  #if [[ $1 = "from-scratch" ]]; then createcluster; else logger "blue" "Skipping cluster creation...";fi
  welcome
  admin-sa
  logging
  helm
  dashboard
  albingresscontroller
  calico
  prometheus 
  grafana 
  congratulations
}

main 
