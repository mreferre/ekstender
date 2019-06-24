#!/bin/bash

: ${VAR:=foo}    
: ${REGION:=us-west-2} 
: ${CLUSTERNAME:=eks1} 
: ${NODE_INSTANCE_ROLE:=eksctl-eks1-nodegroup-ng-7abe0bdc-NodeInstanceRole-XXXXXXXX}  # the IAM role assigned to the worker nodes
: ${AUTOSCALINGGROUPNAME:=eksctl-eks1-nodegroup-ng-7abe0bdc-NodeGroup-XXXXXXXX}  # the name of the ASG
: ${MINNODES:=2}  # the min number of nodes in the ASG
: ${MAXNODES:=4}  # the max number of nodes in the ASG
: ${EXTERNALDASHBOARD:=yes}  
: ${EXTERNALPROMETHEUS:=yes}  
: ${DEMOAPP:=yes}  
: ${NAMESPACE:="kube-system"} 

kubectl delete -f ./yelb/deployments/platformdeployment/Kubernetes/yaml/cnawebapp-ingress-alb.yaml --namespace=$NAMESPACE

template=`cat "./configurations/cluster_autoscaler.yaml" | sed -e "s/AUTOSCALINGGROUPNAME/$AUTOSCALINGGROUPNAME/g" -e "s/MINNODES/$MINNODES/g" -e "s/MAXNODES/$MAXNODES/g" -e "s/AWSREGION/$REGION/g" -e "s/NAMESPACE/$NAMESPACE/g"` 
echo "$template" | kubectl delete -f -
aws iam delete-role-policy --role-name $NODE_INSTANCE_ROLE --policy-name ASG-Policy-For-Worker

aws iam detach-role-policy --role-name $NODE_INSTANCE_ROLE --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy 
template=`cat "./cwagent-serviceaccount.yaml" | sed -e "s/amazon-cloudwatch/$NAMESPACE/g"` 
echo "$template" | kubectl delete -f -
template=`cat "./cwagent-configmap.yaml" | sed -e "s/amazon-cloudwatch/$NAMESPACE/g" -e "s/{{cluster-name}}/$CLUSTERNAME/g"`
echo "$template" | kubectl delete -f - 
template=`cat "./cwagent-daemonset.yaml" | sed -e "s/amazon-cloudwatch/$NAMESPACE/g"`
echo "$template" | kubectl delete -f - 
#---
kubectl delete configmap cluster-info -n $NAMESPACE
template=`cat "./fluentd.yml" | sed -e "s/amazon-cloudwatch/$NAMESPACE/g"`
echo "$template" | kubectl delete -f - 

/usr/local/bin/helm delete --purge grafana 

/usr/local/bin/helm delete --purge prometheus 

template=`cat "configurations/alb-ingress-service-account.yaml" | sed -e "s/NAMESPACE/$NAMESPACE/g"`
echo "$template" | kubectl delete -f - 
template=`cat "./configurations/alb-ingress-controller.yaml" | sed -e "s/CLUSTERNAME/$CLUSTERNAME/g" -e "s/NAMESPACE/$NAMESPACE/g"`
echo "$template" | kubectl delete -f -
aws iam delete-role-policy --role-name $NODE_INSTANCE_ROLE --policy-name ALB-Ingress-Policy-For-Worker 

template=`curl https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml | sed -e "s/kube-system/$NAMESPACE/g"`
echo "$template" | kubectl delete -f - 
template=`curl https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/heapster.yaml | sed -e "s/kube-system/$NAMESPACE/g"`  
echo "$template" | kubectl delete -f -
template=`curl https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/influxdb.yaml | sed -e "s/kube-system/$NAMESPACE/g"` 
echo "$template" | kubectl delete -f -
template=`curl https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/rbac/heapster-rbac.yaml | sed -e "s/kube-system/$NAMESPACE/g"`  
echo "$template" | kubectl delete -f -
kubectl delete service kubernetes-dashboard-external -n $NAMESPACE

/usr/local/bin/helm delete --purge metric-server

template=`cat "./configurations/tiller-service-account.yaml" | sed "s/NAMESPACE/$NAMESPACE/g"`
echo "$template" | kubectl delete -f -
kubectl delete deployment tiller-deploy -n $NAMESPACE
kubectl delete service tiller-deploy -n $NAMESPACE

template=`curl https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/v1.4/calico.yaml | sed -e "s/kube-system/$NAMESPACE/g"`
echo "$template" | kubectl delete -f -

template=`cat "./configurations/eks-admin-service-account.yaml" | sed -e "s/NAMESPACE/$NAMESPACE/g"`
echo "$template" | kubectl delete -f - 

#template=`cat "./configurations/fluentd.yaml" | sed -e "s/NAMESPACE/$NAMESPACE/g"`
#echo "$template" | kubectl delete -f - 
#aws iam delete-role-policy --role-name $NODE_INSTANCE_ROLE --policy-name Logs-Policy-For-Worker