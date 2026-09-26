#!/bin/bash
echo
usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

echo "Usage : ${usage}%"


if ["$usage" -gt 80]; then
	echo "Alerte"
else
	echo "Espace OK"
fi 
