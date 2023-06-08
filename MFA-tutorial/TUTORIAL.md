# Keystone Multi Factor Authentication (MFA) with TOTP

This quick start tutorial will show an example process of activating and using Multi-Factor Authentication (MFA) in OpenStack Keystone with Time-based One-time Password (TOTP) as provided by Keystone.

### 1\. Configure Keystone

Adjust your Keystone server's `keystone.conf`:

```
[auth]
methods = password,token,totp
```

Restart the service after the changes

### 2\. Create a test user

Generic:

```bash
openstack user create mfa-user; \
openstack user set --password '5f8DE1WiaEYcTtqKEIn5' mfa-user; \
openstack project create mfa-project; \
openstack role add --user mfa-user --project mfa-project member
```

(password here is just an example)

Store the returned user id for later:

```bash
export USER_ID=43716137b8414587a34523c5f5b3383c
```

(id here is just an example)

### 3\. Configure MFA for user (as admin)

```bash
export AUTH_TOKEN=$(openstack token issue -f value -c id)
curl -X PATCH \
-H "X-Auth-Token: $AUTH_TOKEN" \
-H "Content-Type: application/json" \
$OS_AUTH_URL/users/$USER_ID \
-d '{ "user": { "options": { "multi_factor_auth_enabled": true, "multi_factor_auth_rules": [ ["password", "totp"] ] } } }'
```

### 4\. Configure TOTP (as admin)

Generate a secret.  
Please replace the `message` string in the following example by something secure and random:

```bash
export SECRET=$(echo -n 1937587123749071 | base32 | tr -d =)
echo $SECRET
```

Register the secret in Keystone for that user, use the `USER_ID` from above:

```bash
export AUTH_TOKEN=$(openstack token issue -f value -c id)
export USER_ID=43716137b8414587a34523c5f5b3383c
curl -X POST \
-H "X-Auth-Token: $AUTH_TOKEN" \
-H "Content-Type: application/json" \
$OS_AUTH_URL/credentials \
-d '{ "credential": { "blob": "'$SECRET'", "type": "totp", "user_id": "'$USER_ID'" } }'
```

### 5\. Generate QR code from secret for user (as admin)

Insert the `SECRET` from above, adjust `name` / `issuer`, and execute the script with Python (make sure `python3-qrcode` package is installed):

```python
#!/usr/bin/env python3
import qrcode

secret='GE4TGNZVHA3TCMRTG42DSMBXGE'
uri = 'otpauth://totp/{name}?secret={secret}&issuer={issuer}'.format(
    name='mfa-user@openstack.org',
    secret=secret,
    issuer='Keystone')

img = qrcode.make(uri)
img.save('totp.png')
```

Transfer the resulting `totp.png` image to the user and have them register with the FreeOTP+ App by scanning the image.

### 6\. Authenticate with TOTP (as user)

The following scripts and instructions are relevant to the user who aims to authenticate with MFA.s

#### 6\.1 TOTP MFA Script

Create `mfa-auth.sh`:

```bash
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
```

The script will export the retrieved token as `OS_TOKEN`, which the `openstack` client will pick up subsequently.  
You can check the retrieved token via `echo $OS_TOKEN`.
However, to be able to properly use this token in the `openstack` client, another script is necessary to align the `OS_` variables correctly.

#### 6\.2 RC File

Create `mfa-user.openrc`:

```bash
# unset any OS_ variables that conflict with token-token authentication
unset OS_USERNAME
unset OS_USER_DOMAIN_NAME
unset OS_REGION_NAME
unset OS_INTERFACE
unset OS_PASSWORD

# variables which are mandatory for the token-only authentication are:
# - OS_TOKEN
# - OS_PROJECT_NAME
# - OS_PROJECT_DOMAIN_NAME
# - OS_AUTH_URL
# (those variables should still be exported from the previous scripts and RC file)
export OS_INTERFACE=public
export OS_AUTH_TYPE=token
```

This script will make sure that all `OS_` variables are aligned in a way that appeases the `openstack` client so that the usage of `OS_TOKEN` as the sole authentication for issuing commands becomes possible after acquiring said `OS_TOKEN` using the MFA process.

**NOTE:** the exact constellation of the `OS_` variables is absolutely important. Having extraneous or missing variables can make the `openstack` client trip up easily with non-obvious error patterns!

#### 6\.3 Usage

> **NOTE:** the order and way (i.e. using `source`) of using these scripts is absolutely crucial!

```bash
source mfa-auth.sh
source mfa-user.openrc

openstack image list
```

After `source`'ing both scripts, the authentication persists in the current shell session (within the `OS_TOKEN` environment variable) for as long as the token is valid (depends on the individual Keystone's token expiration setting).
After its expiration, the process beginning with `source mfa-auth.sh` has to be repeated.