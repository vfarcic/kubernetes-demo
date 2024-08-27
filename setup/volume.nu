#!/usr/bin/env nu

let hyperscaler = [google aws azure]
    | input list $"(ansi green_bold)Which Hyperscaler do you want to use?(ansi yellow_bold)"

$"export HYPERSCALER=($hyperscaler)\n" | save --append .env

open settings.yaml
    | upsert hyperscaler $hyperscaler
    | save settings.yaml --force

$env.KUBECONFIG = $"($env.PWD)/kubeconfig.yaml"

mut ingress_ip = ""

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

}

(
    helm upgrade --install traefik traefik
        --repo https://helm.traefik.io/traefik
        --namespace traefik --create-namespace --wait
)

if $hyperscaler == "google" {

    while $ingress_ip == "" {
        print "Waiting for Ingress Service IP..."
        $ingress_ip = (
            kubectl --namespace projectcontour
                get service contour-envoy --output yaml
                | from yaml
                | get status.loadBalancer.ingress.0.ip
        )
    }

}

$"export INGRESS_HOST=($ingress_ip)\n" | save --append .env

open volume/ingress.yaml
    | upsert spec.rules.0.host $"silly-demo.($ingress_ip).nip.io"
    | save volume/ingress.yaml --force

kubectl create namespace a-team

kubectl --namespace a-team apply --filename volume/service.yaml

kubectl --namespace a-team apply --filename volume/ingress.yaml
