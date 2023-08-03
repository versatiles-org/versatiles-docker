
Trigger single build:
```bash
gh workflow run build-single-image.yml -R versatiles-org/versatiles-docker -F name="alpine" -F platform="linux/amd64" -F tag="v0.5.6"
```

Build locally:
```bash
docker build --progress="plain" --file="docker/frontend-scratch.Dockerfile" .
docker buildx build --platform="linux/arm64" --progress="plain" --file="docker/basic-alpine.Dockerfile" .
```