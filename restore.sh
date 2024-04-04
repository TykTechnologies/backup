#!/bin/bash

export() {
    local url=""
    local secret=""
    local output=""

    # Parse flags
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
            --output)
                output="$2"
                shift 2
                ;;
            *)
                echo "Unknown flag: $1"
                help
                exit 1
                ;;
        esac
    done

    # Validation
    if [[ -z "$url" ]]; then
        echo "Error: --url is required, which indicates the URL of Tyk Dashboard"
        help
        exit 1
    elif [[ -z "$secret" ]]; then 
        echo "Error: --secret is required, which indicates the access key of your user in Tyk Dashboard"
        help
        exit 1
    elif [[ -z "$output" ]]; then
        echo "Error: --output is required, which indicates the output file including all Tyk API Definitions"
        help
        exit 1
    fi

    echo "=> Creating backup API Definitions file from $url..."

    # Send a GET request to list all resources
    response=$(curl -f -s -H "Authorization: $secret" "$url/api/apis?p=-2")
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Failed to fetch API Definitions from Tyk Dashboard $url by using user access key $secret"
        exit 1
    fi

    echo "$response" | jq > "$output"

    echo "=> Creating backup Policy file from $url..."
    response=$(curl -f -s -H "Authorization: $secret" "$url/api/portal/policies?p=-2")
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Failed to fetch Policies from Tyk Dashboard $url by using user access key $secret"
        exit 1
    fi
    echo "$response" | jq > policies.json

    echo "Export operation completed, API Definition backup file: $output, Policy backup file: policies.json."
}

# Function to upload files
upload() {
    local url=""
    local secret=""
    local file=""

    # Parse flags
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
            --file)
                file="$2"
                shift 2
                ;;
            *)
                echo "Unknown flag: $1"
                exit 1
                ;;
        esac
    done

    # Validation
    if [[ -z "$url" ]]; then
        echo "Error: --url is required, which indicates the URL of Tyk Dashboard"
        help
        exit 1
    elif [[ -z "$secret" ]]; then 
        echo "Error: --secret is required, which indicates the access key of your user in Tyk Dashboard"
        help
        exit 1
    elif [[ -z "$file" ]]; then
        echo "Error: --file is required, which indicates the file including all Tyk API Definitions to be uploaded"
        help
        exit 1
    fi

    jq -c '.apis[]' $file | while read -r api;
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
            echo -e "\t[ERROR] Failed to upload OAS API Definition with ID: $apiID, status code: $statusCode"
          fi
      else
          echo "=> Uploading Classic API Definition with ID: $apiID to Tyk Dashboard: $url"
          statusCode=$(curl -o "./logs.json" -s -f -X POST -H "Authorization: $secret" -d "$api" "$url/api/apis/" -w "%{http_code}")
          if [[ $statusCode -ge 200 ]] && [[ $statusCode -lt 300 ]]; then
            echo "Classic API Definition with ID $apiID uploaded to Tyk Dashboard successfully."
          elif [[ $statusCode -eq 409 ]]; then
            echo "Classic API Definition with ID $apiID already exists on Tyk Dashboard."
          else
            echo -e "\t[ERROR] Failed to upload Classic API Definition with ID: $apiID, status code: $statusCode"
          fi
      fi
    done

    jq -c '.Data[]' policies.json | while read -r policy;
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
          echo -e "\t[ERROR] Failed to upload Policy $policyName, status code: $statusCode, response: $content"
        fi
      fi
    done
}


help() {
    instructions=$(cat readme)
    echo "$instructions"
}

# Main script logic
if [ "$#" -eq 0 ]; then
    echo "No command specified. Please use 'export' or 'upload'."
    help
    exit 1
fi

# Check the first argument to determine which command to run
case $1 in
    export)
        shift
        export "$@"
        ;;
    upload)
        shift
        upload "$@"
        ;;
    *)
        echo "Invalid command. Please use 'export' or 'upload'."
        help
        exit 1
        ;;
esac

