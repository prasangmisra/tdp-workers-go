DOCKER_COMPOSE=docker compose
PLATFORM=$(shell uname -s)

ifeq ("x$(PLATFORM)","xLinux")
DOCKER_COMPOSE=docker-compose
endif
