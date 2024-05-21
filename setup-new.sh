#!/bin/sh
set -e

gum confirm '
The setup for this demo is based on Google Cloud GKE.
Please open an issue if you prefer adding one of the other hyperscalers.
Are you ready to start?
Feel free to say "No" and inspect the script if you prefer setting up resources manually.
' || exit 0

###########
# Cluster #
###########

echo "## Which Hyperscaler do you want to use?" | gum format
HYPERSCALER=$(gum choose "google" "aws" "azure")
echo "export HYPERSCALER=$HYPERSCALER" >> .env

export KUBECONFIG=$PWD/kubeconfig.yaml
echo "export KUBECONFIG=$KUBECONFIG" >> .env

if [[ "$HYPERSCALER" == "google" ]]; then

    export USE_GKE_GCLOUD_AUTH_PLUGIN=True

    export PROJECT_ID=dot-$(date +%Y%m%d%H%M%S)

    gcloud auth login

    gcloud projects create $PROJECT_ID

    echo "# Open https://console.cloud.google.com/marketplace/product/google/container.googleapis.com?project=$PROJECT_ID in a browser and enable the Kubernetes Engine API" \
        | gum format
    gum input --placeholder "Press the enter key to continue."

    gcloud container clusters create dot --project $PROJECT_ID \
        --zone us-east1-b --machine-type e2-standard-2 \
        --num-nodes 1 --no-enable-autoupgrade \
        --enable-vertical-pod-autoscaling

elif [[ "$HYPERSCALER" == "aws" ]]; then

    AWS_ACCOUNT_ID=$(gum input --placeholder "AWS Account ID" --value "$AWS_ACCOUNT_ID")
    echo "export AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID" >> .env

    AWS_ACCESS_KEY_ID=$(gum input \
        --placeholder "AWS Access Key ID" \
        --value "$AWS_ACCESS_KEY_ID")
    echo "export AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID" >> .env
    
    AWS_SECRET_ACCESS_KEY=$(gum input \
        --placeholder "AWS Secret Access Key" \
        --value "$AWS_SECRET_ACCESS_KEY" --password)
    echo "export AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY" >> .env

    eksctl create cluster --config-file eksctl.yaml \
        --asg-access --kubeconfig kubeconfig.yaml

    eksctl create addon --name aws-ebs-csi-driver \
        --service-account-role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole \
        --cluster dot --region us-east-1 --force

    helm upgrade --install metrics-server metrics-server \
        --repo https://kubernetes-sigs.github.io/metrics-server \
        --namespace kube-system --create-namespace --wait

    helm upgrade --install vpa vertical-pod-autoscaler \
        --repo https://cowboysysop.github.io/charts \
        --namespace kube-system --create-namespace --wait

elif [[ "$HYPERSCALER" == "azure" ]]; then

    echo "TODO:"

fi

########
# Apps #
########

kubectl create namespace a-team

helm upgrade --install keda keda \
    --repo https://kedacore.github.io/charts \
    --namespace keda --create-namespace --wait

helm upgrade --install prometheus prometheus \
    --repo https://prometheus-community.github.io/helm-charts \
    --namespace monitoring --create-namespace --wait
