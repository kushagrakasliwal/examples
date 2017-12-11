#!/bin/sh

# Horizon workload to subscribe to the Watson IoT Platform MQTT

# This workload expects the CPU microservice to be running.  Run 'make' in the
# sibling directory "../microservice" to start that microservice running.  You
# can verify that microservcie is working by running 'make check' here.

# Verify required configuration and credentials are in the process environment
checkRequiredEnvVar() {
  varname=$1
  if [ -z $(eval echo \$$varname) ]; then
    echo "ERROR: Environment variable $varname must be set; exiting."
    exit 1
  fi
}
checkRequiredEnvVar "WIOTP_DOMAIN"
checkRequiredEnvVar "WIOTP_ORG_ID"
checkRequiredEnvVar "WIOTP_DEVICE_TYPE"
checkRequiredEnvVar "WIOTP_DEVICE_AUTH_TOKEN"
checkRequiredEnvVar "HZN_DEVICE_ID"
echo "Configuration credentials successfully received from process environment."

# Check the exit status of the previously run command and exit if nonzero
checkrc() {
  if [[ $1 -ne 0 ]]; then
    echo "ERROR: Last command exited with rc $1."
    exit 1
  fi
}

# Topic to which this program will subscribe
WIOTP_MQTT_TOPIC="iot-2/evt/status/fmt/json"

# If Watson IoT Platform API credentials are not provided assume existence.
if [ -z $(eval echo \$WIOTP_API_KEY) ] || [ -z $(eval echo \$WIOTP_API_AUTH_TOKEN) ]; then
  echo "Watson IoT Platfrom REST API credentials were not provided:"
  echo "    WIOTP_API_KEY=\"$WIOTP_API_KEY\""
  echo "    WIOTP_API_AUTH_TOKEN=\"$WIOTP_API_AUTH_TOKEN\""
  echo "Assuming type \"$WIOTP_DEVICE_TYPE\" with ID \"$HZN_DEVICE_ID\" exists in Watson IoT Platform."
else
  # Both credentials provided; prepare for Watson IoT Platform REST API calls
  echo "API credentials successfully received from process environment."
  copts='-sS -w %{http_code}'
  wiotpApiAuth="$WIOTP_API_KEY:$WIOTP_API_AUTH_TOKEN"
  apiUrl="https://$WIOTP_ORG_ID.$WIOTP_DOMAIN/api/v0002"
  contentJson='Content-Type: application/json'

  # Verify the specified WIOTP_DEVICE_TYPE exists and if not, exit.
  httpCode=$(curl $copts -u "$wiotpApiAuth" -o /dev/null $apiUrl/device/types/$WIOTP_DEVICE_TYPE)
  checkrc $?
  if [[ "$httpCode" == "404" ]]; then
    echo "Watson IoT device Type \"$WIOTP_DEVICE_TYPE\" does not exist."
    exit 1
  fi
  echo "Device Type \"$WIOTP_DEVICE_TYPE\" exists in Watson IoT Platform."

  # Does the specified HZN_DEVICE_ID exist?  If not, create it.
  httpCode=$(curl $copts -u "$wiotpApiAuth" -o /dev/null $apiUrl/device/types/$WIOTP_DEVICE_TYPE/devices/$HZN_DEVICE_ID)
  checkrc $?
  if [[ "$httpCode" == "404" ]]; then
    echo "Creating device \"$HZN_DEVICE_ID\" in Watson IoT Platform..."
    body='{"deviceId":"'$HZN_DEVICE_ID'", "authToken":"'$WIOTP_DEVICE_TOKEN'", "deviceInfo":{"description":"My edge device"}}, "metadata":{}}'
    output=$(curl $copts -u "$wiotpApiAuth" -X POST -H "$contentJson" -d "$body" $apiUrl/device/types/$WIOTP_DEVICE_TYPE/devices)
    checkrc $?
    httpCode=${output:$((${#output}-3))} # last 3 chars are http status code
    if [[ "$httpCode" != "201" ]]; then
      echo "ERROR: Failed to create device $HZN_DEVICE_ID: $output"
      exit 1
    fi
  elif [[ "$httpCode" != "200" ]]; then
    echo "ERROR: HTTP code $httpCode was returned when trying to check for device \"$HZN_DEVICE_ID\". Exiting..."
    exit 1
  fi
  echo "Device \"$HZN_DEVICE_ID\" exists in Watson IoT Platform."
fi

echo "Subscribing to topic '$WIOTP_MQTT_TOPIC'..."
msgHost="$WIOTP_ORG_ID.messaging.$WIOTP_DOMAIN"
clientId="d:$WIOTP_ORG_ID:$WIOTP_DEVICE_TYPE:$HZN_DEVICE_ID"
mosquitto_sub -h $msgHost -p 8883 -i $clientId -u "use-token-auth" -P $WIOTP_DEVICE_AUTH_TOKEN --cafile messaging.pem -q 2 -t $WIOTP_MQTT_TOPIC

# Not reached
checkrc $?