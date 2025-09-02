#!/usr/bin/env bash
# Script to install all required components from GitHub repositories for
# development. Requires to have a fully setup and activated conda environment.
#
# The below components are installed with the latest from the master branch:
#  - AWSM
#  - SMRF
#
# Install location is given via the first parameter or defaults to $HOME/iSnobal

set -e

ISNOBAL_HOME=${1:-$HOME/iSnobal}
mkdir -p ${ISNOBAL_HOME}

cd $ISNOBAL_HOME

######
# GitHub repositories
# Will install from source and editable
######

declare -a repositories=(
  "https://github.com/iSnobal/awsm.git"
  "https://github.com/iSnobal/smrf.git"
)

for repository in "${repositories[@]}"
do
  IFS='/'; FOLDER=(${repository}) 
  IFS='.'; FOLDER=(${FOLDER[-1]})
  unset IFS;

  echo "Installing: ${FOLDER}"

  if [[ ! -d ${FOLDER} ]]; then
    git clone --depth 1 ${repository}
  fi

  pushd ${FOLDER}
  pip install -v --no-deps -e .
  popd
done
