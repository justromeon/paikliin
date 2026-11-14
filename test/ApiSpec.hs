module ApiSpec (spec) where

import Api (Env (Env), app)
import Data.ByteString.Lazy qualified as LBS
import Data.IORef (modifyIORef, newIORef, readIORef, writeIORef)
import Data.Text qualified as T
import Data.Time (UTCTime (UTCTime), addUTCTime, fromGregorian)
import Db qualified
import Hasql.Connection (Connection)
import Network.HTTP.Types (hContentType, methodPost)
import System.Environment (getEnv)
import Test.Hspec
import Test.Hspec.Wai

t0 :: UTCTime
t0 = UTCTime (fromGregorian 2026 1 1) 0

spec :: Spec
spec = do
  clockRef <- runIO (newIORef t0)
  conn <- runIO connectTest

  let env = Env conn (readIORef clockRef)
      advance secs = liftIO $ modifyIORef clockRef (addUTCTime secs)
      -- runs before every test: resets clock and data
      fresh = do
        writeIORef clockRef t0
        Db.runScript conn "TRUNCATE links; ALTER SEQUENCE link_id_seq RESTART"
        pure (app env)

  with fresh $ describe "API" $ do
    it "creates a link" $
      postLink "{\"url\":\"https://example.com\"}" `shouldRespondWith` 201

    it "redirects to the target" $ do
      _ <- postLink "{\"url\":\"https://example.com\"}"
      get "/q0U" `shouldRespondWith` 302{matchHeaders = ["Location" <:> "https://example.com"]}

    it "rejects a bad URL" $
      postLink "{\"url\":\"ftp://nahhh\"}" `shouldRespondWith` 400

    it "returns a 404 for unknown codes" $
      get "/zzz" `shouldRespondWith` 404

    it "returns 410 once a link has expired" $ do
      _ <- postLink "{\"url\":\"https://example.com\",\"ttlSeconds\":60}"
      advance 61
      get "/q0U" `shouldRespondWith` 410

    it "deletes a link" $ do
      _ <- postLink "{\"url\":\"https://example.com\"}"
      delete "/links/q0U" `shouldRespondWith` 204
      get "/q0U" `shouldRespondWith` 404

connectTest :: IO Connection
connectTest = do
  conn <- Db.connect . T.pack =<< getEnv "TEST_DATABASE_URL"
  Db.migrate conn "migrations"
  pure conn

postLink :: LBS.ByteString -> WaiSession st SResponse
postLink = request methodPost "/links" [(hContentType, "application/json")]
