#!/usr/bin/env nu

let hyperscaler = open settings.yaml | get hyperscaler


if $hyperscaler == "google" {

    let project_id = open settings.yaml | get google.projectId

    (
        gcloud container clusters delete dot 
            --project $project_id --zone us-east1-b --quiet
    )

    gcloud projects delete $project_id --quiet

} else if $hyperscaler == "aws" {

    eksctl delete cluster --config-file eksctl.yaml

} else {

    let resource_group = open settings.yaml
        | get azure.resourceGroup
    let location = open settings.yaml | get azure.location

    (
        az aks delete --resource-group $resource_group --name dot
            --yes
    )

    az group delete --name $resource_group --yes

}

rm --force kubeconfig.yaml
