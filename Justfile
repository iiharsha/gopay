# Database migrations.
service := env("SERVICE", "wallet")
db_url  := env("DB_URL","postgres://gopay:gopay@localhost:5432/" + service + "?sslmode=disable")
migrate_dir := "db/" + service + "/migrations"

migrate := "migrate -path " + migrate_dir + " -database " + db_url

migrate-up:
    @{{migrate}} up

migrate-down:
    @{{migrate}} down 1

migrate-version:
    @{{migrate}} version

migrate-new name:
    @migrate create -ext sql -dir {{migrate_dir}} -seq {{name}}
