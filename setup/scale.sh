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

export KUBECONFIG=$PWD/kubeconfig.yaml
echo "export KUBECONFIG=$KUBECONFIG" >> .env

export USE_GKE_GCLOUD_AUTH_PLUGIN=True

export PROJECT_ID=dot-$(date +%Y%m%d%H%M%S)
echo "export PROJECT_ID=$PROJECT_ID" >> .env

gcloud auth login

gcloud projects create $PROJECT_ID

echo "# Open https://console.cloud.google.com/marketplace/product/google/container.googleapis.com?project=$PROJECT_ID in a browser and enable the Kubernetes Engine API" \
    | gum format
gum input --placeholder "Press the enter key to continue."

gcloud container clusters create dot --project $PROJECT_ID \
    --zone us-east1-b --machine-type e2-standard-2 \
    --num-nodes 1 --no-enable-autoupgrade \
    --enable-vertical-pod-autoscaling

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
