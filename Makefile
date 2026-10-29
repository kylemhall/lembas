# Lembas. Everything runs in Docker: the host perl has none of the dependencies.
COMPOSE := docker compose
RUN     := $(COMPOSE) run --rm test
JOBS    ?= 4
IMAGE   ?= lembas:local

.PHONY: help test dev build shell clean

help: ## Show this help (default)
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-11s %s\n", $$1, $$2}'

test: ## Run the suite in the test image, against the compose MariaDB
	$(RUN) prove -r -j$(JOBS) t

dev: ## Run morbo on http://localhost:8080 with MariaDB (settings from .env)
	$(COMPOSE) --profile dev up --build

build: ## Build the production image $(IMAGE)
	docker build --target app -t $(IMAGE) .

shell: ## Open a shell in the test image
	$(RUN) bash

clean: ## Remove cover_db and every compose container and volume, the database included
	rm -rf cover_db
	$(COMPOSE) --profile dev --profile test down -v --remove-orphans
