MAKEFLAGS += --warn-undefined-variables

.ONESHELL:
.SHELLFLAGS := -o errtrace -o pipefail -o noclobber -o errexit -o nounset -c
SHELL := bash

# host config: ~/.config/homelab/config.mk (rendered by dotfiles/chezmoi from
# [data.homelab] in the private chezmoi.toml), overridden by a repo-local
# local.mk (gitignored, see local.mk.example). CLI variables still win
XDG_CONFIG_HOME ?= $(HOME)/.config
-include $(XDG_CONFIG_HOME)/homelab/config.mk
-include local.mk

# ssh alias of the docker host and the working copy of this repo on it
DEPLOY_HOST ?=
DEPLOY_PATH ?=

# every directory with a compose.yaml is a stack
STACKS := $(patsubst %/compose.yaml,%,$(wildcard */compose.yaml))

PRE_COMMIT_VERSION ?= 4.6
PRE_COMMIT ?= uvx pre-commit@$(PRE_COMMIT_VERSION)
SHELLCHECK_EXCLUDE := -path ./.git

ARGS ?=

define Deploy/Check
	@if [ -z "$(DEPLOY_HOST)" ] || [ -z "$(DEPLOY_PATH)" ]; then
		echo " - DEPLOY_HOST / DEPLOY_PATH not set, see local.mk.example"
		exit 1
	fi
endef

# $(1): stack, $(2): compose arguments
define Remote/Compose
	$(Deploy/Check)
	ssh -t $(DEPLOY_HOST) 'cd $(DEPLOY_PATH)/$(1) && docker compose $(2)'
endef


##@ General


.DEFAULT_GOAL := help
.PHONY: help
help: ## Display this help screen
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} \
		/^[a-zA-Z_0-9\-\\.%]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: stacks
stacks: ## List stacks
	@printf '%s\n' $(STACKS)


##@ Deploy


# never sent to the host; under --delete (without --delete-excluded) excluded
# paths are also left alone on the receiver
DEPLOY_EXCLUDES := .git .claude .idea .DS_Store /local.mk
# host state that must never be overwritten or deleted from here: .env and
# the filters and the rendered service configs (config/*.yml) are filled on
# the host, rclone rewrites rclone.conf on token refresh. Excluded from sending and protected with an rsync 'P' filter
# against --delete. secrets.pull/push below move exactly this set
DEPLOY_PROTECT := .env config/rclone.conf config/*.filter config/*.yml

# --no-owner --no-group: files land as the ssh user, config/ dirs keep the
# uid the containers write with
DEPLOY_RSYNC = rsync -av --delete --no-owner --no-group \
	$(foreach e,$(DEPLOY_EXCLUDES),--exclude=$(e)) \
	$(foreach p,$(DEPLOY_PROTECT),--exclude=$(p) --filter='P $(p)') \
	./ "$(DEPLOY_HOST):$(DEPLOY_PATH)/"

.PHONY: deploy.diff
deploy.diff: ## Preview deploy (rsync dry-run: what gets sent/deleted)
	$(Deploy/Check)
	$(DEPLOY_RSYNC) --dry-run

.PHONY: deploy
deploy: ## Sync the repo to DEPLOY_HOST:DEPLOY_PATH (host-only files protected)
	$(Deploy/Check)
	$(DEPLOY_RSYNC)

.PHONY: networks
networks: ## Create the shared docker networks on the host (idempotent)
	$(Deploy/Check)
	ssh $(DEPLOY_HOST) 'sh $(DEPLOY_PATH)/networks.sh'


##@ Secrets (host-side files, gitignored here)


# <stack>/.env, <stack>/config/*.filter and <stack>/config/*.yml are copies of the same paths under
# ~/.config/homelab/<stack>/ (dotfiles renders them from [data.homelab.*] in
# its private toml), refreshed whenever the rendered one is newer; secrets.push
# then ships them. Stacks without rendered files keep hand-written ones
HOST_FILES := $(patsubst $(XDG_CONFIG_HOME)/homelab/%,%,$(wildcard $(XDG_CONFIG_HOME)/homelab/*/.env $(XDG_CONFIG_HOME)/homelab/*/config/*.filter $(XDG_CONFIG_HOME)/homelab/*/config/*.yml))

$(HOST_FILES): %: $(XDG_CONFIG_HOME)/homelab/%
	cp "$<" "$@"

# only the DEPLOY_PROTECT set, nothing else; the tree copy is the laptop's
# backup of what the host holds (rclone.conf is rewritten there on token
# refresh) and the seed for a new host
SECRETS_RSYNC = rsync -av --no-owner --no-group --prune-empty-dirs \
	--include='*/' $(foreach p,$(DEPLOY_PROTECT),--include='$(p)') --exclude='*'

