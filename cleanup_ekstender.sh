#!/bin/bash

export REGION=us-west-2
export NODES=6 # this is only used if you want to deploy the cluster as part of the process 
export CLUSTERNAME=eks1
export NODE_INSTANCE_ROLE=eksctl-eks1-nodegroup-ng-65104b3e-NodeInstanceRole-XXXXXXXXX # the IAM role assigned to the worker nodes
export AUTOSCALINGGROUPNAME=eksctl-eks1-nodegroup-ng-65104b3e-NodeGroup-XXXXXXX # the name of the ASG
export MINNODES=2 # the min number of nodes in the ASG
export MAXNODES=4 # the max number of nodes in the ASG
export EXTERNALDASHBOARD=yes 
export EXTERNALPROMETHEUS=no 
export DEMOAPP=yes 
export NAMESPACE="kube-system"

kubectl delete -f ./yelb/deployments/platformdeployment/Kubernetes/yaml/cnawebapp-ingress-alb.yaml --namespace=$NAMESPACE

/usr/local/bin/helm delete --purge metric-server

template=`cat "./configurations/cluster_autoscaler.yaml" | sed -e "s/AUTOSCALINGGROUPNAME/$AUTOSCALINGGROUPNAME/g" -e "s/MINNODES/$MINNODES/g" -e "s/MAXNODES/$MAXNODES/g" -e "s/AWSREGION/$REGION/g" -e "s/NAMESPACE/$NAMESPACE/g"` 
echo "$template" | kubectl delete -f -
aws iam delete-role-policy --role-name $NODE_INSTANCE_ROLE --policy-name ASG-Policy-For-Worker

template=`curl https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/v1.3/calico.yaml | sed -e "s/kube-system/$NAMESPACE/g"`
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

template=`cat "./configurations/tiller-service-account.yaml" | sed "s/NAMESPACE/$NAMESPACE/g"`
echo "$template" | kubectl delete -f -
kubectl delete deployment tiller-deploy -n kube-system
kubectl delete service tiller-deploy -n kube-system

template=`cat "./configurations/fluentd.yaml" | sed -e "s/NAMESPACE/$NAMESPACE/g"`
echo "$template" | kubectl delete -f - 
aws iam delete-role-policy --role-name $NODE_INSTANCE_ROLE --policy-name Logs-Policy-For-Worker

template=`cat "./configurations/eks-admin-service-account.yaml" | sed -e "s/NAMESPACE/$NAMESPACE/g"`
echo "$template" | kubectl delete -f - 

