#!/usr/bin/env bash
# Loop through CSV with columns: year,month,directory

INPUT_CSV="year_month_test.csv"

# Skip header and read each line
tail -n +2 "$INPUT_CSV" | while IFS=',' read -r year month directory; do
  echo "Year: $year"
  echo "Month: $month"
  echo "Directory: $directory"
  qsub -v year=${year},month=${month},directory=${directory} ./casper_hrrr_sub.sh 
  sleep 2

  # Example usage: call your HRRR download script
  # ./download_hrrr.sh "$year" "$month" "$directory" Google

  echo "------------------------"
done
