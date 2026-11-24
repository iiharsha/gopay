// Package postgres connects services to PostgreSQL through a pgx connectoin pool.
package postgres

import (
	"context"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// NewPool create a connection pool for the database at dsn, and checks that the
// database is reachable before returning it.
func NewPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
    cfg, err := pgxpool.ParseConfig(dsn)
    if err != nil {
        return nil, fmt.Errorf("postgres: parse dsn: %w", err)
    }

    // Pool sizing: a few warm connections, and hard cap well below
    // Postgres's max_connections, so many replicas can share one server.
    cfg.MinConns = 2
    cfg.MaxConns = 10

    // Recycle connections now and then, so load rebalances after a failover.
    // The jitter stops every connection from reconecting at the same moment.
    cfg.MaxConnLifetime = time.Hour
    cfg.MaxConnLifetimeJitter = 5 * time.Minute
    cfg.MaxConnIdleTime = 15 * time.Minute
    cfg.HealthCheckPeriod =  30 * time.Second
    cfg.ConnConfig.ConnectTimeout = 5 * time.Second

    pool, err := pgxpool.NewWithConfig(ctx, cfg)
    if err != nil {
        return nil, fmt.Errorf("postgres: create pool: %w", err)
    }

    // The pool connects lazily. Ping now, so a bad DSN or a database that is
    // down, fails at startup, instead of on the first request.
    pingCtx, cancel := context.WithTimeout(ctx, 5 * time.Second)
    defer cancel()
    if err := pool.Ping(pingCtx); err != nil {
        pool.Close()
        return nil, fmt.Errorf("postgres: ping: %w", err)
    }
    return pool, nil
}
