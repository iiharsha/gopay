// Package wallet is the wallet service: accounts, balances and the ledger.
package wallet

import (
	"context"
	"errors"
	"fmt"
	"math"

	"github.com/google/uuid"
	"github.com/iiharsha/gopay/internal/wallet/walletdb"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type (
	Account        = walletdb.Account
	AccountBalance = walletdb.AccountBalance
	Entry          = walletdb.Entry
	NewAccount     = walletdb.CreateAccountParams
	Direction      = walletdb.EntryDirection
)

const (
	Debit  = walletdb.EntryDirectionDebit
	Credit = walletdb.EntryDirectionCredit
)

// ErrAccountNotFound is returned when an accound does not exist.
var ErrAccountNotFound = errors.New("wallet: account not found")

// Store is the wallet's repository later (data access). It wraps the sqlc queries,
// and owns the database transactions.
type Store struct {
	pool *pgxpool.Pool
	q    *walletdb.Queries
}

// NewStore returns a Store that run its queries on pool.
func NewStore(pool *pgxpool.Pool) *Store {
	return &Store{pool: pool, q: walletdb.New(pool)}
}

// CreateAccount opens a new account. OwnerID is nil for systems account.
func (s *Store) CreateAccount(ctx context.Context, a NewAccount) (Account, error) {
	acc, err := s.q.CreateAccount(ctx, a)
	if err != nil {
		return Account{}, fmt.Errorf("create account: %w", err)
	}
	return acc, nil
}

func (s *Store) Account(ctx context.Context, id uuid.UUID) (Account, error) {
	acc, err := s.q.GetAccount(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return Account{}, ErrAccountNotFound
	}
	if err != nil {
		return Account{}, fmt.Errorf("get account %s: %w", id, err)
	}
	return acc, nil
}

// Balance returns an account's balance, derived from it's entries by the
// account_balances view. Amounts are minor units of the account's currency.
func (s *Store) Balance(ctx context.Context, id uuid.UUID) (AccountBalance, error) {
	b, err := s.q.GetAccountBalance(ctx, id)
	if errors.Is(err, pgx.ErrNoRows) {
		return AccountBalance{}, ErrAccountNotFound
	}
	if err != nil {
		return AccountBalance{}, fmt.Errorf("get account %s: %w", id, err)
	}
	return b, nil
}

// Entries returns a page of an account's entries, newset first. Pass 0 as
// before for the first page, then the id of the last entry you received.
func (s *Store) Entries(ctx context.Context, id uuid.UUID, before int64,
    limit int32) ([]Entry, error) {
        if before <= 0 {
            before = math.MaxInt64
        }
        entries, err := s.q.ListEntriesByAccount(ctx, walletdb.ListEntriesByAccountParams{
            AccountID: id,
            BeforeID: before,
            PageSize: limit,
        })
        if err != nil {
            return nil, fmt.Errorf("list entries %s: %w", id, err)
        }
        return entries, nil
}
