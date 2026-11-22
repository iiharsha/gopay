-- Runs once, when the postgres data volume is first created.
-- One database per service;  each service owns its own data.
CREATE DATABASE wallet;
CREATE DATABASE auth;
CREATE DATABASE transfer;

