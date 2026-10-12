#!/bin/sh
# Downloads the Our World in Data CO2 and greenhouse gas emissions dataset.
set -e
mkdir -p data
curl -L -o data/owid-co2-data.csv https://raw.githubusercontent.com/owid/co2-data/master/owid-co2-data.csv
echo "Saved data/owid-co2-data.csv"
