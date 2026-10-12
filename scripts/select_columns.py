"""Stream the OWID CSV and keep only the columns used by this project.

psql's \\copy cannot pick columns out of a wider file, so this small helper
does it and writes CSV to standard output.
"""
import csv
import sys

KEEP = ["country", "year", "iso_code", "population", "gdp", "co2",
        "co2_per_capita", "methane", "nitrous_oxide", "total_ghg"]

with open(sys.argv[1], newline="", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    writer = csv.writer(sys.stdout)
    writer.writerow(KEEP)
    for row in reader:
        writer.writerow([row[c] for c in KEEP])
