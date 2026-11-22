BEGIN;
-- debit or credit: the two sides of every entry
CREATE TYPE entry_direction AS enum(
'debit',
'credit'
);

-- account: where money belongs, like user's wallet, bank account etc.
CREATE TABLE accounts(
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    owner_id UUID,
    name TEXT NOT NULL CHECK(name <> ''),
    currency TEXT NOT NULL CHECK(currency ~'^[A-Z]{3}$'),
    normal_balance entry_direction NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(id, currency)
);

CREATE INDEX accounts_owner_id_idx ON accounts(owner_id);

-- transaction: one row per movement of money.
CREATE TABLE transactions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    description TEXT NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- entry: the individual debit and credit records that describe the movement.
CREATE TABLE entries (
    id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_id uuid NOT NULL REFERENCES transactions (id),
    account_id uuid NOT NULL,
    direction entry_direction NOT NULL,
    amount bigint NOT NULL CHECK (amount > 0),
    currency text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    -- each entry's currency must match the account's currency.
    FOREIGN KEY (account_id, currency) REFERENCES accounts (id, currency)
);

-- pg does not index FK for us.
CREATE INDEX entries_transaction_id_idx ON entries(transaction_id);
CREATE INDEX entries_account_id_idx ON entries(account_id);

-- every transaction must have entries, and its debits must be equal to its credits
-- in every currency. checked at COMMIT, once all the entries exist.
CREATE FUNCTION check_transaction_balanced() RETURNS trigger
LANGUAGE plpgsql AS $$
DECLARE
    tx_id uuid;
BEGIN
    IF TG_TABLE_NAME = 'transactions' THEN
        tx_id := NEW.id;
    ELSE
        tx_id := NEW.transaction_id;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM ENTRIES WHERE transaction_id = tx_id) THEN
        RAISE EXCEPTION 'transaction % has no entries', tx_id
            USING ERRCODE = 'check_violation';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM entries
        WHERE transaction_id = tx_id
        GROUP BY currency
        HAVING sum(CASE direction WHEN 'debit' THEN amount ELSE -amount END) <> 0
    ) THEN
        RAISE EXCEPTION 'transaction % is not balanced', tx_id
            USING ERRCODE = 'check_violation';
    END IF;

    RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER transactions_balanced
    AFTER INSERT ON transactions
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION check_transaction_balanced();

CREATE CONSTRAINT TRIGGER entries_balanced
    AFTER INSERT ON entries
    DEFERRABLE INITIALLY DEFERRED
    FOR EACH ROW EXECUTE FUNCTION check_transaction_balanced();

-- the ledger is append only: mistakes are fixed with a reversing transaction.
CREATE FUNCTION forbid_ledger_changes() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% is append-only, post a reversing transaction instead', TG_TABLE_NAME
        USING ERRCODE = 'restrict_violation';
END;
$$;

CREATE TRIGGER transactions_append_only
    BEFORE UPDATE OR DELETE ON transactions
    FOR EACH ROW EXECUTE FUNCTION forbid_ledger_changes();

CREATE TRIGGER entries_append_only
    BEFORE UPDATE OR DELETE ON entries
    FOR EACH ROW EXECUTE FUNCTION forbid_ledger_changes();

-- balances are derived from entries, it is never stored independently.
CREATE VIEW account_balances AS
SELECT
    a.id AS account_id,
    a.name,
    a.currency,
    COALESCE(
        SUM(
            CASE
                WHEN e.direction = a.normal_balance
                    THEN e.amount
                ELSE -e.amount
            END
    ), 0)::bigint AS balance
FROM accounts a
LEFT JOIN entries e ON e.account_id = a.id
GROUP BY a.id;

COMMIT;
