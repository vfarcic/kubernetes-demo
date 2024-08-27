#!/usr/bin/env nu

rm --force .env

rm --force kubeconfig.yaml

$env.KUBECONFIG = $"($env.PWD)/kubeconfig.yaml"
$"export KUBECONFIG=($env.KUBECONFIG)\n" | save --append .env

let hyperscaler = [google aws azure]
    | input list $"(ansi green_bold)Which Hyperscaler do you want to use?(ansi yellow_bold)"

$"(ansi reset)"

$"export HYPERSCALER=($hyperscaler)\n" | save --append .env

open settings.yaml
    | upsert hyperscaler $hyperscaler
    | save settings.yaml --force

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
            --zone us-east1-b --machine-type e2-standard-4
            --num-nodes 2 --no-enable-autoupgrade
    )    

} else if $hyperscaler == "aws" {

    if $env.AWS_ACCESS_KEY_ID == "" {
        $env.AWS_ACCESS_KEY_ID = input $"(ansi green_bold)Enter AWS Access Key ID: (ansi reset)"
        $"export AWS_ACCESS_KEY_ID=($env.AWS_ACCESS_KEY_ID)\n"
            | save --append .env
    }

    if $env.AWS_SECRET_ACCESS_KEY == "" {
        $env.AWS_SECRET_ACCESS_KEY = input $"(ansi green_bold)Enter AWS Secret Access Key: (ansi reset)"
        $"export AWS_SECRET_ACCESS_KEY=($env.AWS_SECRET_ACCESS_KEY)\n"
            | save --append .env
    }

    if $env.AWS_ACCOUNT_ID == "" {
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

}

(
    helm upgrade --install traefik traefik
        --repo https://helm.traefik.io/traefik
        --namespace traefik --create-namespace --wait
)

mut ingress_ip = ""

if $hyperscaler == "google" {

    while $ingress_ip == "" {
        print "Waiting for Ingress Service IP..."
        sleep 5sec
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
        sleep 5sec
        $ingress_ip_name = (
            kubectl --namespace traefik
                get service traefik --output yaml
                | from yaml
                | get status.loadBalancer.ingress.0.hostname
        )
        $ingress_ip = ( dig +short $ingress_ip_name )
    }

}

$"export INGRESS_HOST=($ingress_ip)\n" | save --append .env

open volume/ingress.yaml
    | upsert spec.rules.0.host $"silly-demo.($ingress_ip).nip.io"
    | save volume/ingress.yaml --force

kubectl create namespace a-team

kubectl --namespace a-team apply --filename volume/service.yaml

kubectl --namespace a-team apply --filename volume/ingress.yaml
