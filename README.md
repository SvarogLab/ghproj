# ghproj

A container image of [ghproj](https://github.com/suzuki-shunsuke/ghproj), which adds GitHub issues
and pull requests to a GitHub Project. The image runs ghproj once and exits, so a scheduler such as
a Kubernetes CronJob decides how often it runs.

ghproj reads its token from `GITHUB_TOKEN` only. A GitHub App's installation token lives an hour,
so the image's entrypoint mints a fresh one from the app's private key on every run; a static token
can be given instead.

## Image

`ghcr.io/svaroglab/ghproj:<version>`, for `linux/amd64`. The build checks
the ghproj release's checksums against their Sigstore signature before it unpacks the binary.

The container runs as UID 65532 and writes nothing to disk, so it works with a read-only root
filesystem.

## Settings

| Variable | Meaning |
| --- | --- |
| `GHPROJ_CONFIG` | Path to the ghproj configuration file. |
| `GHPROJ_CONFIG_TEXT` | The configuration itself, instead of a file. |
| `GITHUB_APP_ID` | The GitHub App's ID. |
| `GITHUB_APP_INSTALLATION_ID` | The ID of the app's installation on the organisation that owns the project. |
| `GITHUB_APP_PRIVATE_KEY_FILE` | Path to the app's private key, PEM. |
| `GITHUB_TOKEN` | A token to use as is; when set, the three app settings are not read. |

Arguments, if any, replace the default `add`, as in `ghproj <arguments>`.

The entrypoint exits 2 when the settings are incomplete, 1 when GitHub gives no installation token,
and with ghproj's own status otherwise.

## Setting up

### The project

Create the project in the organisation and note its node ID:

```sh
gh project list --owner example-org --format json --jq '.projects[] | [.number, .id, .title] | @tsv'
```

In the project's **Workflows**, the built-in *Item added to project*, *Item closed* and *Pull
request merged* set the status of what ghproj adds and keep it current; ghproj only adds items.

### The GitHub App

Fine-grained personal access tokens cannot reach GitHub Projects, so an organisation's project is
reached through an app.

1. In the organisation's settings, under **Developer settings → GitHub Apps**, create an app with
   the webhook turned off and these permissions:
   - Repository: **Metadata** read-only, **Issues** read-only, **Pull requests** read-only.
   - Organisation: **Projects** read and write.
2. Generate a private key and keep the downloaded PEM file.
3. Install the app on the organisation, on all repositories or on the ones to track. The
   installation ID is the number at the end of the installation's settings URL, or:

   ```sh
   gh api /orgs/example-org/installation --jq .id
   ```

   That call needs a token the app has not issued, such as an organisation owner's.

### The configuration

A query with `-project:` leaves out what is already on the board, so each run fetches only what is
new. Use `is:issue` or `is:pr` to take one kind only.

```yaml
entries:
  - project_id: PVT_xxxxxxxxxxxxxxxx
    query: |
      is:open
      archived:false
      owner:example-org
      -project:example-org/1
```

Every field and the `expr` filter are described in
[ghproj's README](https://github.com/suzuki-shunsuke/ghproj#configuration).

## Running it in Kubernetes

The app's credentials go into a Secret, the configuration into a ConfigMap:

```sh
kubectl create secret generic ghproj-app \
  --from-literal=app-id=123456 \
  --from-literal=installation-id=7890123 \
  --from-file=private-key.pem=./example-app.private-key.pem
kubectl create configmap ghproj-config --from-file=ghproj.yaml
```

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: ghproj
spec:
  schedule: "* * * * *"
  # A run that has not finished when the next is due is still searching; a second one would add
  # the same items again.
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 1
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 0
      activeDeadlineSeconds: 300
      template:
        spec:
          restartPolicy: Never
          securityContext:
            runAsNonRoot: true
            seccompProfile:
              type: RuntimeDefault
          containers:
            - name: ghproj
              image: ghcr.io/svaroglab/ghproj:0.1.0
              env:
                - name: GHPROJ_CONFIG
                  value: /config/ghproj.yaml
                - name: GITHUB_APP_PRIVATE_KEY_FILE
                  value: /app/private-key.pem
                - name: GITHUB_APP_ID
                  valueFrom:
                    secretKeyRef: {name: ghproj-app, key: app-id}
                - name: GITHUB_APP_INSTALLATION_ID
                  valueFrom:
                    secretKeyRef: {name: ghproj-app, key: installation-id}
              securityContext:
                allowPrivilegeEscalation: false
                readOnlyRootFilesystem: true
                capabilities:
                  drop: [ALL]
              resources:
                requests: {cpu: 10m, memory: 32Mi}
                limits: {memory: 128Mi}
              volumeMounts:
                - {name: config, mountPath: /config, readOnly: true}
                - {name: app, mountPath: /app, readOnly: true}
          volumes:
            - name: config
              configMap:
                name: ghproj-config
            - name: app
              secret:
                secretName: ghproj-app
                items:
                  - {key: private-key.pem, path: private-key.pem}
```

Each run logs how many items its search found and exits 0 when it adds them all, or finds none.
With an app, a run also mints one installation token.

## Development

`tests/entrypoint.sh` runs the entrypoint against stand-ins for ghproj and curl; openssl and jq are
the real ones. CI runs it under dash, bash and busybox sh:

```sh
tests/entrypoint.sh "busybox sh"
```

The code style, and the checks that hold it, are in [docs/CODESTYLE.md](docs/CODESTYLE.md).

A release starts with the **Release PR** workflow, run by hand from the Actions tab. It opens a
pull request with the next version and the regenerated `CHANGELOG.md`; merging it tags `vX.Y.Z`,
publishes the image `X.Y.Z` and creates the GitHub Release, all in that merge's CI run. The tag is
pushed first: if the image or the release then fails, **Re-run failed jobs** finishes them for the
same tag, which a second tag of the same version could not. Renovate
moves the ghproj version in the `Dockerfile` and the Alpine base.

## License

Apache-2.0, see [LICENSE](LICENSE). ghproj itself is MIT-licensed by its author.
