# movie-match-k8s

Manifest Kubernetes per il deploy di movie-match sul cluster di casa. Kustomize piatto, come
`photovault-k8s`.

```
k8s/
├── kustomization.yaml    # resources + blocco images: (i tag dei rilasci)
├── argocd.yaml           # Application — FUORI dalla kustomization, applicata a mano una volta
├── namespace.yaml
├── postgres.yaml         # PV hostPath + PVC + Deployment (postgres:17.6)
├── services.yaml         # postgres, ui-svc, api-svc
├── api.yaml
├── ui.yaml
├── manual/
│   └── ingress.yaml      # ${MOVIEMATCH_HOST}, applicato con ./apply-manual.sh
└── secrets/              # SOPS+age, applicati con ./decrypt.sh + kubectl
    ├── kustomization.yaml
    └── secrets-pg.yaml   # PGDATABASE / PGUSER / PGPASSWORD
```

Fuori da ArgoCD stanno solo `secrets/` (ArgoCD non sa decifrare SOPS) e `manual/` (ArgoCD non
esegue `envsubst`). Tutto il resto è GitOps.

## File locali, fuori dal repo

Accanto a `k8s/`, **dentro `movie-match-k8s/`**, ci sono file che esistono solo sul PC da cui si
fa il deploy:

```
movie-match-k8s/              # radice di questo repo
├── .gitignore                # ignora private/, .env e decrypted (sotto)
├── private/                  # DA CREARE QUI, a mano (non dentro k8s/)
│   └── age-key.txt           # chiave age PRIVATA: decifra i secret, non va mai committata
├── public-age-keys.txt       # chiave age pubblica: va committata, serve a encrypt.sh
├── .env                      # copia di .env.dist con MOVIEMATCH_HOST
├── decrypted                 # lock, esiste solo fra decrypt.sh ed encrypt.sh
├── k8s/
└── *.sh
```

`decrypt.sh` cerca la chiave esattamente in `movie-match-k8s/private/age-key.txt`: altrove non
la trova. Gli script si spostano da soli nella loro cartella, quindi funzionano da qualunque
directory si lancino; i comandi qui sotto invece vanno eseguiti da dentro `movie-match-k8s/`.

`private/` è ignorata dal `.gitignore` del repo, ma **non è un backup**: se la chiave
privata va persa, i secret cifrati nel repo non si possono più decifrare (si rigenerano da
capo). Va copiata anche in un posto sicuro, per esempio un password manager.

## Prima installazione, in ordine

```bash
# tutto da dentro movie-match-k8s/

# 0. hook di protezione, una volta per clone
git config core.hooksPath .githooks

# 1. chiave age del progetto: la privata in movie-match-k8s/private/ (gitignorata),
#    la pubblica in movie-match-k8s/public-age-keys.txt (da committare)
mkdir -p private
age-keygen -o private/age-key.txt
age-keygen -y private/age-key.txt > public-age-keys.txt
chmod 600 private/age-key.txt

# 2. i valori di questa installazione
cp .env.dist .env                     # valorizzare MOVIEMATCH_HOST

# 3. il secret, dal modello
cp k8s/secrets/secrets-pg.yaml.dist k8s/secrets/secrets-pg.yaml
# ... valorizzare PGPASSWORD (openssl rand -hex 24) ...
./encrypt.sh

# 4. namespace, secret, ingress
kubectl apply -f k8s/namespace.yaml
./decrypt.sh && kubectl apply -k k8s/secrets && ./encrypt.sh
./apply-manual.sh

# 5. l'applicazione
kubectl apply -k k8s

# 6. lo schema del database
#    il port-forward resta in primo piano: lanciarlo in un secondo terminale.
#    Porta locale 5433: la 5432 e' gia' del Postgres di sviluppo (movie-match-pg).
kubectl -n movie-match port-forward deployment/postgres 5433:5432
#    Porta e password del cluster passate sulla riga di comando: vincono su
#    movie-match-db/.env, che resta puntato al Postgres di sviluppo.
#    Il repo movie-match-db va clonato accanto a questo (stessa cartella padre).
#    Fra parentesi: si torna in movie-match-k8s/ per il passo 7.
(cd ../movie-match-db && PG_PORT=5433 PG_PASSWORD='<PGPASSWORD del secret>' node app.js -e local up)

# 7. ArgoCD, una volta sola
kubectl apply -f k8s/argocd.yaml
```

Il `pre-commit` (in `.githooks/`) rifiuta il commit se esiste il lock
`decrypted`, se un file di `k8s/secrets/` non è cifrato, o se in `k8s/manual/` c'è un hostname
vero al posto del segnaposto.

## Rilascio

Come photovault: ogni componente si rilascia dal **suo** repo, con un tag.

```bash
# da movie-match-api/ oppure da movie-match-ui/
git tag v0.2.0 && git push --tags
```

La GitHub Action di quel repo (`.github/workflows/build.yml`) builda e pubblica l'immagine
(`pirraste/movie-match-api` o `pirraste/movie-match-ui`), poi clona **questo** repo e scrive il
tag in `k8s/kustomization.yaml` con un commit su `main`; ArgoCD sincronizza. Se api e ui
rilasciano insieme, il secondo push viene rifiutato e la Action riparte dall'ultimo `main`.

Le versioni di api e ui sono indipendenti: un rilascio che cambia lo schema va fatto **dopo**
la migration (`movie-match-db`, a mano, vedi passo 6), e se tocca sia API sia UI vanno taggati
entrambi i repo.

Una volta sola, su **ciascuno** dei repo `pste/movie-match-api` e `pste/movie-match-ui`
(Settings → Secrets and variables → Actions):
- variabile `DOCKERHUB_USERNAME`;
- segreto `DOCKERHUB_TOKEN` (access token Docker Hub con permesso Read & Write);
- segreto `K8S_REPO_TOKEN`: un token GitHub con permesso di push su `pste/movie-match-k8s`
  (fine-grained: solo quel repo, *Contents: Read and write*).

### A mano, senza la Action

```bash
TAG=v0.1.0
docker build -f ../movie-match-api/.docker/Dockerfile -t pirraste/movie-match-api:$TAG ../movie-match-api
docker build -f ../movie-match-ui/.docker/Dockerfile --build-arg VITE_APP_VERSION=$TAG -t pirraste/movie-match-ui:$TAG ../movie-match-ui
docker push pirraste/movie-match-api:$TAG && docker push pirraste/movie-match-ui:$TAG
cd k8s && kustomize edit set image pirraste/movie-match-api:$TAG pirraste/movie-match-ui:$TAG
```

## Risorse

App leggera: api 20m/64Mi → 500m/192Mi, ui 10m/32Mi → 200m/128Mi, postgres 50m/96Mi → 1/256Mi.

## Comandi utili

```bash
kubectl -n movie-match get pods,pvc
kubectl -n movie-match logs -f deployment/api
kubectl kustomize k8s | kubectl apply --dry-run=server -f -
```
