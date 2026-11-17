SERVICE ?= wallet
DB_URL ?= postgres://gopay:gopay@localhost:5432/$(SERVICE)?sslmode=disable
MIGRATE := migrate -path db/$(SERVICE)/migrations -database "$(DB_URL)"

migrate-up:
    @$(MIGRATE) up

migrate-down:
    @$(MIGRATE) down 1

migrate-version:
    @$(MIGRATE) version

migrate-new:
    @test -n "$(name)" || (echo "usage: make migrate-new name=add_something" && exit 1)
    migrate create -ext sql -dir db/$(SERVICE)/migrations -seq $(name)
