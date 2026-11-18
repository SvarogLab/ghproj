# ghproj

A container image of [ghproj](https://github.com/suzuki-shunsuke/ghproj), which adds GitHub issues
and pull requests to a GitHub Project. The image runs `ghproj add` once and exits, so a scheduler
such as a Kubernetes CronJob decides how often it runs.

## Image

`ghcr.io/svaroglab/ghproj:<version>`, for `linux/amd64` and `linux/arm64`: the ghproj binary
from its own release on `distroless/static`. The build checks the release's checksums against their
Sigstore signature, bound to the ghproj repository and tag, before it unpacks the binary.

The container runs as UID 65532 and writes nothing to disk, so it works with a read-only root
filesystem. Arguments replace the default `add`, as in `ghproj <arguments>`.

## Settings

| Variable | Meaning |
| --- | --- |
| `GHPROJ_CONFIG` | Path to the ghproj configuration file. |
| `GHPROJ_CONFIG_TEXT` | The configuration itself, instead of a file. |
| `GITHUB_TOKEN` | The token ghproj reaches GitHub with; see [The token](#the-token). |

## Setting up

### The project

Create the project in the organisation and note its node ID:

```sh
gh project list --owner example-org --format json --jq '.projects[] | [.number, .id, .title] | @tsv'
```

In the project's **Workflows**, the built-in *Item added to project*, *Item closed* and *Pull
request merged* set the status of what ghproj adds and keep it current; ghproj only adds items.

### The token

A fine-grained personal access token, created under **Settings → Developer settings → Personal
access tokens → Fine-grained tokens**:

- **Resource owner**: the organisation that owns the project.
- **Repository access**: all repositories, or the ones to track.
- **Repository permissions**: **Issues** and **Pull requests** read-only.
- **Organization permissions**: **Projects** read and write.

An organisation that requires approval of fine-grained tokens has to approve it before it works.
Items ghproj adds are recorded as added by the token's owner. A project owned by a user rather than
an organisation is out of a fine-grained token's reach and needs a classic token with the `project`
and `repo` scopes.

### The configuration

A query with `-project:` leaves out what is already on the board, so each run fetches only what is
new. With a fine-grained token, GitHub's search finds nothing unless the query names `is:issue` or
`is:pr`, and says so only in its REST API; GraphQL, which ghproj uses, returns no items and no
error. Issues and pull requests therefore take an entry each:

```yaml
entries:
  - project_id: PVT_xxxxxxxxxxxxxxxx
    query: |
      is:issue
      is:open
      archived:false
      owner:example-org
      -project:example-org/1
  - project_id: PVT_xxxxxxxxxxxxxxxx
    query: |
      is:pr
      is:open
      archived:false
      owner:example-org
      -project:example-org/1
```

Every field and the `expr` filter are described in
[ghproj's README](https://github.com/suzuki-shunsuke/ghproj#configuration).

## Running it in Kubernetes

The token goes into a Secret, the configuration into a ConfigMap:

```sh
kubectl create secret generic ghproj-token --from-file=token=./token
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
                - name: GITHUB_TOKEN
                  valueFrom:
                    secretKeyRef: {name: ghproj-token, key: token}
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
          volumes:
            - name: config
              configMap:
                name: ghproj-config
```

Each run logs how many items its search found and exits 0 when it adds them all, or finds none.

## Development

CI lints the Dockerfile and builds the image on every pull request. The code style, and the checks
that hold it, are in [docs/CODESTYLE.md](docs/CODESTYLE.md).

A release carries the version of the ghproj it ships. It starts with the **Release PR** workflow,
run by hand from the Actions tab, which takes that version from `GHPROJ_VERSION` in the `Dockerfile`
and opens a pull request with it and the regenerated `CHANGELOG.md`; merging it tags `vX.Y.Z`,
publishes the image `X.Y.Z` and creates the GitHub Release, all in that merge's CI run. The tag is
pushed first: if the image or the release then fails, **Re-run failed jobs** finishes them for the
same tag, which a second tag of the same version could not. Renovate moves the ghproj version in a
pull request of its own, and the base images and actions together in another. A change without a new
ghproj ships with the next ghproj release: its version is already tagged, and Release PR refuses it.

## License

Apache-2.0, see [LICENSE](LICENSE). ghproj itself is MIT-licensed by its author.
