#!/usr/bin/env nu

rm --force .env

rm --force kubeconfig.yaml

$env.KUBECONFIG = $"($env.PWD)/kubeconfig.yaml"
$"export KUBECONFIG=($env.KUBECONFIG)\n" | save --append .env

let hyperscaler = [aws azure google]
    | input list $"(ansi green_bold)Which Hyperscaler do you want to use?(ansi yellow_bold)"

$"(ansi reset)"

$"export HYPERSCALER=($hyperscaler)\n" | save --append .env

open settings.yaml
    | upsert hyperscaler $hyperscaler
    | save settings.yaml --force

mut storage_class = "standard"

if $hyperscaler == "google" {

    gcloud auth login

    let project_id = $"dot-(date now | format date "%Y%m%d%H%M%S")"

    open settings.yaml
        | upsert google.projectId $project_id
        | save settings.yaml --force

    gcloud projects create $project_id

    start $"https://console.cloud.google.com/marketplace/product/google/container.googleapis.com?project=($project_id)"

    print $"(ansi yellow_bold)
ENABLE(ansi reset) the API.
Press any key to continue.
"
    input

    (
        gcloud container clusters create dot --project $project_id
            --zone us-east1-b --machine-type e2-standard-2
            --num-nodes 1 --no-enable-autoupgrade
    )    

} else if $hyperscaler == "aws" {

    if "AWS_ACCESS_KEY_ID" not-in $env {
        $env.AWS_ACCESS_KEY_ID = input $"(ansi green_bold)Enter AWS Access Key ID: (ansi reset)"
        $"export AWS_ACCESS_KEY_ID=($env.AWS_ACCESS_KEY_ID)\n"
            | save --append .env
    }

    if "AWS_SECRET_ACCESS_KEY" not-in $env {
        $env.AWS_SECRET_ACCESS_KEY = input $"(ansi green_bold)Enter AWS Secret Access Key: (ansi reset)"
        $"export AWS_SECRET_ACCESS_KEY=($env.AWS_SECRET_ACCESS_KEY)\n"
            | save --append .env
    }

    if "AWS_ACCOUNT_ID" not-in $env {
        $env.AWS_ACCOUNT_ID = input $"(ansi green_bold)Enter AWS Account ID: (ansi reset)"
        $"export AWS_ACCOUNT_ID=($env.AWS_ACCOUNT_ID)\n"
            | save --append .env
    }

    (
        eksctl create cluster --config-file eksctl.yaml
            --kubeconfig kubeconfig.yaml
    )

    (
        eksctl create addon --name aws-ebs-csi-driver
            --service-account-role-arn $"arn:aws:iam::($env.AWS_ACCOUNT_ID):role/AmazonEKS_EBS_CSI_DriverRole"
            --cluster dot --region us-east-1 --force
    )

    kubectl apply --filename volume/storage-class-aws.yaml

} else {

    if "AZURE_TENANT_ID" not-in $env {
        $env.AZURE_TENANT_ID = input $"(ansi green_bold)Enter Azure Tenant ID: (ansi reset)"
    }

    az login --tenant $env.AZURE_TENANT_ID

    let resource_group = $"dot-(date now | format date "%Y%m%d%H%M%S")"
    let location = "eastus"
    open settings.yaml
        | upsert azure.resourceGroup $resource_group
        | upsert azure.location $location
        | save settings.yaml --force

    az group create --name $resource_group --location $location

    (
        az aks create --resource-group $resource_group --name dot
            --node-count 1 --node-vm-size Standard_B2s
            --enable-managed-identity --generate-ssh-keys --yes
    )

    (
        az aks get-credentials --resource-group $resource_group
            --name dot --file $env.KUBECONFIG
    )

    $storage_class = "managed"

}

open volume/persistent-volume-claim.yaml
    | upsert spec.storageClassName $storage_class
    | save volume/persistent-volume-claim.yaml --force


(
    helm upgrade --install traefik traefik
        --repo https://helm.traefik.io/traefik
        --namespace traefik --create-namespace --wait
)

mut ingress_ip = ""

if $hyperscaler == "google" or $hyperscaler == "azure" {

    while $ingress_ip == "" {
        print "Waiting for Ingress Service IP..."
        sleep 10sec
        $ingress_ip = (
            kubectl --namespace traefik
                get service traefik --output yaml
                | from yaml
                | get status.loadBalancer.ingress.0.ip
        )
    }

} else {
    
    mut ingress_ip_name = ""

    while $ingress_ip == "" {
        print "Waiting for Ingress Service IP..."
        sleep 10sec
        $ingress_ip_name = (
            kubectl --namespace traefik
                get service traefik --output yaml
                | from yaml
                | get status.loadBalancer.ingress.0.hostname
        )
        $ingress_ip = ( dig +short $ingress_ip_name )
    }

    $ingress_ip = $ingress_ip | lines | first

}

$"export INGRESS_HOST=($ingress_ip)\n" | save --append .env

open volume/ingress.yaml
    | upsert spec.rules.0.host $"silly-demo.($ingress_ip).nip.io"
    | save volume/ingress.yaml --force

kubectl create namespace a-team

for file in ["service.yaml", "ingress.yaml"] {
    kubectl --namespace a-team apply --filename $"volume/($file)"
}
