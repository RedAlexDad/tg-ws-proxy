RED    := \033[31m
GREEN  := \033[32m
YELLOW := \033[33m
CYAN   := \033[36m
BOLD   := \033[1m
RESET  := \033[0m

IMAGE     := tg-ws-proxy
CONTAINER := tg-ws-proxy
PORT      := 1443
DC_IPS    := "2:149.154.167.220 4:149.154.167.220"
SECRET    := $(shell cat .secret 2>/dev/null)
SERVICE   := tg-ws-proxy
LINK_FILE := $(HOME)/.config/tg-ws-proxy/link

.DEFAULT_GOAL := help

.PHONY: help build rebuild run stop rm restart logs secret link link-file shell install uninstall .secret

help:
	@printf "$(BOLD)Usage:$(RESET)\n"
	@printf "  make $(GREEN)<command>$(RESET)\n\n"
	@printf "$(BOLD)Commands:$(RESET)\n"
	@printf "  $(GREEN)build$(RESET)          Build Docker image\n"
	@printf "  $(GREEN)rebuild$(RESET)        Build without cache\n"
	@printf "  $(GREEN)run$(RESET)            Run container (auto-creates .secret)\n"
	@printf "  $(GREEN)stop$(RESET)           Stop container\n"
	@printf "  $(GREEN)rm$(RESET)             Remove container\n"
	@printf "  $(GREEN)restart$(RESET)        Restart container\n"
	@printf "  $(GREEN)logs$(RESET)           Follow container logs\n"
	@printf "  $(GREEN)link$(RESET)           Show tg://proxy link\n"
	@printf "  $(GREEN)link-file$(RESET)      Save link to $(LINK_FILE)\n"
	@printf "  $(GREEN)secret$(RESET)         Show current secret\n"
	@printf "  $(GREEN)shell$(RESET)          Open shell in running container\n"
	@printf "  $(GREEN)install$(RESET)        Install systemd service (auto-start on boot)\n"
	@printf "  $(GREEN)uninstall$(RESET)      Remove systemd service\n\n"
	@printf "$(BOLD)Docs:$(RESET)\n"
	@printf "  $(CYAN)docs/README.docker.md$(RESET)    Docker setup guide\n"
	@printf "  $(CYAN)docs/BuildFromSource.md$(RESET)  Run from source\n"
	@printf "  $(CYAN)docs/CfProxy.md$(RESET)          Cloudflare proxy domain\n"
	@printf "  $(CYAN)docs/CfWorker.md$(RESET)         Cloudflare Worker relay\n"
	@printf "  $(CYAN)docs/FakeTlsNginx.md$(RESET)     Fake TLS + nginx\n"

.secret:
	@if [ ! -f .secret ]; then \
		openssl rand -hex 16 > .secret; \
		printf "$(YELLOW)Generated secret: $(GREEN)%s$(RESET)\n" "$$(cat .secret)"; \
	fi

build:
	@printf "$(YELLOW)Building image '$(IMAGE)'...$(RESET)\n"
	docker build -t $(IMAGE) .
	@printf "$(GREEN)Done.$(RESET)\n"

rebuild:
	@printf "$(YELLOW)Rebuilding image '$(IMAGE)' (no cache)...$(RESET)\n"
	docker build --no-cache -t $(IMAGE) .
	@printf "$(GREEN)Done.$(RESET)\n"

run: .secret
	@docker rm -f $(CONTAINER) 2>/dev/null || true
	@printf "$(YELLOW)Starting container '$(CONTAINER)'...$(RESET)\n"
	docker run -d \
		--name $(CONTAINER) \
		--restart=always \
		-p $(PORT):$(PORT) \
		-e TG_WS_PROXY_SECRET="$(shell cat .secret)" \
		$(IMAGE):latest
	@printf "$(GREEN)Container started on port $(PORT).$(RESET)\n"
	@sleep 1
	@$(MAKE) link-file
	@$(MAKE) link

stop:
	@printf "$(YELLOW)Stopping container '$(CONTAINER)'...$(RESET)\n"
	docker stop $(CONTAINER) 2>/dev/null || printf "$(RED)Container not running.$(RESET)\n"

rm:
	@printf "$(YELLOW)Removing container '$(CONTAINER)'...$(RESET)\n"
	docker rm -f $(CONTAINER) 2>/dev/null || printf "$(RED)Container not found.$(RESET)\n"

restart:
	@$(MAKE) rm
	@$(MAKE) run

logs:
	docker logs -f $(CONTAINER)

secret:
	@cat .secret 2>/dev/null || printf "$(RED)No .secret file. Run 'make run' first.$(RESET)\n"

link:
	@docker logs $(CONTAINER) 2>&1 | grep -o 'tg://[^ ]*' | head -1 || \
		printf "$(RED)No link found. Is the container running?$(RESET)\n"

link-file:
	@mkdir -p "$(dir $(LINK_FILE))"
	@docker logs $(CONTAINER) 2>&1 | grep -o 'tg://[^ ]*' | head -1 > $(LINK_FILE) 2>/dev/null || true
	@printf "$(GREEN)Link saved to $(LINK_FILE)$(RESET)\n"

shell:
	docker exec -it $(CONTAINER) /bin/sh

install:
	@printf "$(YELLOW)Installing systemd service '$(SERVICE)'...$(RESET)\n"
	@sudo cp $(SERVICE).service /etc/systemd/system/
	@sudo systemctl daemon-reload
	@sudo systemctl enable $(SERVICE)
	@printf "$(GREEN)Service installed and enabled.$(RESET)\n"
	@printf "  Start:  $(GREEN)sudo systemctl start $(SERVICE)$(RESET)\n"
	@printf "  Status: $(GREEN)sudo systemctl status $(SERVICE)$(RESET)\n"
	@printf "  Stop:   $(GREEN)sudo systemctl stop $(SERVICE)$(RESET)\n"
	@printf "  Logs:   $(GREEN)sudo journalctl -u $(SERVICE) -f$(RESET)\n"

uninstall:
	@printf "$(YELLOW)Removing systemd service '$(SERVICE)'...$(RESET)\n"
	-sudo systemctl stop $(SERVICE) 2>/dev/null || true
	-sudo systemctl disable $(SERVICE) 2>/dev/null || true
	-sudo rm -f /etc/systemd/system/$(SERVICE).service
	-sudo systemctl daemon-reload
	@printf "$(GREEN)Service removed.$(RESET)\n"
