#!/bin/bash -l
#PBS -N daily_hrrr_dwnload_20221229
#PBS -A P48500028
#PBS -l select=1:ncpus=1:mpiprocs=1:ompthreads=1:mem=20GB
#PBS -l walltime=1:00:00
#PBS -q casper
#PBS -j oe

### Set TMPDIR as recommended
export TMPDIR=/glade/derecho/scratch/$USER/temp_serial
mkdir -p $TMPDIR


###module swap
module load conda
conda activate jomey_hrrr


echo "PROCESSING..."
year='2022'
month='12'
day='29'
directory='/glade/derecho/scratch/rossamower/snow/data/met/hrrr/raw/2023/'


###module swap
# echo "./download_hrr_directory.sh ${year}${month}
time ./download_hrrr_directory.sh "${year}${month}${day}" $directory
echo "FINISHED DOWNLOAD..."
### After download — verify & repair each daily directory
echo "Verifying downloaded HRRR directories..."
VERIFY_SCRIPT="./verify_and_repair_hrrr.sh"

# Safety check
if [[ ! -x "$VERIFY_SCRIPT" ]]; then
  echo "ERROR: verify script not found or not executable: $VERIFY_SCRIPT"
  exit 1
fi
day_dir="${directory}/hrrr.${year}${month}${day}"
echo "Running verification for: $day_dir"
"$VERIFY_SCRIPT" "$day_dir"
echo "All verification checks complete."

