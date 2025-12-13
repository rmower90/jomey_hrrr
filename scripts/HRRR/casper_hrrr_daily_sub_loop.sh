#!/bin/bash -l
#PBS -N daily_hrrr_dwnload_loop_test
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
year='2025'
month='10'
day='06'
directory='/glade/derecho/scratch/rossamower/snow/data/met/hrrr/raw/2026/'

# identify missing days.
python ./generate_download_todolist.py $year $month $day $directory


CSV="wus_hrrr_daily_download_todo.csv"
test -s "$CSV"   # non-empty file required

tail -n +2 "$CSV" | while IFS=',' read -r date directory_; do
    date="${date//$'\r'/}"
    directory_="${directory_//$'\r'/}"

    echo "Downloading: ${date}"
    echo "Target dir:  ${directory_}"
    time ./download_hrrr_directory.sh $date $directory_
    echo "Appending Checklist......"
    python ./generate_download_checklist.py $date
done




echo "FINISHED DOWNLOAD..."




