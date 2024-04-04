#!/bin/bash

#!/bin/bash

# Function to copy files
copy() {
    local url=""
    local secret=""
    local dir=""

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
            --dir)
                dir="$2"
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
        exit 1
    elif [[ -z "$secret" ]]; then 
        echo "Error: --secret is required, which indicates the access key of your user in Tyk Dashboard"
        exit 1
    # elif [[ -z "$dir" ]]; then
    #     echo "Error: --dir is required, which indicates the local path where OAS APIs will be saved from Tyk Dashboard"
    #     exit 1
    fi

    echo "Copying files from $url to $dir..."

    echo "Checking OAS APIs from $url..."
    # Send a GET request to list all resources
    response=$(curl -f -s -H "Authorization: $secret" "$url/api/apis?-p=2")
    if [[ $? -ne 0 ]]; then
        echo "[ERROR] Failed to fetch APIs from Tyk Dashboard $url by using user access key $secret"
        exit 1
    fi

    oasAPIs=$(echo "$response" | jq '.apis[] | select(.api_definition.is_oas)')

    # Iterate over each enabled resource and download it
    for id in $(echo "${oasAPIs}" | jq -r '.api_definition.id'); do
        echo "Downloading resource with ID: $id into ${id}.json..."
        statusCode=$(curl -s -f -H "Authorization: $secret" "$url/api/apis/oas/$id/export" -o "tykoas-$id.json" -w "%{http_code}")
        if [[ $statusCode -ge 200 ]] && [[ $statusCode -lt 300 ]]; then
            echo -e "$id.json is created..."
        else
            echo -e "\t[ERROR] Failed to download OAS API with ID: $id, status code: $statusCode" 
        fi
    done

    echo "Copy operation completed."
}

# Function to upload files
upload() {
    echo "uploading files..."
    echo "upload operation completed."
}

# Main script logic
if [ "$#" -eq 0 ]; then
    echo "No command specified. Please use 'copy' or 'upload'."
    exit 1
fi

# Check the first argument to determine which command to run
case $1 in
    copy)
        shift
        copy "$@"
        ;;
    upload)
        upload
        ;;
    *)
        echo "Invalid command. Please use 'copy' or 'upload'."
        exit 1
        ;;
esac

