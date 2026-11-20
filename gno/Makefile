.PHONY: test test-docker

# Runs the tests with GNOROOT naming a gno checkout built as the Dockerfile
# builds it, and that checkout's gno on PATH.
test:
	python3 scripts/test.py

# Builds gno and runs the tests in Docker, with networking off.
test-docker:
	DOCKER_BUILDKIT=1 docker build --progress plain -f Dockerfile --target tests .
