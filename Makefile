# Lembas. Everything runs in Docker: the host perl has none of the dependencies.
COMPOSE := docker compose
RUN     := $(COMPOSE) run --rm test
# The checks that need no database
CHECK   := $(COMPOSE) run --rm --no-deps test
JOBS    ?= 4
IMAGE   ?= lembas:local

.PHONY: help all test coverage cover lint critic tidy-check format dev dev-otel migrate build smoke shell clean

help: ## Show this help (default)
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-11s %s\n", $$1, $$2}'

all: lint test coverage ## What CI runs: the checks, the suite, then the 100% coverage gate

test: ## Run the suite in the test image, against the compose MariaDB
	$(RUN) prove -r -j$(JOBS) t

coverage: ## Run the suite under Devel::Cover, fail unless lib/ is 100% covered (script/coverage)
	$(RUN) script/coverage

cover: coverage ## Same as coverage

lint: critic tidy-check ## Perl::Critic and the formatting check

critic: ## Run Perl::Critic (.perlcriticrc) on lib, script and t
	$(CHECK) prove t/critic.t

tidy-check: ## Fail if a file is not tidy (what the pre-commit hook runs)
	$(CHECK) prove t/tidy.t

format: ## Format the code with perltidy and prettier (writes the files)
	$(CHECK) script/tidy

dev: ## Run morbo on http://localhost:8080 with MariaDB (settings from .env)
	$(COMPOSE) --profile dev up --build

dev-otel: ## Same as dev, with OpenTelemetry: a collector, and Jaeger on http://localhost:16686
	OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318 $(COMPOSE) --profile dev --profile otel up --build

migrate: ## Apply the migrations to the development database
	$(COMPOSE) --profile dev run --rm dev script/lembas migrate

build: ## Build the production image $(IMAGE)
	docker build --target app -t $(IMAGE) .

smoke: build ## Run the production image with a MariaDB and a collector, and check it (script/smoke)
	script/smoke $(IMAGE)

shell: ## Open a shell in the test image
	$(RUN) bash

clean: ## Remove cover_db and every compose container and volume, the database included
	rm -rf cover_db
	$(COMPOSE) --profile dev --profile test --profile otel down -v --remove-orphans
