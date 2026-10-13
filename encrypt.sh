#!/bin/bash
# Ricifra i manifest di k8s/secrets/ e rimuove il lock file.
cd "$(dirname "$0")"
export SOPS_AGE_RECIPIENTS=$(<public-age-keys.txt)

SECFILES="secrets-pg"

for SECFILE in $SECFILES; do
  FNAME="./k8s/secrets/$SECFILE.yaml"
  if [ -f $FNAME ]; then
    echo "Encrypting $FNAME ..."
    sops --encrypt --in-place --age ${SOPS_AGE_RECIPIENTS} $FNAME
  fi
done

# rm lock file
rm -f decrypted
