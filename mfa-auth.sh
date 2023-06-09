#!/bin/bash

# Note: you can skip defining the variables here if the user
# sources their "openrc" file beforehand anyway!
OS_AUTH_URL=http://controller:5000/v3
OS_USERNAME=mfa-user
OS_USER_DOMAIN_NAME=Default
OS_PROJECT_DOMAIN_NAME=Default
OS_PROJECT_NAME=mfa-project

echo "Please enter your OpenStack Password for project $OS_PROJECT_NAME as user $OS_USERNAME: "
read -sr OS_PASSWORD

echo "Please generate and enter a TOTP authentication code: "
read -r OS_TOTP_CODE

export OS_TOKEN=$(curl -v -s -X POST \
"$OS_AUTH_URL/auth/tokens?nocatalog" -H "Content-Type: application/json" \
-d '{
    "auth": {
        "identity": {
            "methods": ["password", "totp"],
            "password": {
                "user": {
                    "domain": {
                        "name": "'"$OS_USER_DOMAIN_NAME"'"
                    },
                    "name": "'"$OS_USERNAME"'",
                    "password": "'"$OS_PASSWORD"'"
                }
            },
            "totp": {
                "user": {
                    "domain": {
                        "name": "'"$OS_USER_DOMAIN_NAME"'"
                    },
                    "name": "'"$OS_USERNAME"'",
                    "passcode": "'"$OS_TOTP_CODE"'"
                }
            }
        },
        "scope": {
            "project": {
                "domain": {
                    "name": "'"$OS_PROJECT_DOMAIN_NAME"'"
                },
                "name": "'"$OS_PROJECT_NAME"'"
                }
            }
        }
    }' \
--stderr - | grep -i "X-Subject-Token" | cut -d':' -f2 | tr -d ' ' | tr -d '\r')