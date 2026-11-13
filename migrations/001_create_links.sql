CREATE SEQUENCE link_id_seq START 100000;  -- first code is "q0U", not "1"

CREATE TABLE links (
  id          bigint      PRIMARY KEY,
  code        text        NOT NULL,
  target      text        NOT NULL,
  created_at  timestamptz NOT NULL,
  expires_at  timestamptz
);

CREATE UNIQUE INDEX links_code_idx ON links (code);
