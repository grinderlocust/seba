#!/bin/bash
#ask the user for login detalis

read -p 'Username: ' uservar
read -sp 'Password: ' passvar
echo $passvar >> text.txt
echo
echo Thank you $uservar we now have your login details
