#!/bin/bash

export() {
    local url=""
    local secret=""
    local apiOutputFile=""
    local policyOutputFile=""

    while (( "$#" )); do
        case "$1" in
            --url)
                url="$2"
                shift 2
                ;;
            --secret)
                secret="$2"
                shift 2
                ;;
            --api-output )
                apiOutputFile="$2"
                shift 2
                ;;
            --policy-output)
                policyOutputFile="$2"
                shift 2
                ;;
            *)
                echo "Unknown flag: $1"
                help
                exit 1
                ;;
        esac
    done

    if [[ -z "$url" ]]; then
        echo "Error: --url is required, which indicates the URL of Tyk Dashboard"
        help
        exit 1
    elif [[ -z "$secret" ]]; then 
        echo "Error: --secret is required, which indicates the access key of your user in Tyk Dashboard"
        help
        exit 1
    elif [[ -z "$apiOutputFile" ]]; then
        echo "Error: --api-output is required, which indicates the output file including all Tyk API Definitions"
        help
        exit 1
    elif [[ -z "$policyOutputFile" ]]; then
        echo -e "Warning: --policy-output is empty, backup will not export Policies from Tyk Dashboard\n"
    fi

    echo "=> Creating backup API Definitions file from $url..."

    response=$(curl -f -s -H "Authorization: $secret" "$url/api/apis?p=-2")
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Failed to fetch API Definitions from Tyk Dashboard $url by using user access key $secret"
        exit 1
    fi

    echo "$response" | jq > "$apiOutputFile"

    if [[ -n "$policyOutputFile" ]]; then
      echo "=> Creating backup Policy file from $url..."
      response=$(curl -f -s -H "Authorization: $secret" "$url/api/portal/policies?p=-2")
      if [[ $? -ne 0 ]]; then
          echo "[ERROR] Failed to fetch Policies from Tyk Dashboard $url by using user access key $secret"
          exit 1
      fi
      echo "$response" | jq > "$policyOutputFile"

      echo "Export operation completed, API Definition backup file: $apiOutputFile, Policy backup file: $policyOutputFile."
    else
      echo "Export operation completed, API Definition backup file: $apiOutputFile."
    fi
}

