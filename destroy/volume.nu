#!/usr/bin/env nu

let hyperscaler = open settings.yaml | get hyperscaler


if $hyperscaler == "google" {

    let project_id = open settings.yaml | get google.projectId

    (
        gcloud container clusters delete dot 
            --project $project_id --zone us-east1-b --quiet
    )

    gcloud projects delete $project_id --quiet

}
