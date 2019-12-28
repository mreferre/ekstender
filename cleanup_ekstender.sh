#!/bin/bash

: ${REGION:=$(aws configure get region)}
: ${NAMESPACE:="kube-system"}
: ${MESH_NAME:="ekstender-mesh"}

# scripts read $1 as clustername. If $1 is not used it defaults to eks1
if [ -z "$1" ]; then echo "Please specify the cluster you want to clean!"; exit; else export CLUSTERNAME=$1; fi
export STACK_NAME=$(eksctl get nodegroup --cluster $CLUSTERNAME --region $REGION  -o json | jq -r '.[].StackName')
: ${NODE_INSTANCE_ROLE:=$(aws cloudformation describe-stack-resources --region $REGION --stack-name $STACK_NAME | jq -r '.StackResources[] | select(.LogicalResourceId=="NodeInstanceRole") | .PhysicalResourceId' )}  # the IAM role assigned to the worker nodes
: ${AUTOSCALINGGROUPNAME:=$(aws cloudformation describe-stack-resources --region $REGION --stack-name $STACK_NAME | jq -r '.StackResources[] | select(.LogicalResourceId=="NodeGroup") | .PhysicalResourceId')}  # the name of the ASG

if [ -d $(pwd)/kubeflow-aws ]; then
        export KUBEFLOW_SRC=$(pwd)/kubeflow-aws
        export KFAPP=kfapp
        cd ${KUBEFLOW_SRC}/${KFAPP}
        ${KUBEFLOW_SRC}/scripts/kfctl.sh delete k8s
        cd ../..
        rm -r ./kubeflow-aws
        aws iam delete-role-policy --role-name $NODE_INSTANCE_ROLE --policy-name iam_alb_ingress_policy
        aws iam delete-role-policy --role-name $NODE_INSTANCE_ROLE --policy-name iam_csi_fsx_policy 
fi 

# this needs investigation. The command below, when ran in the script can leave a zombie ALB. When ran standalone the ALB typically gets deleted properly 
# potentially some race conditions between the istio ALB de-registration (as part of the kubeflow uninstall) and this? 
sleep 10 
if [ -d ./yelb ]; then
        kubectl delete -f ./yelb/deployments/platformdeployment/Kubernetes/yaml/cnawebapp-ingress-alb.yaml --namespace=$NAMESPACE
        sleep 10
fi 

kubectl delete crd meshes.appmesh.k8s.aws
kubectl delete crd virtualnodes.appmesh.k8s.aws
kubectl delete crd virtualservices.appmesh.k8s.aws
kubectl delete namespace appmesh-system
# the below needs investigation. The docs say the injector is deployed in appmesh-inject but 
# it appears to be installing in the appmesh-system namespace (and appmesh-inject is not even created)
#kubectl delete namespace appmesh-inject
kubectl delete clusterrolebinding appmesh-inject
kubectl delete clusterrolebinding app-mesh-controller-binding
kubectl delete clusterrole appmesh-inject 
kubectl delete clusterrole app-mesh-controller
kubectl label namespace default appmesh.k8s.aws/sidecarInjectorWebhook-
aws iam detach-role-policy --role-name $NODE_INSTANCE_ROLE --policy-arn arn:aws:iam::aws:policy/AWSAppMeshFullAccess

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
kubectl delete configmap cluster-info -n $NAMESPACE
template=`cat "./fluentd.yml" | sed -e "s/amazon-cloudwatch/$NAMESPACE/g"`
echo "$template" | kubectl delete -f - 

/usr/local/bin/helm delete --purge grafana 

/usr/local/bin/helm delete --purge prometheus 

template=`cat "./configurations/alb-ingress-controller.yaml" | sed -e "s/CLUSTERNAME/$CLUSTERNAME/g" -e "s/NAMESPACE/$NAMESPACE/g"`
echo "$template" | kubectl delete -f -
sleep 2
template=`cat "configurations/alb-ingress-service-account.yaml" | sed -e "s/NAMESPACE/$NAMESPACE/g"`
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
