Development container

A single target can be built e.g.
```
docker build . --target cares
```

Tag the container locally such that a new version can be tested without waiting for the CI to finish building the container.

```
docker build . -t ghcr.io/nabto/nabto-development-container:master
```
