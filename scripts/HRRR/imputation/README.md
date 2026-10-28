# Imputation

The historic HRRR archive has various forms of missing and corrupt files, relevant for the F01 and F06 forecasting variables needed to run SnowModel. These scripts are intended to be run in four stages:
Stage 1). to identify missing and corrupt files (`diagnose.py`)
    - 2019 Ex. `python3 diagnose.py 2019 --out ledger_2019.csv --workers 16`
Stage 2). identify donor files for imputation (`plan_repairs.py`)
    - 2019 Ex. `python3 plan_repairs.py ledger_2019.csv --out plan_2019.csv`
Stage 3). create a new directory with simlinks of both available files and imputed files (`execute.py`)
    - 2019 Ex. `python3 execute.py ledger_2019.csv plan_2019.csv --out-base /glade/derecho/scratch/rossamower/snow/data/met/hrrr/raw_filled` 
Stage 4). final verification that new imputed directory has all the necessary files (`diagnose.py`)
    - 2019 Ex. `python3 diagnose.py 2019 --raw-base /glade/derecho/scratch/rossamower/snow/data/met/hrrr/raw_filled --out final_verify_2019.csv --workers 16`

***NOTE:*** The current file directory is hodecoded and should be adjusted on different computer systems. Additionally, I recommend activating the `jomey_hrrr` conda environment to run these scripts.