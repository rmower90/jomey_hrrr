#!/bin/bash -l
#PBS -N monthly_hrrr_dwnload
#PBS -A P48500028
#PBS -l select=1:ncpus=1:mpiprocs=1:ompthreads=1:mem=10GB
#PBS -l walltime=4:00:00
#PBS -q casper
#PBS -j oe

### Set TMPDIR as recommended
export TMPDIR=/glade/derecho/scratch/$USER/temp_serial
mkdir -p $TMPDIR


###module swap
module load conda
conda activate jomey_hrrr


echo "PROCESSING..."
echo $year
echo $month
echo $directory


###module swap
time ./download_hrrr_directory.sh $year $month $directory
echo "FINISHED DOWNLOAD..."
### After download — verify & repair each daily directory
echo "Verifying downloaded HRRR directories..."
VERIFY_SCRIPT="./verify_and_repair_hrrr.sh"

# Safety check
if [[ ! -x "$VERIFY_SCRIPT" ]]; then
  echo "ERROR: verify script not found or not executable: $VERIFY_SCRIPT"
  exit 1
fi

# Loop through directories like: /path/to/.../hrrr.YYYYMMDD
for day_dir in "${directory}/hrrr.${year}${month}"*; do
  if [[ -d "$day_dir" ]]; then
    echo "Running verification for: $day_dir"
    "$VERIFY_SCRIPT" "$day_dir"
  else
    echo "No matching directory for pattern: ${directory}/hrrr.${year}${month}*"
  fi
done

echo "All verification checks complete."

