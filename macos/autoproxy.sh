#!/bin/bash

### Default proxy configurations
 proxy_host="172.17.0.2"
 proxy_port="8080"
 proxy_user="username"
 SHOW_PROXY_SETTINGS=true
 SHOW_PROXY_PASSWORD=false

 ### Define url encoding function
 urlencode() {
     # This function will take a string as an argument and encode it to URL encoding
     local string="${1}"
     local strlen=${#string}
     local encoded=""

     for (( pos=0 ; pos<strlen ; pos++ )); do
        c="${string:$pos:1}"
        case "$c" in
           [-_.~a-zA-Z0-9] ) o="${c}" ;;
           * )               printf -v o '%%%02x' "'$c"
        esac
        encoded+="${o}"
     done
     echo "${encoded}"    # You can either set a return variable (FASTER)
 }

 # Check if proxy host was set in system, if not use default
 read proxy_host proxy_port <<< $(scutil --proxy | awk -v proxy_host="$proxy_host" -v proxy_port="$proxy_port" '\
   /HTTPEnable/ { enabled = $3; } \
   /HTTPProxy/ { server = $3; } \
   /HTTPPort/ { port = $3; } \
   /ProxyAutoConfigEnable/ { script_enabled = $3; } \
   END { if (enabled == "1" || script_enabled == "1") { if (server == "" && port == "") { server = proxy_host; port = proxy_port; } print server" "port; } }')

 ### Read password from key chain
 proxy_password=$(urlencode $(security find-internet-password -s $proxy_host -w))

 ### If proxy_host and proxy_password are set and not empty string, do proxy setup
 if [[ -n "$proxy_host" ]]; then
   ### Do the proxy setup
   if [[ -n "$proxy_user" && -n "$proxy_password" ]]; then
     export http_proxy=http://$proxy_user:$proxy_password@$proxy_host:$proxy_port
   else
     export http_proxy=http://$proxy_host:$proxy_port
   fi
   export HTTP_PROXY="${http_proxy}"
   export https_proxy="${http_proxy}"
   export HTTPS_PROXY="${https_proxy}"
output=$(php artisan 2>&1)

   ### Do the no_proxy setup ###
   # Extract the ExceptionsList array
   exceptions=$(scutil --proxy | awk '/ExceptionsList/ {getline; while (getline > 0 && !/\}/) {gsub(/^[[:space:]]*|[[:space:]]*$/,"");print $0}}')

   # Remove the array index numbers
   exceptions=$(echo "$exceptions" | sed -e 's/^[[:digit:]]* : //' -e 's/\*\.//')

   # Replace newlines with commas
   joined_values=$(echo "$exceptions" | tr '\n' ',')

   # Set the no_proxy environment variable
   export no_proxy="localhost,127.0.0.1,$joined_values"
 fi


### Echo proxy setting on screen
 if [[ "$SHOW_PROXY_SETTINGS" = true ]]; then
   echo PROXY SETTINGS:
   if [[ "$SHOW_PROXY_PASSWORD" = true ]]; then
     echo http_proxy: $http_proxy
     echo https_proxy: $https_proxy
   else
     echo http_proxy: $(echo $http_proxy | sed -E 's/\/\/([^:]*):[^@]*@/\/\/\1:***@/g')
     echo https_proxy: $(echo $https_proxy | sed -E 's/\/\/([^:]*):[^@]*@/\/\/\1:***@/g')
   fi
   echo no_proxy: $no_proxy
 fi
