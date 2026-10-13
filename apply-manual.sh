#!/bin/bash
# Applica i manifest di k8s/manual/, sostituendo i segnaposto coi valori di .env.
#
# Servono perche' ArgoCD non esegue envsubst: se questi file stessero nella
# kustomization, sincronizzerebbe i segnaposto e l'Ingress verrebbe rifiutato a
# ogni giro.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f .env ]; then
  echo "Manca .env: copialo da .env.dist e valorizzalo."
  exit 1
fi

set -a
. ./.env
set +a

# Elenco esplicito delle variabili: envsubst senza argomenti sostituirebbe
# qualunque $NOME presente nei manifest, comprese cose che non c'entrano.
VARS='${MOVIEMATCH_HOST}'

for VAR in MOVIEMATCH_HOST; do
  if [ -z "${!VAR:-}" ]; then
    echo "$VAR non e' valorizzata in .env"
    exit 1
  fi
done

if ! kubectl get namespace movie-match >/dev/null 2>&1; then
  echo "Il namespace movie-match non esiste: lancia prima"
  echo "  kubectl apply -f k8s/namespace.yaml"
  exit 1
fi

# --dry-run=server come primo passo: meglio scoprire un valore sbagliato
# adesso che a meta' apply.
for MODE in "--dry-run=server" ""; do
  for FNAME in k8s/manual/*.yaml; do
    envsubst "$VARS" < "$FNAME" | kubectl apply $MODE -f -
  done
done
