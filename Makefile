.PHONY: up refresh warm logs stop status network help

# Up: start the stack. The first run pulls the ~2.3 GB database image and builds Martin.
up: network
	docker compose up -d --build --wait
	docker compose run --rm orm-patch
	@echo "✅ Up. Test a tile: docker run --rm --network trainlog_network curlimages/curl -sI http://orm:5000/railway_line_high/8/132/88"

# Warm: render every tile up to zoom 8 into the nginx cache (also run by refresh)
warm:
	docker compose run --rm warm

# Refresh: pull upstream's latest database, rebuild Martin from the same commit, swap both
refresh: network
	./refresh.sh

logs:
	docker compose logs -f

stop:
	docker compose down

status:
	docker compose ps

# Network: orm joins trainlog_network (shared with the services_proxy nginx); create it
# if this machine doesn't have it yet
network:
	@docker network inspect trainlog_network >/dev/null 2>&1 || docker network create trainlog_network

help:
	@echo "Available commands:"
	@echo "  make up       - Start the stack (pulls the database image on first run)"
	@echo "  make warm     - Render every tile up to zoom 8 into the cache"
	@echo "  make refresh  - Pull the latest upstream database and rebuild Martin"
	@echo "  make logs     - Follow logs"
	@echo "  make stop     - Stop the stack"
	@echo "  make status   - Show container status"
	@echo "  make help     - Show this help message"
