
Trigger single build:
```bash
gh workflow run build-single-image.yml -R versatiles-org/versatiles-docker -F name="alpine" -F platform="linux/amd64" -F tag="v0.5.6"
```

Build locally:
```bash
docker build --progress="plain" --file="docker/frontend-scratch.Dockerfile" .
docker buildx build --platform="linux/amd64" --progress="plain" --file="docker/basic-alpine.Dockerfile" .
```

Build and test Docker:
```bash
docker buildx build --platform=linux/amd64 --progress=plain --file=docker/basic-alpine.Dockerfile --tag=test . && docker run -it --rm test serve --auto-shutdown 1000 -p 8088 "https://download.versatiles.org/planet-20230605.versatiles"
```