import() {
    local url=""
    local secret=""
    local apiFile=""
    local policyFile=""

    while (( "$#" )); do
        case "$1" in
            --url)
                url="$2"
                shift 2
                ;;
            --secret)
                secret="$2"
                shift 2
                ;;
            --api-file)
                apiFile="$2"
                shift 2
                ;;
            --policy-file)
                policyFile="$2"
                shift 2
                ;;
            *)
                echo "Unknown flag: $1"
                exit 1
                ;;
        esac
    done

    if [[ -z "$url" ]]; then
        echo "Error: --url is required, which indicates the URL of Tyk Dashboard"
        help
        exit 1
    elif [[ -z "$secret" ]]; then 
        echo "Error: --secret is required, which indicates the access key of your user in Tyk Dashboard"
        help
        exit 1
    elif [[ -z "$apiFile" ]]; then
        echo "Error: --api-file is required, which indicates the file including all Tyk API Definitions to be uploaded"
        help
        exit 1
     elif [[ -z "$policyFile" ]]; then
        echo -e "Warning: --policy-file is empty, backup will not import Policies to Tyk Dashboard\n"
    fi

    jq -c '.apis[]' "$apiFile" | while read -r api;
    do
      apiID=$(echo "$api" | jq .api_definition.id)
      if isOAS=$(echo "$api" | jq -e '.api_definition.is_oas'); then
          echo "=> Uploading OAS API Definition with ID: $apiID to Tyk Dashboard: $url"
          oasBody=$(echo "$api" | jq '.oas')

          statusCode=$(curl -o "./oas-logs.json" -s -f -X POST -H "Authorization: $secret" -d "$oasBody" "$url/api/apis/oas" -w "%{http_code}")
          if [[ $statusCode -ge 200 ]] && [[ $statusCode -lt 300 ]]; then
            echo "OAS API Definition with ID $apiID uploaded to Tyk Dashboard successfully."
          elif [[ $statusCode -eq 409 ]]; then
            echo "OAS API Definition with ID $apiID already exists on Tyk Dashboard."
          else
            echo -e "\t[ERROR] Failed to import OAS API Definition with ID: $apiID, status code: $statusCode"
          fi
      else
          echo "=> Uploading Classic API Definition with ID: $apiID to Tyk Dashboard: $url"
          statusCode=$(curl -o "./logs.json" -s -f -X POST -H "Authorization: $secret" -d "$api" "$url/api/apis/" -w "%{http_code}")
          if [[ $statusCode -ge 200 ]] && [[ $statusCode -lt 300 ]]; then
            echo "Classic API Definition with ID $apiID uploaded to Tyk Dashboard successfully."
          elif [[ $statusCode -eq 409 ]]; then
            echo "Classic API Definition with ID $apiID already exists on Tyk Dashboard."
          else
            echo -e "\t[ERROR] Failed to import Classic API Definition with ID: $apiID, status code: $statusCode"
          fi
      fi
    done

    if [[ -n "$policyFile" ]]; then
      jq -c '.Data[]' "$policyFile" | while read -r policy;
      do
        policyName=$(echo "$policy" | jq .name)
        policyId=$(echo "$policy" | jq -r ._id)
        echo "=> Uploading Policy '$policyName' with ID $policyId to Tyk Dashboard: $url"

        response=$(curl -s -H "Authorization: $secret" -X GET "$url/api/portal/policies/$policyId" -w "\n%{http_code}")
        statusCode=$(tail -n1 <<< "$response")
        content=$(sed '$ d' <<< "$response")
        echo -e "\t Checking if Policy exists..."
        if [[ $statusCode -ge 200 ]] && [[ $statusCode -lt 399 ]]; then
          echo -e "\t Policy $policyName already exists on Tyk Dashboard"
        else
          echo -e "\t Policy does not exists, response from Tyk Dashboard $content"
          response=$(curl -s -X POST -H "Authorization: $secret" -d "$policy" "$url/api/portal/policies" -w "\n%{http_code}")
          statusCode=$(tail -n1 <<< "$response")
          content=$(sed '$ d' <<< "$response")

          if [[ $statusCode -ge 200 ]] && [[ $statusCode -lt 300 ]]; then
            echo "Policy $policyName uploaded to Tyk Dashboard successfully."
          else
            echo -e "\t[ERROR] Failed to import Policy $policyName, status code: $statusCode, response: $content"
          fi
        fi
      done
    fi
}


help() {
    cat << EOF
Usage: ./backup.sh [command] [options]

Commands:
 help      Print this message
 export    Export Tyk API Definitions and Policies from a Tyk Dashboard.
 import    Upload Tyk API Definitions and Policies to a Tyk Dashboard.

Options:
 --url            URL of the Tyk Dashboard (required).
 --secret         Access key of your user in the Tyk Dashboard (required).
 --api-output     (export only) Output file for the exported Tyk API Definitions (required).
 --policy-output  (export only) Output file for the exported Tyk Policies (optional).
 --api-file       (import only) File containing the Tyk API Definitions to be uploaded (required).
 --policy-file    (import only) File containing the Tyk Policies to be uploaded (optional).

Examples:
   Export Tyk API Definitions:
      ./backup.sh export --url https://my-tyk-dashboard.com --secret mysecretkey --api-output apis.json

   Export Tyk API Definitions and Policies:
      ./backup.sh export --url https://my-tyk-dashboard.com --secret mysecretkey --api-output apis.json --policy-output policies.json

   Upload Tyk API Definitions:
      ./backup.sh import --url https://my-tyk-dashboard.com --secret mysecretkey --api-file apis.json

   Upload Tyk API Definitions and Policies:
      ./backup.sh import --url https://my-tyk-dashboard.com --secret mysecretkey --api-file apis.json --policy-file policies.json
EOF
}

# Main script logic
if [ "$#" -eq 0 ]; then
    echo "No command specified. Please use 'help', 'export' or 'import'."
    help
    exit 1
fi

# Check the first argument to determine which command to run
case $1 in
    export)
        shift
        export "$@"
        ;;
    import)
        shift
        import "$@"
        ;;
    help)
        shift
        help "$@"
        ;;
    *)
        echo "Invalid command. Please use 'export' or 'import'."
        help
        exit 1
        ;;
esac