.PHONY: secrets.pull
secrets.pull: ## Copy .env, rclone.conf, config/*.filter, config/*.yml of every stack from the host into the tree
	$(Deploy/Check)
	$(SECRETS_RSYNC) "$(DEPLOY_HOST):$(DEPLOY_PATH)/" ./

# after the copy every stack's .env and config/ are chowned to the PUID:PGID
# its .env names (0 when unset), so a service running as that uid can read
# the 0600 files rsync just created as the ssh user
.PHONY: secrets.push
secrets.push: $(HOST_FILES) ## Copy them to the host (.env, filters and service configs from dotfiles, rclone.conf from the tree); never deletes
	$(Deploy/Check)
	$(SECRETS_RSYNC) --chmod=F600 ./ "$(DEPLOY_HOST):$(DEPLOY_PATH)/"
	ssh $(DEPLOY_HOST) 'cd $(DEPLOY_PATH) && for s in $(STACKS); do \
		[ -f "$$s/.env" ] || continue; \
		u=$$(sed -n "s/^PUID=//p" "$$s/.env"); g=$$(sed -n "s/^PGID=//p" "$$s/.env"); \
		chown -R "$${u:-0}:$${g:-0}" "$$s/.env" "$$s/config" 2>/dev/null || true; \
	done'


##@ Stacks (on the host)


.PHONY: ps
ps: ## docker compose ps of every stack
	$(Deploy/Check)
	ssh $(DEPLOY_HOST) 'for s in $(STACKS); do echo "== $$s"; (cd $(DEPLOY_PATH)/$$s && docker compose ps); done'

up.%: ## docker compose up -d <stack>, ARGS= passes extra flags
	$(call Remote/Compose,$*,up -d $(ARGS))

down.%: ## docker compose down <stack>
	$(call Remote/Compose,$*,down $(ARGS))

restart.%: ## docker compose restart <stack>
	$(call Remote/Compose,$*,restart $(ARGS))

update.%: ## docker compose pull + up -d <stack>
	$(call Remote/Compose,$*,pull && docker compose up -d)

logs.%: ## docker compose logs -f <stack>
	$(call Remote/Compose,$*,logs -f --tail=200 $(ARGS))

compose.%: ## docker compose <ARGS> in <stack>, e.g. make compose.cloud-sync ARGS="config"
	$(call Remote/Compose,$*,$(ARGS))

.PHONY: shell
shell: ## ssh to the host
	$(Deploy/Check)
	ssh $(DEPLOY_HOST)


##@ Lint


.PHONY: lint
lint: lint.compose lint.shellcheck lint.pre-commit ## Run all linters

.PHONY: lint.compose
lint.compose: ## Validate every stack's compose.yaml against its .env.example
	@for s in $(STACKS); do
		echo "== $$s"
		docker compose --project-directory "$$s" --env-file "$$s/.env.example" -f "$$s/compose.yaml" config -q
	done

.PHONY: lint.shellcheck
lint.shellcheck: ## Run shellcheck on the repo's shell scripts
	find . -type d \( $(SHELLCHECK_EXCLUDE) \) -prune -o -type f -name '*.sh' \
		-exec shellcheck --format=gcc {} +

.PHONY: lint.pre-commit
lint.pre-commit: ## Run the pre-commit hooks on every file
	$(PRE_COMMIT) run --all-files $(ARGS)
