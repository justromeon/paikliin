{-# LANGUAGE QuasiQuotes #-}

module Db (connect, runScript, migrate, insertLink, findLink, deleteLink) where

import Control.Monad (forM_, unless)
import Data.Int (Int64)
import Data.List (isSuffixOf, sort)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Text.IO qualified as TIO
import Data.Time (UTCTime)
import Domain
import Hasql.Connection (Connection)
import Hasql.Connection qualified as Connection
import Hasql.Connection.Settings qualified as Settings
import Hasql.Session (Session)
import Hasql.Session qualified as Session
import Hasql.Statement (Statement)
import Hasql.TH (maybeStatement, resultlessStatement, rowsAffectedStatement, singletonStatement)
import System.Directory (listDirectory)
import System.FilePath ((</>))

connect :: Text -> IO Connection
connect url = Connection.acquire (Settings.connectionString url) >>= either (fail . show) pure

run :: Connection -> Session a -> IO a
run conn session = Connection.use conn session >>= either (fail . show) pure

-- | Raw SQL, possibly several statements, no parameters. For DDL and test resets.
runScript :: Connection -> Text -> IO ()
runScript conn = run conn . Session.script

migrate :: Connection -> FilePath -> IO ()
migrate conn dir = do
  runScript
    conn
    "CREATE TABLE IF NOT EXISTS schema_migrations \
    \(name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())"

  files <- sort . filter (".sql" `isSuffixOf`) <$> listDirectory dir
  forM_ files $ \file -> do
    applied <- run conn (Session.statement (T.pack file) isApplied)
    unless applied $ do
      sql <- TIO.readFile (dir </> file)
      run conn $ do
        Session.script ("BEGIN;\n" <> sql)
        Session.statement (T.pack file) recordMigration
        Session.script "COMMIT"
      putStrLn ("migrated: " <> file)
 where
  isApplied =
    [singletonStatement|
      select exists (select 1 from schema_migrations where name = $1 :: text) :: bool |]
  recordMigration =
    [resultlessStatement|
      insert into schema_migrations (name) values ($1 :: text) |]

-- Operations
insertLink :: Connection -> UTCTime -> NewLink -> IO Link
insertLink conn now new = run conn $ do
  linkId <- (Session.statement () nextId)
  let link =
        Link
          { code = encodeBase62 (fromIntegral linkId)
          , target = new.target
          , createdAt = now
          , expiresAt = new.expiresAt
          }

  Session.statement
    (linkId, shortCodeText link.code, longUrlText link.target, link.createdAt, link.expiresAt)
    insertRow

  pure link
 where
  nextId :: Statement () Int64
  nextId = [singletonStatement| select nextval('link_id_seq') :: int8 |]
  insertRow =
    [resultlessStatement|
      insert into links (id, code, target, created_at, expires_at)
      values ($1 :: int8, $2 :: text, $3 :: text, $4 :: timestamptz, $5 :: timestamptz?)
    |]

findLink :: Connection -> ShortCode -> IO (Maybe Link)
findLink conn code = do
  row <- run conn (Session.statement (shortCodeText code) selectLink)
  pure (toLink <$> row)
 where
  toLink (target, createdAt, expiresAt) = Link code (unsafeLongUrl target) createdAt expiresAt
  selectLink =
    [maybeStatement|
      select target :: text, created_at :: timestamptz, expires_at :: timestamptz?
      from links where code = $1 :: text
    |]

deleteLink :: Connection -> ShortCode -> IO Bool
deleteLink conn code = do
  n <- run conn (Session.statement (shortCodeText code) deleteRow)
  pure (n > 0)
 where
  deleteRow = [rowsAffectedStatement| delete from links where code = $1 :: text |]
