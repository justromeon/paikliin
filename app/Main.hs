module Main (main) where

import Api (Env (Env), app)
import Data.Text qualified as T
import Data.Time (getCurrentTime)
import Db qualified
import Network.Wai.Handler.Warp (run)
import System.Environment (getArgs, getEnv, lookupEnv)

main :: IO ()
main = do
  conn <- Db.connect . T.pack =<< getEnv "DATABASE_URL"
  getArgs >>= \case
    ["migrate"] -> Db.migrate conn "migrations"
    _ -> do
      port <- maybe 8080 read <$> lookupEnv "PORT"
      putStrLn $ "listening on " <> show port
      run port $ app (Env conn getCurrentTime)
