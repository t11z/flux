# Self-hosted GitLab runner on Ubuntu (Docker executor)

A step-by-step for standing up a **self-hosted** GitLab runner on a fresh Ubuntu server that
runs this pipeline with the **Docker executor**, using Docker from Ubuntu's native repo
(`docker.io`). The usual reason to self-host: your Panorama sits on a private management
network that gitlab.com's shared runners cannot reach.

## What the host needs vs. what the job needs

This is the key point. With the **Docker executor**, each job runs inside a container started
from the image in `.gitlab-ci.yml` (`python:3.12-slim`), and `before_script` installs the
per-job tools (terraform, curl) *inside that container*. So:

- **The Ubuntu host needs only:** Docker + `gitlab-runner`. Nothing else.
- **terraform / python3 / curl are NOT installed on the host** — they come from the image and
  `before_script`. The shipped `.gitlab-ci.yml` works on a self-hosted Docker runner unchanged.
- **No Docker-in-Docker, no `privileged` mode:** the mock Panorama and terraform both run
  inside the single job container. (You'd only need `privileged`/DinD if you later build images
  in CI — this pipeline doesn't.)

If you would rather bake the tools into the image and drop `before_script`, see
[*Optional: a prebuilt tools image*](#optional-a-prebuilt-tools-image) at the end.

## 0. Prerequisites

- Ubuntu 22.04 or 24.04 LTS, with `sudo`.
- Outbound network from the host to: `gitlab.com` (jobs + artifacts), Docker Hub
  (`registry-1.docker.io`, for the `python:3.12-slim` image), and `releases.hashicorp.com`
  (the terraform binary the `before_script` fetches). In an air-gapped network, mirror these
  or use a prebuilt image (see the end).

## 1. Install Docker from the native Ubuntu repo

```bash
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker

# smoke test (should print "Hello from Docker!")
sudo docker run --rm hello-world
```

`docker.io` is Ubuntu's packaged Docker engine — slightly older than Docker's own `docker-ce`
repo, but perfectly fine as a runner backend. No extra Docker config is required.

## 2. Install gitlab-runner

The runner is not in the native Ubuntu repo at a useful version, so use GitLab's official
package repo:

```bash
curl -fsSL "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
sudo apt-get install -y gitlab-runner
```

The package creates a `gitlab-runner` system user and a systemd service. Make sure that user
can talk to Docker (the install usually adds it to the `docker` group; verify and restart):

```bash
sudo usermod -aG docker gitlab-runner
sudo systemctl restart gitlab-runner
```

## 3. Create the runner in GitLab and get a token

In the project: **Settings ▸ CI/CD ▸ Runners ▸ New project runner**.

- Platform: **Linux**.
- **Tick "Run untagged jobs".** ← important: the flux jobs carry no `tags:`, so a tags-only
  runner would sit idle and the pipeline would never start.
- (Optional) add a tag like `flux` if you also add matching `tags:` to the jobs.

Create it and copy the authentication token (`glrt-…`).

## 4. Register the runner with the Docker executor

```bash
sudo gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.com" \
  --token "glrt-XXXXXXXXXXXXXXXXXXXX" \
  --executor "docker" \
  --docker-image "python:3.12-slim" \
  --docker-pull-policy "if-not-present" \
  --description "flux-ubuntu-docker"
```

- `--docker-image` is only the *fallback* image for jobs that don't name one; flux jobs name
  `python:3.12-slim` themselves, so this just keeps behaviour consistent.
- `--docker-pull-policy if-not-present` caches images across jobs (faster). Use `always` if you
  want to always pull the latest tag.

This writes `/etc/gitlab-runner/config.toml`. Bump concurrency if you like:

```toml
concurrent = 4

[[runners]]
  name = "flux-ubuntu-docker"
  url = "https://gitlab.com"
  executor = "docker"
  [runners.docker]
    image = "python:3.12-slim"
    pull_policy = ["if-not-present"]
    # privileged = false   # default; leave false — this pipeline needs no DinD
```

## 5. Verify

```bash
sudo gitlab-runner verify          # token is valid, runner reachable
sudo gitlab-runner list            # shows the registered runner
sudo systemctl status gitlab-runner
```

In GitLab, the runner now shows **online** under Settings ▸ CI/CD ▸ Runners. Push a commit (or
**Build ▸ Pipelines ▸ Run pipeline**) and the runner picks up `validate` → `plan`; `apply` and
`commit` remain manual gates. The first job is slower (it pulls `python:3.12-slim` and the
terraform binary); later jobs reuse the cached image.

## Reaching a real Panorama on a private network

This is the payoff of self-hosting. Put the runner host where it can route to Panorama's
management interface (TCP/443), then set the CI/CD variables from
[README.md](README.md) (`PANOS_PROTOCOL=https`, `PANOS_HOSTNAME`, `PANOS_PORT=443`, masked
`TF_VAR_panos_api_key`). The job container inherits the host's network, so if the host can
reach Panorama, so can terraform.

## Troubleshooting

| Symptom | Cause / fix |
|---------|-------------|
| Pipeline stays "pending", runner idle | Runner not allowed to run **untagged** jobs (step 3), or job `tags:` don't match. |
| `Cannot connect to the Docker daemon` | `gitlab-runner` user not in `docker` group, or `docker` service not running (step 1–2). |
| `Pulling image ... no such host` / timeout | Host can't reach Docker Hub / `releases.hashicorp.com` — check egress/proxy (step 0). |
| `permission denied` on `/var/run/docker.sock` | Same as above — re-run `usermod -aG docker gitlab-runner` and restart the service. |

## Optional: a prebuilt tools image

If you prefer the host's runner to use an image that already bundles terraform + python3 + curl
(so you can delete `before_script` from `.gitlab-ci.yml`), build one and push it to a registry
the runner can read:

```dockerfile
FROM python:3.12-slim
ARG TERRAFORM_VERSION=1.9.8
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl unzip ca-certificates \
 && curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o /tmp/tf.zip \
 && unzip -oq /tmp/tf.zip -d /usr/local/bin \
 && rm -rf /tmp/tf.zip /var/lib/apt/lists/*
```

Then set that tag as `default.image` and remove the `before_script`. For a single self-hosted
runner the in-pipeline `before_script` is usually simpler — a prebuilt image mainly pays off
across many runners or in an air-gapped setup.
